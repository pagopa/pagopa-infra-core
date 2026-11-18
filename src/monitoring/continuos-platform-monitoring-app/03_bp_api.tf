locals {
  bp_api_dir = "${path.module}/business_process_api"
  bp_api_files = {
    "app/__init__.py"  = filebase64("${local.bp_api_dir}/app/__init__.py")
    "app/bpfile.py"    = filebase64("${local.bp_api_dir}/app/bpfile.py")
    "app/main.py"      = filebase64("${local.bp_api_dir}/app/main.py")
    "requirements.txt" = filebase64("${local.bp_api_dir}/requirements.txt")
  }
  bp_api_unit = filebase64("${local.bp_api_dir}/deploy/bp-api.service")
  bp_api_env  = filebase64("${local.bp_api_dir}/deploy/bp-api.env")

  bp_api_hash = sha256(join("", concat(
    [for k in sort(keys(local.bp_api_files)) : "${k}:${local.bp_api_files[k]}"],
    [local.bp_api_unit, local.bp_api_env, local.bp_file],
  )))
}

# Installa (idempotente) la business process API sulla VM Icinga come servizio systemd
resource "terraform_data" "icinga_vm_bp_api" {
  triggers_replace = [
    data.azurerm_virtual_machine.icinga_vm.id,
    local.bp_api_hash,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    environment = {
      SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id
      RESOURCE_GROUP  = data.azurerm_virtual_machine.icinga_vm.resource_group_name
      VM_NAME         = data.azurerm_virtual_machine.icinga_vm.name
      LOCATION        = data.azurerm_virtual_machine.icinga_vm.location
      RUN_NAME        = "${local.project}-icinga-vm-bp-api"
      BP_FILE         = local.bp_file
      BP_API_HASH     = local.bp_api_hash
      UNIT_B64        = local.bp_api_unit
      ENV_B64         = local.bp_api_env
      FILES_B64       = join(" ", [for k in sort(keys(local.bp_api_files)) : "${k}=${local.bp_api_files[k]}"])
    }

    command = <<-EOT
      set -euo pipefail
      script="$(mktemp)"
      log="$${TMPDIR:-/tmp}/$VM_NAME-$RUN_NAME.log"
      az_run() {
        az vm run-command "$@" --subscription "$SUBSCRIPTION_ID" \
          --resource-group "$RESOURCE_GROUP" --vm-name "$VM_NAME" --name "$RUN_NAME"
      }

      cat > "$script" <<SCRIPT
      #!/usr/bin/env bash
      set -euo pipefail
      APP=/opt/bp-api
      command -v python3 >/dev/null || { echo "python3 mancante sulla VM" >&2; exit 1; }
      python3 -m venv --help >/dev/null 2>&1 || { echo "modulo python3 venv mancante sulla VM" >&2; exit 1; }

      id bp-api >/dev/null 2>&1 || useradd --system --home-dir "\$APP" --shell /usr/sbin/nologin bp-api
      usermod -aG icingaweb2 bp-api

      mkdir -p "\$APP/app"
      for entry in $FILES_B64; do
        rel="\$${entry%%=*}"
        mkdir -p "\$APP/\$(dirname "\$rel")"
        echo "\$${entry#*=}" | base64 -d > "\$APP/\$rel"
      done
      [ -d "\$APP/venv" ] || python3 -m venv "\$APP/venv"
      "\$APP/venv/bin/pip" install --quiet -r "\$APP/requirements.txt"
      chown -R root:bp-api "\$APP"
      chmod -R g+rX,o-rwx "\$APP"

      [ -f /etc/default/bp-api ] || echo '$ENV_B64' | base64 -d > /etc/default/bp-api
      echo '$UNIT_B64' | base64 -d > /etc/systemd/system/bp-api.service

      # la API scrive direttamente sul file (nessun temp file): serve il permesso di gruppo sul solo file
      if [ -f '$BP_FILE' ]; then
        chgrp icingaweb2 '$BP_FILE'
        chmod 0660 '$BP_FILE'
      fi

      systemctl daemon-reload
      systemctl enable bp-api.service
      systemctl restart bp-api.service
      sleep 3
      systemctl is-active --quiet bp-api.service
      echo "bp-api installed (sha256 $BP_API_HASH)"
      SCRIPT

      trap 'rm -f "$script"; az_run delete --yes --output none || echo "WARNING: cancellare a mano il run command $RUN_NAME su $VM_NAME" >&2' EXIT

      az_run create --location "$LOCATION" \
        --async-execution false --timeout-in-seconds 900 \
        --script "@$script" --output none

      az_run show --instance-view --query instanceView --output json > "$log"
      exit_code="$(az_run show --instance-view --query instanceView.exitCode --output tsv)"
      if [[ "$exit_code" != "0" ]]; then
        echo "$RUN_NAME fallito su $VM_NAME (exit code $exit_code), vedi $log" >&2
        exit 1
      fi
      echo "$RUN_NAME completato su $VM_NAME, vedi $log"
    EOT
  }
}
