{
  "schedule-default": {
    "partition_key": "Schedule",
    "entity": [
      {
        "name": "[finops] Cost spike 7 days ",
        "cron": "0 0 10 * * 1",
        "runbook": "finops/azure_cost_threshold.py",
        "run_args": "--days 7 -r 30 --top-types 30 --slack-team-id TQSBH3ZS4 --slack-bot-id B0C0X97T4UA --keyvault-name pagopa-u-itn-cloudo-kv --keyvault-slack-token finops-slack-token",
        "worker_pool": "generic",
        "enabled": true,
        "oncall": false
      },
      {
        "name": "[finops] Cost spike 30 days ",
        "cron": "0 0 09 1 * 1",
        "runbook": "finops/azure_cost_threshold.py",
        "run_args": "--days 30 -r 30 --top-types 30 --slack-team-id TQSBH3ZS4 --slack-bot-id B0C0X97T4UA --keyvault-name pagopa-u-itn-cloudo-kv --keyvault-slack-token finops-slack-token",
        "worker_pool": "generic",
        "enabled": true,
        "oncall": false
      }
    ]
  }
}
