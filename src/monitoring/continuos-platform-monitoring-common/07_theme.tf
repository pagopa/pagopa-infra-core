# -----------------------------------------------------------------------------
# Icinga Web theme: "pagopa" module (templates/theme), theme pagopa/default
# set as default in config.ini (icinga-configure.sh). Separate run: a change
# to the theme doesn't re-run the whole Icinga configuration
# -----------------------------------------------------------------------------
locals {
  icinga_theme_dir = "${path.module}/templates/theme"

  icinga_theme_hash = substr(sha256(jsonencode([
    filesha256("${path.module}/templates/icinga-theme.sh"),
    { for f in sort(fileset(local.icinga_theme_dir, "**")) : f => filesha256("${local.icinga_theme_dir}/${f}") },
  ])), 0, 8)
}

# Run once by templates/run-command.sh with a run command deleted at the end.
# Re-run when the theme changes or Icinga is configured again (VM replaced).
# Requires the Azure CLI logged in
resource "terraform_data" "icinga_theme" {
  triggers_replace = [
    terraform_data.icinga_configure.id,
    local.icinga_theme_hash,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    environment = {
      SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id
      RESOURCE_GROUP  = azurerm_resource_group.icinga_rg.name
      VM_NAME         = azurerm_linux_virtual_machine.icinga.name
      LOCATION        = azurerm_linux_virtual_machine.icinga.location
      RUN_NAME        = "icinga-theme-${local.icinga_theme_hash}"
      PARAMETERS      = "THEME_HASH"
      THEME_HASH      = local.icinga_theme_hash
      THEME_DIR       = local.icinga_theme_dir
      THEME_SCRIPT    = "${path.module}/templates/icinga-theme.sh"
      RUN_COMMAND     = "${path.module}/templates/run-command.sh"
    }

    # icinga-theme.sh with the files of the theme (base64) in place of "@THEME_FILES@"
    command = <<-EOT
      set -euo pipefail
      export SCRIPT_PATH="$(mktemp)"
      trap 'rm -f "$SCRIPT_PATH"' EXIT

      marker='# @THEME_FILES@'
      grep -qx "$marker" "$THEME_SCRIPT"
      {
        sed "/^$marker\$/,\$d" "$THEME_SCRIPT"
        (cd "$THEME_DIR" && find . -type f | sed 's|^\./||' | sort) | while read -r f; do
          [[ "$f" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "unexpected file name: $f" >&2; exit 1; }
          echo "mkdir -p \"\$STAGE/$(dirname "$f")\""
          echo "base64 -d > \"\$STAGE/$f\" <<'THEME_FILE'"
          base64 < "$THEME_DIR/$f" | tr -d '\n'
          printf '\nTHEME_FILE\n'
        done
        sed "1,/^$marker\$/d" "$THEME_SCRIPT"
      } > "$SCRIPT_PATH"

      "$RUN_COMMAND"
    EOT
  }
}
