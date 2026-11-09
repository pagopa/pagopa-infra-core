
import os

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.mgmt.apimanagement import ApiManagementClient
from azure.mgmt.apimanagement.models import NamedValueCreateContract
from slack_sdk.webhook import WebhookClient
from slack_sdk.errors import SlackApiError
import argparse

SUBSCRIPTIONS = {
  "d" : "bbe47ad4-08b3-4925-94c5-1278e5819b86",
  "u" : "26abc801-0d8f-4a6e-ac5f-8e81bcc09112",
  "p" : "b9fc9419-6097-45fe-9f74-ba0641c91912"
}

SUBSCRIPTION_ID = SUBSCRIPTIONS.get(os.environ.get('CLOUDO_ENVIRONMENT_SHORT', 'd'))


APIM_RG_NAME = f"pagopa-{os.environ.get('CLOUDO_ENVIRONMENT_SHORT', 'd')}-api-rg"
APIM_NAME = f"pagopa-{os.environ.get('CLOUDO_ENVIRONMENT_SHORT', 'd')}-apim"

NDP_INSTANCE_NEXI = "nexi"
NDP_INSTANCE_PAGOPA = "pagoPA"
SLACK_WEBHOOK_URL = "ndp-activation-slack-webhook"



SWITCH = {
  NDP_INSTANCE_NEXI : {
    "enable-nm3-decoupler-switch": True,
    "enable-routing-decoupler-switch": False
  },
  NDP_INSTANCE_PAGOPA : {
    "enable-nm3-decoupler-switch": True,
    "enable-routing-decoupler-switch": True
  }

}

def azure_login():
  try:
    credential = DefaultAzureCredential()
    return credential
  except Exception as e:
    print(f"Error during login: {str(e)}")
    exit(1)


def build_apim_client(azure_credentials):
  try:
    client = ApiManagementClient(azure_credentials, SUBSCRIPTION_ID)
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

# Retrieve secrets from keyvault
def get_runbook_secrets(azure_credentials):
    kv_uri = f"https://pagopa-{os.environ.get('CLOUDO_ENVIRONMENT_SHORT', 'd')}-itn-cloudo-kv.vault.azure.net"
    kv_client = SecretClient(vault_url=kv_uri, credential=azure_credentials)
    return {
     SLACK_WEBHOOK_URL : kv_client.get_secret("ndp-activation-slack-webhook").value,
    }


def create_slack_message(ndp_instance: str, named_values: dict):
  if ndp_instance == NDP_INSTANCE_PAGOPA:
    blocks = [
      {
        "type": "header",
        "text": {
          "type": "plain_text",
          "text": f"Attivazione NDP pagoPA in ambiente {os.environ.get('CLOUDO_ENVIRONMENT', 'dev')}",
        }
      },
      {
        "type": "section",
        "text": {
          "type": "mrkdwn",
          "text": f"Attivazione eseguita impostando i seguenti valori di named values: {named_values}"
        }
      },
      {
        "type": "section",
        "text": {
          "type": "mrkdwn",
          "text": f"L'effettiva percentuale di traffico gestita dal decoupler dipende dalle configurazioni di routing e dalle regole di traffico in vigore."
        }
      }
    ]
  else:
    blocks = [
      {
        "type": "header",
        "text": {
          "type": "plain_text",
          "text": f"Disattivazione NDP pagoPA",
        }
      },
      {
        "type": "section",
        "text": {
          "type": "mrkdwn",
          "text": f"Disattivazione eseguita impostando i seguenti valori di named values: {named_values}"
        }
      }
    ]

  return {"blocks": blocks}


def send_slack_message(payload, webhook_url):
  client = WebhookClient(webhook_url)
  print("Slack client initialized.")
  try:
    response = client.send(
      **payload
    )

    print(f"Slack API response: {response.status_code}")
    if response.status_code == 200:
      print(f"Success! Slack message sent ")

    return
  except SlackApiError as e:
    print(f"Error sending Slack notification: {e.response['error']}")
  except Exception as e:
    print(f"An unexpected error occurred: {e}")

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
  parser = argparse.ArgumentParser(
    description="NDP PagoPA Activation Runbook - Activates or deactivates the NDP PagoPA decoupler switches in Azure API Management"
  )
  parser.add_argument("--ndp-instance", "-n", default=None,
                      help="NDP instance to activate/deactivate (e.g., 'toNexi' or 'toPagopa')")

  parser.add_argument("--dry-run", "-dr", action='store_true',
                      help="If set, the script will only print the actions it would take without making any changes.")

  args = parser.parse_args()

  switch = args.ndp_instance
  dry_run = args.dry_run

  print(f"received ndp instance: {switch}")
  azure_credentials = azure_login()
  apim_client = build_apim_client(azure_credentials)

  values = get_apim_named_values(apim_client, SWITCH.get(switch).keys())
  print(f"current values: {values}")

  if dry_run:
    print("Dry run mode enabled. No changes will be made.")
    print(f"DRY-RUN would update to: {SWITCH.get(switch)}")
  else:
    print(f"updating to: {SWITCH.get(switch)}")
    update_apim_named_values(apim_client, SWITCH.get(switch))
    secrets = get_runbook_secrets(azure_credentials)
    payload = create_slack_message(switch, SWITCH.get(switch))
    send_slack_message(payload, secrets.get(SLACK_WEBHOOK_URL))

if __name__ == "__main__":
  main()
