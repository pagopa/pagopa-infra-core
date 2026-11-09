#!/usr/bin/env bash

INPUT="${1:-input.json}"
OUTPUT="${2:-output.json}"

wget https://raw.githubusercontent.com/pagopa/pagopa-infra-core/refs/heads/main/src/cloudo/cloudo-core/runbooks/ndp/internal_nodo/$CLOUDO_ENVIRONMENT/$INPUT -O "$INPUT"

compact=$(jq -c . "$INPUT")

escaped=$(printf '%s' "$compact" |
  sed 's/\\/\\\\/g; s/"/\\"/g; s#://#:\\\\/\\\\/#g')

value="<fragment><set-variable name=\"configuration\" value=\"@{return \"$escaped\";}\" /></fragment>"

jq -n --arg value "$value" \
  '{properties: {format: "rawxml", value: $value}}' \
  > "$OUTPUT"

response=$(az rest --method put \
  --url "https://management.azure.com/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/pagopa-$CLOUDO_ENVIRONMENT_SHORT-api-rg/providers/Microsoft.ApiManagement/service/pagopa-$CLOUDO_ENVIRONMENT_SHORT-apim/policyFragments/decoupler-configuration?api-version=2022-08-01" \
  --headers "If-Match=*" \
  --body @"$OUTPUT" --verbose 2>&1)
status=$?
echo "$response"
exit $status
