#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Runs a script on an Azure VM with a run command that is deleted at the end.
# Called by the local-exec of terraform_data.icinga_configure (05_vm.tf) and
# terraform_data.icinga_theme (07_theme.tf), runs where Terraform runs (Azure
# CLI logged in).
# A managed run command left on the VM (azurerm_virtual_machine_run_command)
# is run again at every start and blocks it, so it is never kept.
# -----------------------------------------------------------------------------
: "${SUBSCRIPTION_ID:?}" "${RESOURCE_GROUP:?}" "${VM_NAME:?}" "${LOCATION:?}" "${RUN_NAME:?}" "${SCRIPT_PATH:?}"

# "@<path>" of a missing file would be sent as the script itself
[[ -s "$SCRIPT_PATH" ]] || { echo "script not found: $SCRIPT_PATH" >&2; exit 1; }

log="${TMPDIR:-/tmp}/${VM_NAME}-${RUN_NAME}.log"

az_run() {
  az vm run-command "$@" --subscription "$SUBSCRIPTION_ID" \
    --resource-group "$RESOURCE_GROUP" --vm-name "$VM_NAME" --name "$RUN_NAME"
}

args=()
if [[ -n "${PARAMETERS:-}" ]]; then
  args+=(--parameters)
  for p in $PARAMETERS; do args+=("$p=${!p}"); done
fi
if [[ -n "${PROTECTED_PARAMETERS:-}" ]]; then
  args+=(--protected-parameters)
  for p in $PROTECTED_PARAMETERS; do args+=("$p=${!p}"); done
fi

# the run command must not stay on the VM, also when the script fails
trap 'az_run delete --yes --output none || echo "WARNING: delete run command $RUN_NAME on $VM_NAME manually" >&2' EXIT

# synchronous: waits for the end of the script. "@file": the script is read by
# the Azure CLI, not passed on the command line (size limit of an argument)
az_run create --location "$LOCATION" \
  --async-execution false --timeout-in-seconds 1800 \
  --script "@${SCRIPT_PATH}" \
  "${args[@]}" \
  --output none

az_run show --instance-view --query instanceView --output json > "$log"
exit_code="$(az_run show --instance-view --query instanceView.exitCode --output tsv)"
if [[ "$exit_code" != "0" ]]; then
  echo "$RUN_NAME failed on $VM_NAME (exit code $exit_code), see $log" >&2
  exit 1
fi
echo "$RUN_NAME completed on $VM_NAME, see $log"
