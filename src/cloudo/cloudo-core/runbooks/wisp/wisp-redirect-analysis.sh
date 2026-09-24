#!/usr/bin/env bash
set -euo pipefail

if [[ "${MONITOR_CONDITION:-}" == "Resolved" ]]; then
  echo "The WISP redirect availability alert is resolved. No analysis is required."
  exit 0
fi

ENV_SHORT="${CLOUDO_ENVIRONMENT_SHORT:-}"

case "$ENV_SHORT" in
  d|u|p) ;;
  *)
    echo "Unsupported or missing CLOUDO_ENVIRONMENT_SHORT: '${ENV_SHORT}'. Expected d, u or p." >&2
    exit 1
    ;;
esac

WORKSPACE_NAME="pagopa-${ENV_SHORT}-law"
WORKSPACE_RESOURCE_GROUP="pagopa-${ENV_SHORT}-monitor-rg"

if ! az account show >/dev/null 2>&1; then
  echo "Logging in to Azure with the ClouDo managed identity..."
  if [[ -n "${AZURE_CLIENT_ID:-}" ]]; then
    az login --identity --client-id "$AZURE_CLIENT_ID" >/dev/null
  else
    az login --identity >/dev/null
  fi
fi

if ! WORKSPACE_ID="$(az monitor log-analytics workspace show \
  --resource-group "$WORKSPACE_RESOURCE_GROUP" \
  --workspace-name "$WORKSPACE_NAME" \
  --query customerId \
  --output tsv)"; then
  echo "Unable to resolve Log Analytics workspace '${WORKSPACE_NAME}'." >&2
  exit 1
fi

if [[ -z "$WORKSPACE_ID" ]]; then
  echo "Log Analytics workspace '${WORKSPACE_NAME}' has an empty customerId." >&2
  exit 1
fi

KQL_QUERY="$(cat <<'KQL'
AzureDiagnostics
| where TimeGenerated >= ago(30m)
| where Category == "GatewayLogs"
| extend RequestPath = tolower(tostring(parse_url(url_s).Path))
| where RequestPath == "/wisp-converter/redirect/api/v1/payments"
| extend
    Code = tolong(responseCode_d),
    BackendPath = tolower(tostring(parse_url(backendUrl_s).Path))
| summarize
    Requests = count(),
    Redirect302 = countif(Code == 302),
    Responses200 = countif(Code == 200),
    StaticError200 = countif(Code == 200 and BackendPath == "/pagopa-wispconverter/static/error"),
    Payments200 = countif(Code == 200 and BackendPath == "/pagopa-wispconverter/payments"),
    Errors5xx = countif(Code >= 500),
    OtherCodes = countif(Code !in (200, 302))
    by TimeSlot = bin(TimeGenerated, 5m)
| extend
    RedirectAvailability = round(100.0 * todouble(Redirect302) / Requests, 2),
    ExpectedAvailability = round(
      iff(
        Requests >= 500,
        95.0,
        iff(
          Requests <= 100,
          50.0,
          (todouble(Requests - 100) / 400.0 * 45.0) + 50.0
        )
      ),
      2
    )
| extend BelowThreshold = Requests > 10 and RedirectAvailability < ExpectedAvailability
| order by TimeSlot asc
| serialize
| extend
    PreviousTimeSlot = prev(TimeSlot),
    PreviousBelowThreshold = coalesce(prev(BelowThreshold), false)
| extend ConsecutiveBreach =
    BelowThreshold
    and PreviousBelowThreshold
    and datetime_diff("minute", TimeSlot, PreviousTimeSlot) == 5
| project
    TimeSlot,
    Requests,
    Redirect302,
    Responses200,
    StaticError200,
    Payments200,
    Errors5xx,
    OtherCodes,
    RedirectAvailability,
    ExpectedAvailability,
    BelowThreshold,
    ConsecutiveBreach
| order by TimeSlot desc
KQL
)"

echo "WISP redirect diagnostic analysis"
echo "Environment: ${ENV_SHORT}"
echo "Workspace: ${WORKSPACE_NAME}"
echo "Endpoint: /wisp-converter/redirect/api/v1/payments"
echo "Observation window: 30 minutes"
echo

if ! QUERY_OUTPUT="$(az monitor log-analytics query \
  --workspace "$WORKSPACE_ID" \
  --analytics-query "$KQL_QUERY" \
  --timespan PT30M \
  --output table)"; then
  echo "The Log Analytics query failed." >&2
  exit 1
fi

if [[ -z "${QUERY_OUTPUT//[[:space:]]/}" ]]; then
  echo "No WISP redirect requests were found in the last 30 minutes."
  exit 0
fi

echo "$QUERY_OUTPUT"