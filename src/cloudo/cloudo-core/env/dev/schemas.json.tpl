[
  {
    "partition_key": "generic",
    "entity": []
  }, {
    "partition_key": "core",
    "entity": [{
                       "id": "pagopa-d-opex_pagopa-wisp-converter-redirect-availability",
                       "name": "WISP redirect availability analysis",
                       "description": "Read-only analysis of WISP redirect availability and backend response paths",
                       "runbook": "wisp/wisp-redirect-analysis.sh",
                       "run_args": "",
                       "worker": "generic",
                       "oncall": false,
                       "require_approval": false,
                       "team": "core",
                       "tags": "wisp,apim,diagnostics"
                     }]
  },
  {
    "partition_key": "infra",
    "entity": [
      {
        "id": "pagopa-d-appgw-total-request-info",
        "name": "total request pagopa-app-gw",
        "description": "Get Total request from pagopa appgw!",
        "runbook": "azure/application_gateway_info.sh",
        "run_args": "pagopa-d-app-gw pagopa-d-vnet-rg",
        "worker": "generic",
        "team": "infra",
        "oncall": false,
        "require_approval": false,
        "tags": "application gateway,azure"
      },
      {
        "id": "availability-fe-checkout-cdn",
        "name": "Checkout CDN check status",
        "description": "Status check for checkout provider from CDN to APIM",
        "runbook": "cdn/checkout_cdn_check.py",
        "run_args": "",
        "worker": "generic",
        "team": "infra",
        "oncall": false,
        "require_approval": false,
        "tags": "checkout,azure"
      },
      {
        "id": "cdn-apim-switch",
        "name": "Switch CDN to  APIM",
        "description": "Switch static content provider from CDN to APIM",
        "runbook": "cdn/cdn_to_apim_switch.sh",
        "run_args": "",
        "worker": "generic",
        "team": "infra",
        "oncall": false,
        "require_approval": true,
        "tags": "checkout,azure"
      },
      {
        "id": "availability-nodo-checkPosition-appgw",
        "name": "NDP DR - Check status",
        "description": "NDP DR - Check status",
        "runbook": "ndp/ndp-check.py",
        "run_args": "",
        "worker": "generic",
        "team": "infra",
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
        "team": "infra",
        "oncall": true,
        "require_approval": false,
        "group": "ndp-dr-check",
        "tags": "nodo,synthetic"
      },
      {
        "id": "availability-nodo-verifyPaymentNoticeOnPartner-appgw",
        "name": "NDP DR - Check status",
        "description": "NDP DR - Check status",
        "runbook": "ndp/ndp-check.py",
        "run_args": "",
        "worker": "generic",
        "team": "infra",
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
        "team": "infra",
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
        "team": "infra",
        "oncall": true,
        "enabled": true,
        "require_approval": true,
        "group": "ndp-dr-switch",
        "tags": "nodo"
      },
      {
        "id": "carbon-monthly-emissions-report",
        "name": "Carbon dashboard - Refresh emissions data",
        "description": "Fetch the Carbon Optimization monthly report for the pagoPA subscriptions and publish it to the carbon dashboard",
        "runbook": "carbon/fetch_carbon_report.py",
        "run_args": "--storage-account pagopaditncarbonfe",
        "worker": "generic",
        "oncall": false,
        "require_approval": false,
        "tags": "carbon,azure"
      }
    ]
  },
  {
    "partition_key": "alert",
    "entity": []
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
      "team": "infra",
      "oncall": false,
      "require_approval": false,
      "tags": ""
    }
    ]
  }
]
