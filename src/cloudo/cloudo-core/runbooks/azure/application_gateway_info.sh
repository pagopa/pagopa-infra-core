#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage:"
  echo "  $0 <APPGW_NAME> <APPGW_RG> [--metric NAME] [--aggregation TYPE] [--interval ISO8601]"
  echo
  echo "Examples:"
  echo "  $0 my-appgw my-rg"
  echo "  $0 my-appgw my-rg --metric TotalRequests --aggregation Total --interval PT5M"
}

# Require at least 2 positional args
if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

APPGW_NAME="$1"; shift
APPGW_RG="$1"; shift

# Defaults
METRIC="TotalRequests"
AGGREGATION="Total"
INTERVAL="PT5M"
HEALTH_EXIT_CODE=0

require_value() {
  if [[ $# -lt 1 || -z "${1:-}" || "${1:-}" == --* ]]; then
    echo "Missing value for option." >&2
    usage
    exit 1
  fi
}

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --metric) shift; require_value "${1:-}"; METRIC="$1"; shift ;;
    --aggregation) shift; require_value "${1:-}"; AGGREGATION="$1"; shift ;;
    --interval) shift; require_value "${1:-}"; INTERVAL="$1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! az account show >/dev/null 2>&1; then
  echo "Logging into Azure..."
  if [[ -n "${AZURE_CLIENT_ID:-}" ]]; then
    az login --identity --client-id "$AZURE_CLIENT_ID" >/dev/null
  else
    az login --identity >/dev/null
  fi
fi

APPGW_ID="$(az network application-gateway show \
  --name "$APPGW_NAME" \
  --resource-group "$APPGW_RG" \
  --query id -o tsv)"

if [[ -z "${APPGW_ID:-}" ]]; then
  echo "Could not find Application Gateway '$APPGW_NAME' in resource group '$APPGW_RG'." >&2
  exit 1
fi

APPGW_PROVISIONING_STATE="$(az network application-gateway show \
  --name "$APPGW_NAME" \
  --resource-group "$APPGW_RG" \
  --query provisioningState -o tsv)"

APPGW_OPERATIONAL_STATE="$(az network application-gateway show \
  --name "$APPGW_NAME" \
  --resource-group "$APPGW_RG" \
  --query operationalState -o tsv)"

LISTENERS_COUNT="$(az network application-gateway show \
  --name "$APPGW_NAME" \
  --resource-group "$APPGW_RG" \
  --query "length(httpListeners)" -o tsv)"

RULES_COUNT="$(az network application-gateway show \
  --name "$APPGW_NAME" \
  --resource-group "$APPGW_RG" \
  --query "length(requestRoutingRules)" -o tsv)"

BACKEND_HEALTH_JSON="$(az network application-gateway show-backend-health \
  --resource-group "$APPGW_RG" \
  --name "$APPGW_NAME" \
  -o json)"

# Fetch metrics (prefer --metrics, fallback to --metric for older az versions)
if METRICS_JSON="$(az monitor metrics list --resource "$APPGW_ID" --metrics "$METRIC" --aggregation "$AGGREGATION" --interval "$INTERVAL" -o json 2>/dev/null)"; then
  :
else
  METRICS_JSON="$(az monitor metrics list --resource "$APPGW_ID" --metric "$METRIC" --aggregation "$AGGREGATION" --interval "$INTERVAL" -o json)"
fi

# Summary output
echo "Application Gateway: $APPGW_NAME"
echo "Resource Group:      $APPGW_RG"
echo "Metric:              $METRIC"
echo "Aggregation:         $AGGREGATION"
echo "Interval:            $INTERVAL"
echo

echo "Health checks"
echo "-------------"
echo "Provisioning State:  $APPGW_PROVISIONING_STATE"
echo "Operational State:   ${APPGW_OPERATIONAL_STATE:-N/A}"
echo "Listeners:           $LISTENERS_COUNT"
echo "Routing Rules:       $RULES_COUNT"

if [[ "$APPGW_PROVISIONING_STATE" != "Succeeded" ]]; then
  echo "CRITICAL: provisioningState is '$APPGW_PROVISIONING_STATE' (expected: Succeeded)."
  HEALTH_EXIT_CODE=1
fi

if [[ -n "${APPGW_OPERATIONAL_STATE:-}" && "$APPGW_OPERATIONAL_STATE" != "Running" ]]; then
  echo "CRITICAL: operationalState is '$APPGW_OPERATIONAL_STATE' (expected: Running)."
  HEALTH_EXIT_CODE=1
fi

if command -v jq >/dev/null 2>&1; then
  TOTAL_BACKENDS="$(echo "$BACKEND_HEALTH_JSON" | jq '[.backendAddressPools[]?.backendHttpSettingsCollection[]?.servers[]?] | length')"
  UNHEALTHY_BACKENDS="$(echo "$BACKEND_HEALTH_JSON" | jq '[.backendAddressPools[]?.backendHttpSettingsCollection[]?.servers[]? | select(.health != "Healthy")] | length')"

  echo "Backend Servers:     $TOTAL_BACKENDS"
  echo "Unhealthy Backends:  $UNHEALTHY_BACKENDS"

  if [[ "$UNHEALTHY_BACKENDS" -gt 0 ]]; then
    echo "CRITICAL: found unhealthy backends:"
    echo "$BACKEND_HEALTH_JSON" | jq -r '
      .backendAddressPools[]?
      | .backendAddressPool.id as $poolId
      | .backendHttpSettingsCollection[]?
      | .backendHttpSettings.id as $settingId
      | .servers[]?
      | select(.health != "Healthy")
      | "  - pool=\($poolId | split("/")[-1]) setting=\($settingId | split("/")[-1]) address=\(.address) health=\(.health)"'
    HEALTH_EXIT_CODE=1
  fi
else
  echo "WARNING: jq not found; backend detailed health check skipped."
fi

echo

# Print data points
if command -v jq >/dev/null 2>&1; then
  COUNT=$(echo "$METRICS_JSON" | jq -r '.value[0].timeseries[0].data | length // 0')
  if [[ "$COUNT" -eq 0 ]]; then
    echo "No data available for the selected period."
    exit "$HEALTH_EXIT_CODE"
  fi
  echo "Timestamp, Value"
  echo "$METRICS_JSON" | jq -r --arg agg "$AGGREGATION" '
    .value[0].timeseries[0].data[]
    | [.timeStamp, .[($agg | ascii_downcase)]]
    | @csv'
else
  echo "jq not found: printing raw JSON output."
  echo "$METRICS_JSON"
fi

exit "$HEALTH_EXIT_CODE"
