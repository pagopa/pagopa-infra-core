import sys, os
import psycopg2
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

# Set azure credentials
credential = DefaultAzureCredential()

# Set queries to launch
query = """SELECT process, note, date, execution_id
         FROM maintenance.process_log
         WHERE date >= %s and date < %s
         AND outcome = 'KO'
         AND note IS NOT NULL
         ORDER BY date DESC"""

# Set query interval
end_time = datetime.now(ZoneInfo("Europe/Rome"))
start_time = end_time.replace(hour=0, minute=0, second=0, microsecond=0)
date_time_format = "%d/%m/%Y %H:%M:%S"
date_format = "%d/%m/%Y"

# Set secrets name
slack_webhook_secret_name = "pagopa-platform-reporter-oauth-token"
db_password_secret_name = "db-fdr3-password"

# Set DB parameters
db_host = f"fdr-archive-db.{os.environ.get('CLOUDO_ENVIRONMENT_SHORT', 'd')}.internal.postgresql.pagopa.it"
db_name = "fdr3"
db_user = "fdr3"


# Retrieve secret from keyvault
def get_secret(secret_name: str):
    kv_uri = f"https://pagopa-{os.getenv('CLOUDO_ENVIRONMENT_SHORT')}-fdr-kv.vault.azure.net"
    kv_client = SecretClient(vault_url=kv_uri, credential=credential)
    return kv_client.get_secret(secret_name)


# Postgres query logic
def query_postgres(start_time: datetime, end_time: datetime):
    try:
        db_password = get_secret(db_password_secret_name).value
        conn = psycopg2.connect(
            host=db_host,
            dbname=db_name,
            user=db_user,
            password=db_password,
            sslmode="require"
        )
        cursor = conn.cursor()
        cursor.execute(query, (start_time, end_time))
        result = cursor.fetchall()
        print(f"Found [{len(result)}] tuples!")
        cursor.close()
        conn.close()
        return result
    except psycopg2.Error as err:
        print("❌ Fatal database error happened")
        print(err)
        sys.exit(1)
    except Exception as err:
        print("❌ An unexpected error occurred")
        print(err)
        sys.exit(1)


# Create slack message
def send_slack_message(payload, slack_channel_id):
    client = WebClient(token=get_secret(slack_webhook_secret_name).value)
    print("Slack client initialized.")
    try:
        response = client.chat_postMessage(
            channel=slack_channel_id,
            **payload
        )
        print(f"Success! Message sent to {slack_channel_id} at {response['ts']}")
        return response
    except SlackApiError as e:
        print(f"❌ Error sending Slack notification: {e.response['error']}")
    except Exception as e:
        print(f"❌ An unexpected error occurred: {e}")


def create_slack_message(db_results: list, start_time: datetime, end_time: datetime):
    results_text = ""

    for row in db_results:
        process = row[0]
        note = row[1]
        log_date = row[2]
        execution_id = row[3]
        if isinstance(log_date, datetime):
            log_date_str = log_date.strftime(date_time_format)
        else:
            log_date_str = str(log_date)
        results_text += f"• *Timestamp: [{log_date_str}], Process: [{process}]* (Execution ID: `{execution_id}`)\n>_{note}_\n\n"

    return {
        "text": f"Report errori archiviazione FdR - Trovati {len(db_results)} errori",
        "blocks":
            [
                {
                    "type" : "header",
                    "text": {
                        "type": "plain_text",
                        "text": ":warning: Report errori archiviazione FdR :warning:",
                        "emoji": True
                    }
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f":date: *Data:* _{start_time.strftime(date_format)}_\n\n\n:mag: *Dettaglio:*\n{results_text}"
                    }
                }
            ]
        }

# To launch this script: python3 check_archive_maintenance_processes.py <slack_channel_id>
if __name__ == "__main__":
  total_records = query_postgres(start_time, end_time)
  if len(total_records) > 0:
    payload = create_slack_message(total_records, start_time, end_time)
    send_slack_message(payload, sys.argv[1])
