#!/usr/bin/env bash

set -euo pipefail

INPUT="${1:-input.json}"
OUTPUT="${2:-output.json}"

compact=$(jq -c . "$INPUT")

escaped=$(printf '%s' "$compact" |
  sed 's/\\/\\\\/g; s/"/\\"/g; s#://#:\\\\/\\\\/#g')

value="<fragment><set-variable name=\"configuration\" value=\"@{return \"$escaped\";}\" /></fragment>"

jq -n --arg value "$value" \
  '{properties: {format: "rawxml", value: $value}}' \
  > "$OUTPUT"

az rest --method put \
  --url "https://management.azure.com/subscriptions/26abc801-0d8f-4a6e-ac5f-8e81bcc09112/resourceGroups/pagopa-u-api-rg/providers/Microsoft.ApiManagement/service/pagopa-u-apim/policyFragments/decoupler-configuration?api-version=2022-08-01" \
  --headers "If-Match=*" \
  --body @$OUTPUT --verbose
