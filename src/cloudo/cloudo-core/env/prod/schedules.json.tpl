{
  "schedule-default": {
    "partition_key": "Schedule",
    "entity": [
      {
        "name": "DEBT_POSITION_ARCHIVE_REPORT",
        "cron": "00 00 11 * * 1",
        "runbook": "gpd/archivedDebtPositionsReport.py",
        "run_args": "C081WTLJHB8",
        "worker_pool": "generic",
        "enabled": true,
        "oncall": false
      },
      {
        "name": "FDR_ARCHIVE_MAINTENANCE_PROCESS",
        "cron": "0 0 8 * * *",
        "runbook": "fdr/check_archive_maintenance_processes.py",
        "run_args": "C084LL01EHX",
        "worker_pool": "generic",
        "enabled": true,
        "oncall": false
      }
    ]
  }
}
