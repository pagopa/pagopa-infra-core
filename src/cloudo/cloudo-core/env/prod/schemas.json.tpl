[
  {
    "partition_key": "generic",
    "entity": []
  },
  {
    "partition_key": "infra",
    "entity": [
      {
        "id": "pagopa-p-appgw-total-request-info",
        "name": "total request pagopa-app-gw",
        "description": "Get Total request from pagopa appgw!",
        "runbook": "azure/application_gateway_info.sh",
        "run_args": "pagopa-p-app-gw pagopa-p-vnet-rg",
        "worker": "generic",
        "oncall": false,
        "require_approval": false,
        "tags": "application gateway,azure"
      },
      {
        "id": "availability-nodo-checkPosition-pagoPa",
        "name": "NDP DR - Check status",
        "description": "NDP DR - Check status",
        "runbook": "ndp/ndp-check.py",
        "run_args": "",
        "worker": "generic",
        "oncall": true,
        "require_approval": false,
        "group": "ndp-dr-check",
        "tags": "nodo,synthetic"
      },
      {
        "id": "availability-nodo-checkPosition-nexiPostgres",
        "name": "NDP DR - Check status",
        "description": "NDP DR - Check status",
        "runbook": "ndp/ndp-check.py",
        "run_args": "",
        "worker": "generic",
        "oncall": true,
        "require_approval": false,
        "group": "ndp-dr-check",
        "tags": "nodo,synthetic"
      },
      {
        "id": "availability-nodo-checkPosition-nexiPostgresPublic",
        "name": "NDP DR - Check status",
        "description": "NDP DR - Check status",
        "runbook": "ndp/ndp-check.py",
        "run_args": "",
        "worker": "generic",
        "oncall": true,
        "require_approval": false,
        "group": "ndp-dr-check",
        "tags": "nodo,synthetic"
      },
      {
        "id": "availability-nodo-verifyPaymentNoticeOnPartner-pagoPa",
        "name": "NDP DR - Check status",
        "description": "NDP DR - Check status",
        "runbook": "ndp/ndp-check.py",
        "run_args": "",
        "worker": "generic",
        "oncall": true,
        "require_approval": false,
        "group": "ndp-dr-check",
        "tags": "nodo,synthetic"
      },
      {
        "id": "availability-nodo-verifyPaymentNoticeOnPartner-nexiPostgres",
        "name": "NDP DR - Check status",
        "description": "NDP DR - Check status",
        "runbook": "ndp/ndp-check.py",
        "run_args": "",
        "worker": "generic",
        "oncall": true,
        "require_approval": false,
        "group": "ndp-dr-check",
        "tags": "nodo,synthetic"
      },
      {
        "id": "availability-nodo-verifyPaymentNoticeOnPartner-nexiPostgresPublic",
        "name": "NDP DR - Check status",
        "description": "NDP DR - Check status",
        "runbook": "ndp/ndp-check.py",
        "run_args": "",
        "worker": "generic",
        "oncall": true,
        "require_approval": false,
        "group": "ndp-dr-check",
        "tags": "nodo,synthetic"
      },
      {
        "id": "ndp-switch-execution",
        "name": "NDP DR - Execute switch",
        "description": "NDP DR - Execute switch",
        "runbook": "ndp/ndp-switch.py",
        "run_args": "",
        "worker": "generic",
        "oncall": true,
        "require_approval": true,
        "group": "ndp-dr-switch",
        "tags": "nodo"
      }
    ]
  },
  {
    "partition_key": "elastic",
    "entity": [
      {
        "id": "elastic-cache-postgres-error",
        "name": "Cache postgres DB connection error",
        "description": "Rollout cache postgres deployment to mitigate connection error",
        "runbook": "aks/aks-deployments-rollout.sh",
        "run_args": "",
        "worker": "generic",
        "oncall": false,
        "require_approval": false,
        "tags": "elastic,aks,apiconfig"
      },
      {
        "id": "cluster_health_red",
        "name": "Elastic cluster health red",
        "description": "Try the cluster reroute with retryFailed option",
        "runbook": "elastic/reroute-retry.py",
        "run_args": "",
        "worker": "generic",
        "oncall": false,
        "require_approval": false,
        "tags": "elastic"
      },
      {
        "id": "cluster_health_yellow",
        "name": "Elastic cluster health yellow",
        "description": "Check if ilm is stuck and try to remove replica shard to fix",
        "runbook": "elastic/ilm-stuck.py",
        "run_args": "",
        "worker": "generic",
        "oncall": false,
        "require_approval": false,
        "tags": "elastic"
      }
    ]
  }
]
