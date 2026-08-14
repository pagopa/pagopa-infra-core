{
  "schedule-default": {
    "partition_key": "Schedule",
    "entity": [
      {
        "name": "[pagopa-dev] Check application gateway ",
        "cron": "0 0 */1 * * *",
        "runbook": "azure/application_gateway_info.sh",
        "run_args": "pagopa-d-app-gw pagopa-d-vnet-rg",
        "worker_pool": "generic",
        "enabled": true,
        "oncall": false
      }
    ]
  }
}
