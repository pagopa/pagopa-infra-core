
import os

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.mgmt.apimanagement import ApiManagementClient
from azure.mgmt.apimanagement.models import NamedValueCreateContract
import json
from slack_sdk.webhook import WebhookClient
from slack_sdk.errors import SlackApiError

SUBSCRIPTIONS = {
  "d" : "bbe47ad4-08b3-4925-94c5-1278e5819b86",
  "u" : "26abc801-0d8f-4a6e-ac5f-8e81bcc09112",
  "p" : "b9fc9419-6097-45fe-9f74-ba0641c91912"
}

SUBSCRIPTION_ID = SUBSCRIPTIONS.get(os.environ.get('CLOUDO_ENVIRONMENT_SHORT'))


APIM_RG_NAME = f"pagopa-{os.environ.get('CLOUDO_ENVIRONMENT_SHORT')}-api-rg"
APIM_NAME = f"pagopa-{os.environ.get('CLOUDO_ENVIRONMENT_SHORT')}-apim"

SWITCH_TO_NEXI = "toNexi"
SWITCH_TO_PAGOPA = "toPagopa"



SWITCH = {
  SWITCH_TO_NEXI : {
    "enable-nm3-decoupler-switch": False,
    "enable-routing-decoupler-switch": False,
  },
  SWITCH_TO_PAGOPA : {
    "enable-nm3-decoupler-switch": False,
    "enable-routing-decoupler-switch": False,
  }

}

def build_apim_client():
  try:
    credential = DefaultAzureCredential()
    client = ApiManagementClient(credential, SUBSCRIPTION_ID)
    return client
  except Exception as e:
    print(f"Error during login: {str(e)}")
    exit(1)



def get_apim_named_values(client, names):
  return [
    {nv.display_name: nv.value}
    for name in names
    for nv in [client.named_value.get(
      resource_group_name=APIM_RG_NAME,
      service_name=APIM_NAME,
      named_value_id=name
    )]
  ]

def update_apim_named_values(client, values: dict):
  try:
    for name, value in values.items():
      update = NamedValueCreateContract(
        display_name=name,
        value=value,
        secret=False
      )
      print(f"updating: {name}")
      client.named_value.begin_create_or_update(
        resource_group_name=APIM_RG_NAME,
        service_name=APIM_NAME,
        named_value_id=name,
        parameters=update
      )
      print(f"updated: {name}")
  except Exception as e:
    print(f"Error during update: {str(e)}")
    exit(1)

def main():
  cloudo_playload = os.environ.get('CLOUDO_PAYLOAD')
  if not cloudo_playload:
    print("No payload found in environment variable 'CLOUDO_PAYLOAD'")
    exit(1)

  cloudo_playload_j = json.loads(cloudo_playload)
  runbook_payload = cloudo_playload_j.get("payload")
  if isinstance(runbook_payload, str):
    runbook_payload = json.loads(runbook_payload)

  print(f"received payload: {runbook_payload}")
  switch = runbook_payload.get("switch")

  apim_client = build_apim_client()

  values = get_apim_named_values(apim_client, SWITCH.get(switch).keys())
  print(f"current values: {values}")
  print(f"updating to: {SWITCH.get(switch)}")
  update_apim_named_values(apim_client, SWITCH.get(switch))
  print()

if __name__ == "__main__":
  main()
