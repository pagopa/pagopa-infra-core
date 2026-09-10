import argparse
import datetime
import calendar
import json
import os
import sys
import urllib.request
from collections import defaultdict
from azure.identity import DefaultAzureCredential
from azure.mgmt.consumption import ConsumptionManagementClient
from azure.keyvault.secrets import SecretClient

def get_secret_from_keyvault(vault_name_or_url: str, secret_name: str,
                             credential=None) -> str:
  """
  Retrieves the value of a secret (e.g. Slack token/webhook) from Azure Key Vault.

  :param vault_name_or_url: Name of the Key Vault (e.g., "my-kv") or full URL (e.g., "https://my-kv.vault.azure.net/")
  :param secret_name: Name of the secret stored in Key Vault
  :param credential: Optional Azure credential instance (defaults to DefaultAzureCredential)
  :return: Secret value string
  """
  if not vault_name_or_url.startswith("https://"):
    vault_url = f"https://{vault_name_or_url}.vault.azure.net/"
  else:
    vault_url = vault_name_or_url

  if credential is None:
    credential = DefaultAzureCredential()

  client = SecretClient(vault_url=vault_url, credential=credential)
  retrieved_secret = client.get_secret(secret_name)

  return retrieved_secret.value

def get_subscription_display_name(credential, subscription_id):
    """
    Attempts to resolve the human-readable Subscription Name from Azure Subscription ID.
    Falls back to the Subscription ID if resolution fails.
    """
    try:
        from azure.mgmt.subscription import SubscriptionClient
        sub_client = SubscriptionClient(credential)
        sub_info = sub_client.subscriptions.get(subscription_id)
        return sub_info.display_name
    except Exception:
        # Fallback to Subscription ID if permissions/import fail
        return subscription_id

def fetch_resource_costs(client, scope, start_date, end_date):
    """
    Retrieves cost data from Azure API and groups costs by both resource ID and resource type.
    """
    filter_str = (
        f"properties/usageStart ge '{start_date.strftime('%Y-%m-%d')}' "
        f"and properties/usageEnd le '{end_date.strftime('%Y-%m-%d')}'"
    )

    try:
        usage_details = list(client.usage_details.list(scope=scope, filter=filter_str))
    except Exception as e:
        print(f"[API ERROR] Failed to fetch usage_details: {e}")
        return 0.0, defaultdict(float), defaultdict(float)

    if not usage_details:
        print(f"[WARNING] No cost records returned for period {start_date} - {end_date}.")
        return 0.0, defaultdict(float), defaultdict(float)

    total_cost = 0.0
    costs_by_resource = defaultdict(float)
    costs_by_type = defaultdict(float)

    for detail in usage_details:
        cost = 0.0
        possible_fields = [
            'cost_in_billing_currency',
            'pretax_cost',
            'payg_cost',
            'cost_in_pricing_currency',
            'cost_in_usd'
        ]

        for field in possible_fields:
            val = getattr(detail, field, None)
            if val is not None and float(val) > 0:
                cost = float(val)
                break

        if cost == 0.0 and hasattr(detail, 'cost') and detail.cost is not None:
            cost = float(detail.cost)

        total_cost += cost

        # Identify Resource Name / ID
        res_id = (
            getattr(detail, 'resource_id', None)
            or getattr(detail, 'resource_name', None)
            or getattr(detail, 'instance_name', 'Unknown Resource')
        )
        costs_by_resource[res_id] += cost

        # Identify Resource Type
        res_type = getattr(detail, 'consumed_service', None) or getattr(detail, 'resource_type', None)
        if not res_type and "/" in res_id and "providers/" in res_id:
            parts = res_id.split("providers/")[-1].split("/")
            if len(parts) >= 2:
                res_type = f"{parts[0]}/{parts[1]}"

        if not res_type:
            res_type = "Other / Unknown"

        costs_by_type[res_type] += cost

    return total_cost, costs_by_resource, costs_by_type


def extract_resource_name(resource_id):
    """Extracts the short resource name from an Azure ARM ID."""
    if "/" in resource_id:
        return resource_id.split("/")[-1]
    return resource_id


def get_month_dates(year_month_str):
    """Calculates start and end dates for the given month (YYYY-MM) and the previous month."""
    try:
        dt = datetime.datetime.strptime(year_month_str, "%Y-%m").date()
    except ValueError:
        raise ValueError("Month format must be YYYY-MM (e.g., 2026-08)")

    curr_start = datetime.date(dt.year, dt.month, 1)
    _, last_day = calendar.monthrange(dt.year, dt.month)
    curr_end = datetime.date(dt.year, dt.month, last_day)

    first_day_prev = curr_start - datetime.timedelta(days=1)
    prev_start = datetime.date(first_day_prev.year, first_day_prev.month, 1)
    _, last_day_prev = calendar.monthrange(first_day_prev.year, first_day_prev.month)
    prev_end = datetime.date(first_day_prev.year, first_day_prev.month, last_day_prev)

    return (curr_start, curr_end), (prev_start, prev_end)


def get_sorted_data(items_curr, items_prev, is_resource=True):
    """Prepares and sorts cost delta data in descending order."""
    all_keys = set(items_curr.keys()).union(set(items_prev.keys()))
    data = []
    for key in all_keys:
        c_curr = items_curr.get(key, 0.0)
        c_prev = items_prev.get(key, 0.0)
        delta = c_curr - c_prev
        name = extract_resource_name(key) if is_resource else key
        data.append((name, c_prev, c_curr, delta))

    data.sort(key=lambda x: x[3], reverse=True)
    return data


def send_slack_compact_alert(webhook_url, sub_name, percentage_increase, prev_total, curr_total, curr_dates, prev_dates):
    """
    Sends a compact and streamlined Slack alert block without top tables.
    Includes subscription display name and exact analysis date ranges.
    """
    curr_start_str, curr_end_str = curr_dates
    prev_start_str, prev_end_str = prev_dates

    payload = {
      "text": f"🚨 *Azure Cost Spike Alert* - {sub_name}",
      "blocks": [
        {
          "type": "header",
          "text": {
            "type": "plain_text",
            "text": "🚨 Azure Cost Spike Alert",
            "emoji": True
          }
        },
        {
          "type": "section",
          "text": {
            "type": "mrkdwn",
            "text": f"*Subscription:* *{sub_name}*"
          }
        },
        {"type": "divider"},
        {
          "type": "section",
          "fields": [
            {"type": "mrkdwn", "text": "*Period / Metric*"},
            {"type": "mrkdwn", "text": "*Amount / Rate*"},

            {"type": "mrkdwn",
             "text": f"Current ({curr_start_str} / {curr_end_str})"},
            {"type": "mrkdwn", "text": f"`{curr_total:.2f} €`"},

            {"type": "mrkdwn",
             "text": f"Previous ({prev_start_str} / {prev_end_str})"},
            {"type": "mrkdwn", "text": f"`{prev_total:.2f} €`"},

            {"type": "mrkdwn", "text": "Cost Variation"},
            {"type": "mrkdwn", "text": f"*`{percentage_increase:+.2f} %`*"},
          ]
        }
      ]
    }

    try:
        req = urllib.request.Request(
            webhook_url,
            data=json.dumps(payload).encode('utf-8'),
            headers={'Content-Type': 'application/json'}
        )
        with urllib.request.urlopen(req) as response:
            if response.status == 200:
                print("[SLACK] Compact alert message successfully sent to Slack.")
            else:
                print(f"[SLACK ERROR] Slack API returned HTTP STATUS {response.status}")
    except Exception as e:
        print(f"[SLACK ERROR] Failed to deliver message to Slack: {e}")


def print_table(title, data, top_count, compare_mode):
    """Renders formatted tabular data to terminal stdout."""
    print(f"\n--- {title} (TOP {top_count} SORTED BY DELTA) ---")
    if compare_mode:
        print(f"{'Name / Type':<45} | {'Prev.':<10} | {'Curr.':<10} | {'Delta':<10}")
        print("-" * 83)
        for name, cost_prev, cost_curr, delta in data[:top_count]:
            print(f"{name[:43]:<45} | {cost_prev:10.2f} | {cost_curr:10.2f} | {delta:+10.2f}")
    else:
        print(f"{'Name / Type':<55} | {'Period Cost':<15}")
        print("-" * 73)
        for name, _, cost_curr, _ in data[:top_count]:
            print(f"{name[:53]:<55} | {cost_curr:15.2f}")


def main():
    parser = argparse.ArgumentParser(
        description="Azure Cost Analysis tool with threshold monitoring, compact Slack alerts, and resource breakdowns."
    )
    parser.add_argument("--subscription-id", "-s", default=None, help="Target Azure Subscription ID (defaults to AZURE_SUBSCRIPTION_ID env var)")
    parser.add_argument("--threshold", "-t", type=float, default=15.0, help="Allowed cost increase threshold %% (default: 15.0)")
    parser.add_argument("--top-resources", "-r", type=int, default=10, help="Top N individual resources to display in stdout (default: 10)")
    parser.add_argument("--top-types", type=int, default=10, help="Top N resource types to display in stdout (default: 10)")
    parser.add_argument("--days", "-d", type=int, default=7, help="Window length in days for rolling analysis (default: 7)")
    parser.add_argument("--month", "-m", type=str, default=None, help="Target calendar month in YYYY-MM format (e.g., 2026-08)")
    parser.add_argument("--compare", action=argparse.BooleanOptionalAction, default=True, help="Enable or disable period comparison")

    # Slack Webhook configuration arguments
    parser.add_argument("--slack-webhook-url", "-w", type=str, default=None, help="Full Slack Incoming Webhook URL")
    parser.add_argument("--slack-team-id", type=str, default=None, help="Slack Team/Workspace ID")
    parser.add_argument("--slack-bot-id", type=str, default=None, help="Slack Bot/Integration ID")
    parser.add_argument("--slack-token", type=str, default=None, help="Slack Secret Token")
    parser.add_argument("--keyvault-slack-token", type=str, default=None, help="KeyVault name for Slack Secret Token")
    parser.add_argument("--keyvault-name", type=str, default=None, help="KeyVault URL")

    args = parser.parse_args()

    subscription_id = args.subscription_id or os.getenv("AZURE_SUBSCRIPTION_ID")
    if not subscription_id:
        parser.error("--subscription-id is required unless AZURE_SUBSCRIPTION_ID is set")

    # Resolve Slack Webhook URL from full string or components
    webhook_url = args.slack_webhook_url
    if not webhook_url and args.slack_team_id and args.slack_bot_id:
        if not args.slack_token and args.keyvault_name:
          slack_token = get_secret_from_keyvault(args.keyvault_name, args.keyvault_slack_token)
        else:
          slack_token = args.slack_token
        webhook_url = f"https://hooks.slack.com/services/{args.slack_team_id}/{args.slack_bot_id}/{slack_token}"

    credential = DefaultAzureCredential()
    client = ConsumptionManagementClient(credential, subscription_id)
    scope = f"/subscriptions/{subscription_id}"

    # Resolve Subscription Display Name
    subscription_name = get_subscription_display_name(credential, subscription_id)

    # Determine analysis timeframes
    if args.month:
        try:
            (current_start, current_end), (previous_start, previous_end) = get_month_dates(args.month)
        except ValueError as e:
            print(f"[ERROR] {e}")
            sys.exit(2)
    else:
        today = datetime.datetime.utcnow().date()
        current_end = today - datetime.timedelta(days=1)
        current_start = current_end - datetime.timedelta(days=args.days - 1)
        previous_end = current_start - datetime.timedelta(days=1)
        previous_start = previous_end - datetime.timedelta(days=args.days - 1)

    print("=" * 85)
    print(f"AZURE COST ANALYSIS FOR SUBSCRIPTION: {subscription_name} ({subscription_id})")
    print(f"-> Current Period : {current_start} / {current_end}")
    if args.compare:
        print(f"-> Previous Period: {previous_start} / {previous_end}")
    else:
        print("-> Comparison mode: DISABLED")
    print("=" * 85)

    try:
        current_total, current_resources, current_types = fetch_resource_costs(client, scope, current_start, current_end)

        previous_total = 0.0
        previous_resources, previous_types = defaultdict(float), defaultdict(float)
        if args.compare:
            previous_total, previous_resources, previous_types = fetch_resource_costs(client, scope, previous_start, previous_end)

    except Exception as e:
        print(f"\n[ERROR] Failed to retrieve cost metrics: {e}")
        sys.exit(2)

    # Prepare sorted dataset for terminal output
    sorted_types = get_sorted_data(current_types, previous_types, is_resource=False)
    sorted_resources = get_sorted_data(current_resources, previous_resources, is_resource=True)

    # SUMMARY OVERVIEW
    print(f"\n--- TOTAL SUMMARY ---")
    if args.compare:
        print(f"Previous Period Cost : {previous_total:.2f}")
        print(f"Current Period Cost  : {current_total:.2f}")

        if previous_total == 0:
            percentage_increase = 100.0 if current_total > 0 else 0.0
        else:
            percentage_increase = ((current_total - previous_total) / previous_total) * 100

        print(f"Total Change         : {percentage_increase:+.2f}%")
        print(f"Allowed Threshold    : +{args.threshold:.2f}%")
    else:
        print(f"Total Period Cost    : {current_total:.2f}")

    # PRINT TABLES TO STDOUT (CONSOLE ONLY)
    if args.top_types > 0:
        print_table("RESOURCE TYPES", sorted_types, args.top_types, args.compare)

    if args.top_resources > 0:
        print_table("INDIVIDUAL RESOURCES", sorted_resources, args.top_resources, args.compare)

    # THRESHOLD VERIFICATION, COMPACT SLACK ALERT, AND EXIT CODES
    print("\n" + "=" * 85)
    if args.compare:
        if percentage_increase > args.threshold:
            print(f"[ALERT] Cost increase ({percentage_increase:.2f}%) EXCEEDS allowed threshold ({args.threshold:.2f}%)!")

            # Dispatch compact Slack alert if webhook URL is resolved
            if webhook_url:
                send_slack_compact_alert(
                    webhook_url=webhook_url,
                    sub_name=subscription_name,
                    percentage_increase=percentage_increase,
                    prev_total=previous_total,
                    curr_total=current_total,
                    curr_dates=(current_start, current_end),
                    prev_dates=(previous_start, previous_end)
                )

            sys.exit(1)
        else:
            print(f"[OK] Cost increase ({percentage_increase:.2f}%) within acceptable threshold.")
            sys.exit(0)
    else:
        print("[INFO] Analysis complete (threshold check skipped).")
        sys.exit(0)


if __name__ == "__main__":
    main()
