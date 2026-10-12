#!/usr/bin/env bash

# Read-only analysis of recent WISP redirect telemetry for ClouDo alerts.
#
# The report contains one row per five-minute UTC bucket, newest first:
# - TimeUTC: bucket start time in UTC.
# - Req: total requests to the monitored endpoint.
# - R302: successful redirects; HTTP 302 is the expected WISP response.
# - R200: HTTP 200 responses, which are not successful redirects.
# - Static / Pay: R200 responses routed respectively to the static error page
#   and to the payments page. Their sum can be lower than R200 when the backend
#   path is missing or different.
# - E5xx: server-error responses.
# - Other: all responses other than 200 and 302; it includes E5xx.
# - Avail: actual redirect availability / traffic-adjusted expected threshold.
# - State: OK means that the bucket does not qualify as a breach; LOW means one
#   valid bucket below threshold; PAIR means two adjacent buckets below threshold.
#
# Buckets with 10 requests or fewer are ignored by the breach rule and therefore
# have state OK even when their displayed availability is below the threshold.
# Set CLOUDO_LOG_LEVEL=DEBUG to include resource details and the full KQL query.
set -euo pipefail

RUNBOOK_VERSION="2026-10-08.6"
RAW_LOG_LEVEL="${CLOUDO_LOG_LEVEL:-INFO}"
LOG_LEVEL="${RAW_LOG_LEVEL^^}"

case "$LOG_LEVEL" in
  DEBUG) LOG_THRESHOLD=10 ;;
  INFO)  LOG_THRESHOLD=20 ;;
  WARN)  LOG_THRESHOLD=30 ;;
  ERROR) LOG_THRESHOLD=40 ;;
  *)
    printf '[%s] [WARN] Unsupported CLOUDO_LOG_LEVEL: %s. Using INFO.\n' \
      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$RAW_LOG_LEVEL"
    LOG_LEVEL="INFO"
    LOG_THRESHOLD=20
    ;;
esac

log_level_value() {
  case "$1" in
    DEBUG) printf '10\n' ;;
    INFO)  printf '20\n' ;;
    WARN)  printf '30\n' ;;
    ERROR) printf '40\n' ;;
  esac
}

log() {
  local level="$1"
  shift
  local level_value timestamp line

  level_value="$(log_level_value "$level")"
  if ((level_value < LOG_THRESHOLD)); then
    return 0
  fi

  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '[%s] [%s] %s\n' "$timestamp" "$level" "$line"
  done <<< "$*"
}

log_debug() { log DEBUG "$@"; }
log_info()  { log INFO "$@"; }
log_warn()  { log WARN "$@"; }
log_error() { log ERROR "$@"; }

log_cli_output() {
  local level="$1"
  local prefix="$2"
  local file="$3"
  local line

  [[ -s "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    log "$level" "${prefix}${line}"
  done < "$file"
}

# Resolved notifications require no further analysis.
if [[ "${MONITOR_CONDITION:-}" == "Resolved" ]]; then
  log_info "The WISP redirect availability alert is resolved; skipping analysis."
  exit 0
fi

ENV_SHORT="${CLOUDO_ENVIRONMENT_SHORT:-}"
case "$ENV_SHORT" in
  d|u|p) ;;
  *)
    log_error "Unsupported or missing CLOUDO_ENVIRONMENT_SHORT: '${ENV_SHORT}'. Expected d, u or p."
    exit 1
    ;;
esac

APIM_NAME="pagopa-${ENV_SHORT}-apim"
APIM_RESOURCE_GROUP="pagopa-${ENV_SHORT}-api-rg"

log_info "Starting WISP redirect analysis ${RUNBOOK_VERSION} for environment '${ENV_SHORT}'."
log_info "Target APIM: '${APIM_NAME}'; endpoint: '/wisp-converter/redirect/api/v1/payments'; lookback: 30 minutes."

if ! command -v az >/dev/null 2>&1; then
  log_error "Azure CLI is not available."
  exit 1
fi

AZ_STDERR_FILE="$(mktemp)"
trap 'rm -f "$AZ_STDERR_FILE"' EXIT

# Authenticate only when the worker has no active Azure session.
if ! az account show --only-show-errors >/dev/null 2>&1; then
  log_info "No Azure session is available; logging in with the ClouDo managed identity."
  : > "$AZ_STDERR_FILE"

  if [[ -n "${AZURE_CLIENT_ID:-}" ]]; then
    if ! az login --identity --client-id "$AZURE_CLIENT_ID" --only-show-errors \
      >/dev/null 2>"$AZ_STDERR_FILE"; then
      log_error "Azure login with the user-assigned managed identity failed."
      log_cli_output ERROR "Azure CLI: " "$AZ_STDERR_FILE"
      exit 1
    fi
  else
    if ! az login --identity --only-show-errors >/dev/null 2>"$AZ_STDERR_FILE"; then
      log_error "Azure login with the system-assigned managed identity failed."
      log_cli_output ERROR "Azure CLI: " "$AZ_STDERR_FILE"
      exit 1
    fi
  fi

  log_cli_output DEBUG "Azure CLI: " "$AZ_STDERR_FILE"
else
  log_debug "Using the existing Azure CLI session."
fi

# Resolve APIM and query telemetry in resource context, not workspace context.
log_debug "Resolving APIM resource '${APIM_NAME}' in resource group '${APIM_RESOURCE_GROUP}'."
: > "$AZ_STDERR_FILE"
if ! APIM_RESOURCE_ID="$(az apim show \
  --resource-group "$APIM_RESOURCE_GROUP" \
  --name "$APIM_NAME" \
  --query id \
  --output tsv \
  --only-show-errors \
  2>"$AZ_STDERR_FILE")"; then
  log_error "Unable to resolve APIM resource '${APIM_NAME}'."
  log_cli_output ERROR "Azure CLI: " "$AZ_STDERR_FILE"
  exit 1
fi

log_cli_output DEBUG "Azure CLI: " "$AZ_STDERR_FILE"

if [[ -z "$APIM_RESOURCE_ID" ]]; then
  log_error "APIM resource '${APIM_NAME}' has an empty resource ID."
  exit 1
fi
log_debug "APIM resource ID resolved: ${APIM_RESOURCE_ID}."

# Prefer the table currently configured in each environment, with the other as fallback.
if [[ "$ENV_SHORT" == "d" ]]; then
  PRIMARY_LOG_TABLE="ApiManagementGatewayLogs"
  FALLBACK_LOG_TABLE="AzureDiagnostics"
else
  PRIMARY_LOG_TABLE="AzureDiagnostics"
  FALLBACK_LOG_TABLE="ApiManagementGatewayLogs"
fi

build_kql_source() {
  case "$1" in
    ApiManagementGatewayLogs)
      cat <<'KQL'
ApiManagementGatewayLogs
| where TimeGenerated >= ago(30m)
| project
    TimeGenerated,
    RequestUrl = tostring(Url),
    Code = tolong(ResponseCode),
    BackendUrlValue = tostring(BackendUrl)
KQL
      ;;
    AzureDiagnostics)
      cat <<'KQL'
AzureDiagnostics
| where TimeGenerated >= ago(30m)
| where Category == "GatewayLogs"
| extend
    LegacyUrl = tostring(column_ifexists("url_s", "")),
    AlternativeUrl = tostring(column_ifexists("requestUri_s", "")),
    LegacyCode = tolong(column_ifexists("responseCode_d", "")),
    AlternativeCode = tolong(column_ifexists("httpStatusCode_d", "")),
    LegacyBackendUrl = tostring(column_ifexists("backendUrl_s", ""))
| project
    TimeGenerated,
    RequestUrl = coalesce(LegacyUrl, AlternativeUrl),
    Code = coalesce(LegacyCode, AlternativeCode),
    BackendUrlValue = LegacyBackendUrl
KQL
      ;;
    *)
      return 1
      ;;
  esac
}

build_kql_query() {
  local kql_source="$1"

  cat <<KQL
${kql_source}
| where isnotempty(RequestUrl)
| extend RequestPath = tolower(tostring(parse_url(RequestUrl).Path))
| where RequestPath == "/wisp-converter/redirect/api/v1/payments"
| extend BackendPath = tolower(tostring(parse_url(BackendUrlValue).Path))
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
    RedirectAvailability = 100.0 * todouble(Redirect302) / Requests,
    ExpectedAvailability = iff(
      Requests >= 500,
      95.0,
      iff(
        Requests <= 100,
        50.0,
        (todouble(Requests - 100) / 400.0 * 45.0) + 50.0
      )
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
| extend
    RedirectAvailability = round(RedirectAvailability, 2),
    ExpectedAvailability = round(ExpectedAvailability, 2)
| extend
    Availability = strcat(tostring(RedirectAvailability), "%/", tostring(ExpectedAvailability), "%"),
    State = case(
      ConsecutiveBreach, "PAIR",
      BelowThreshold, "LOW",
      "OK"
    )
| project
    TimeSlot,
    Requests,
    Redirect302,
    Responses200,
    StaticError200,
    Payments200,
    Errors5xx,
    OtherCodes,
    Availability,
    State
| order by TimeSlot desc
KQL
}

build_query_body() {
  local kql_json="$1"

  kql_json="${kql_json//\\/\\\\}"
  kql_json="${kql_json//\"/\\\"}"
  kql_json="${kql_json//$'\n'/\\n}"
  kql_json="${kql_json//$'\r'/\\r}"
  kql_json="${kql_json//$'\t'/\\t}"
  printf '{"query":"%s","timespan":"PT30M"}' "$kql_json"
}

execute_diagnostic_query() {
  local table="$1"
  local kql_source kql_query query_body

  LAST_QUERY_OUTPUT=""
  LAST_QUERY_ERROR=""

  if ! kql_source="$(build_kql_source "$table")"; then
    LAST_QUERY_ERROR="Unsupported APIM log table: '${table}'."
    return 1
  fi

  kql_query="$(build_kql_query "$kql_source")"
  query_body="$(build_query_body "$kql_query")"
  log_debug "KQL query for '${table}':"$'\n'"${kql_query}"

  : > "$AZ_STDERR_FILE"

  if ! LAST_QUERY_OUTPUT="$(az rest \
    --method post \
    --url "https://api.loganalytics.azure.com/v1${APIM_RESOURCE_ID}/query" \
    --resource "https://api.loganalytics.io" \
    --headers "Content-Type=application/json" \
    --body "$query_body" \
    --query 'tables[0].rows[*].{TimeUTC: [0], Req: [1], R302: [2], R200: [3], Static: [4], Pay: [5], E5xx: [6], Other: [7], Avail: [8], State: [9]}' \
    --output table \
    --only-show-errors \
    2>"$AZ_STDERR_FILE")"; then
    LAST_QUERY_ERROR="$(<"$AZ_STDERR_FILE")"
    return 1
  fi

  log_cli_output DEBUG "Azure CLI: " "$AZ_STDERR_FILE"
}

QUERY_OUTPUT=""
LOG_TABLE=""
PRIMARY_QUERY_RESULT="error"
PRIMARY_QUERY_ERROR=""

log_info "Querying primary APIM log table '${PRIMARY_LOG_TABLE}'."
if execute_diagnostic_query "$PRIMARY_LOG_TABLE"; then
  if [[ -n "${LAST_QUERY_OUTPUT//[[:space:]]/}" ]]; then
    PRIMARY_QUERY_RESULT="data"
    LOG_TABLE="$PRIMARY_LOG_TABLE"
    QUERY_OUTPUT="$LAST_QUERY_OUTPUT"
  else
    PRIMARY_QUERY_RESULT="empty"
  fi
else
  PRIMARY_QUERY_ERROR="$LAST_QUERY_ERROR"
fi

# An empty result can be valid, but also indicate that diagnostics moved tables.
if [[ "$PRIMARY_QUERY_RESULT" != "data" ]]; then
  if [[ "$PRIMARY_QUERY_RESULT" == "error" ]]; then
    log_info "Primary table '${PRIMARY_LOG_TABLE}' could not be queried; trying fallback '${FALLBACK_LOG_TABLE}'."
  else
    log_info "Primary table '${PRIMARY_LOG_TABLE}' returned no rows; checking fallback '${FALLBACK_LOG_TABLE}'."
  fi

  if execute_diagnostic_query "$FALLBACK_LOG_TABLE"; then
    if [[ -n "${LAST_QUERY_OUTPUT//[[:space:]]/}" ]]; then
      LOG_TABLE="$FALLBACK_LOG_TABLE"
      QUERY_OUTPUT="$LAST_QUERY_OUTPUT"
      if [[ "$PRIMARY_QUERY_RESULT" == "error" ]]; then
        log_warn "Primary table '${PRIMARY_LOG_TABLE}' could not be queried; using fallback '${FALLBACK_LOG_TABLE}'."
        [[ -n "$PRIMARY_QUERY_ERROR" ]] && log_debug "Primary query error:"$'\n'"${PRIMARY_QUERY_ERROR}"
      else
        log_warn "Primary table '${PRIMARY_LOG_TABLE}' returned no data; using fallback '${FALLBACK_LOG_TABLE}'."
      fi
    else
      if [[ "$PRIMARY_QUERY_RESULT" == "error" ]]; then
        log_warn "Primary table '${PRIMARY_LOG_TABLE}' could not be queried, and fallback '${FALLBACK_LOG_TABLE}' contained no WISP redirect requests."
        [[ -n "$PRIMARY_QUERY_ERROR" ]] && log_debug "Primary query error:"$'\n'"${PRIMARY_QUERY_ERROR}"
      else
        log_info "No WISP redirect requests were found in either APIM log table during the last 30 minutes."
      fi
      exit 0
    fi
  else
    FALLBACK_QUERY_ERROR="$LAST_QUERY_ERROR"

    if [[ "$PRIMARY_QUERY_RESULT" == "error" ]]; then
      log_error "Queries against both APIM log tables failed."
      [[ -n "$PRIMARY_QUERY_ERROR" ]] && log_error "${PRIMARY_LOG_TABLE}: ${PRIMARY_QUERY_ERROR}"
      [[ -n "$FALLBACK_QUERY_ERROR" ]] && log_error "${FALLBACK_LOG_TABLE}: ${FALLBACK_QUERY_ERROR}"
      exit 1
    fi

    log_info "No WISP redirect requests were found in '${PRIMARY_LOG_TABLE}' during the last 30 minutes."
    [[ -n "$FALLBACK_QUERY_ERROR" ]] && log_debug "Fallback query error:"$'\n'"${FALLBACK_QUERY_ERROR}"
    exit 0
  fi
fi

log_info "Diagnostic query completed successfully."

printf 'WISP redirect diagnostic analysis\n'
printf 'Runbook version: %s\n' "$RUNBOOK_VERSION"
printf 'Environment: %s\n' "$ENV_SHORT"
printf 'APIM resource: %s\n' "$APIM_NAME"
printf 'Log table: %s\n' "$LOG_TABLE"
printf 'Endpoint: /wisp-converter/redirect/api/v1/payments\n'
printf 'Observation window: 30 minutes\n'
printf 'Report: one row per 5-minute UTC bucket, newest first.\n'
printf 'Columns: Req=total; R302=successful redirects; R200=HTTP 200; Static/Pay=known R200 backends.\n'
printf '         E5xx=server errors; Other=non-200/302 responses (including E5xx); Avail=actual/expected.\n'
printf 'State: OK=no qualifying breach (also used when Req<=10); LOW=one breach; PAIR=consecutive breach.\n\n'
printf '%s\n' "$QUERY_OUTPUT"