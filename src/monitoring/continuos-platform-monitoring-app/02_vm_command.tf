data "azurerm_virtual_machine" "icinga_vm" {
  name                = "${local.project}-icinga-vm"
  resource_group_name = "${local.project}-icinga-rg"
}


resource "terraform_data" "icinga_vm_bp" {
  triggers_replace = [
    data.azurerm_virtual_machine.icinga_vm.id,
    sha256(local.bp_content),
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    environment = {
      SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id
      RESOURCE_GROUP  = data.azurerm_virtual_machine.icinga_vm.resource_group_name
      VM_NAME         = data.azurerm_virtual_machine.icinga_vm.name
      LOCATION        = data.azurerm_virtual_machine.icinga_vm.location
      RUN_NAME        = "${local.project}-icinga-vm-bp-${local.bp_name}"
      BP_DIR          = local.bp_dir
      BP_NAME         = local.bp_name
      BP_FILE         = local.bp_file
      BP_SHA256       = sha256(local.bp_content)
      BP_CONTENT_B64  = base64encode(local.bp_content)
    }

    # script eseguito sulla VM, con il contenuto del Business Process (base64)
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
      mkdir -p '$BP_DIR'
      TMP="\$(mktemp '$BP_DIR/.$BP_NAME.XXXXXX')"
      base64 -d > "\$TMP" <<'BP'
      $BP_CONTENT_B64
      BP
      chown --reference='$BP_DIR' "\$TMP"
      chmod 0660 "\$TMP"
      mv -f "\$TMP" '$BP_FILE'
      echo "written $BP_FILE (sha256 $BP_SHA256)"
      SCRIPT

      # il run command non deve restare sulla VM, anche se lo script fallisce
      trap 'rm -f "$script"; az_run delete --yes --output none || echo "WARNING: cancellare a mano il run command $RUN_NAME su $VM_NAME" >&2' EXIT

      # sincrono: attende la fine dello script. "@file": lo script è letto dalla
      # Azure CLI, non passato sulla riga di comando
      az_run create --location "$LOCATION" \
        --async-execution false --timeout-in-seconds 600 \
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
