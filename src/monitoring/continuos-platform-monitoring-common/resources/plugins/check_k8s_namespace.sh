#!/usr/bin/env bash
# usage: check_k8s_namespace -c <cluster name> -n <namespace> [-a <max heartbeat age in seconds>]
set -uo pipefail

cluster="" namespace="" max_age=300
while getopts "c:n:a:" opt; do
  case "$opt" in
    c) cluster="$OPTARG" ;;
    n) namespace="$OPTARG" ;;
    a) max_age="$OPTARG" ;;
    *) echo "UNKNOWN - usage: $0 -c <cluster> -n <namespace> [-a <seconds>]"; exit 3 ;;
  esac
done
# also keeps the values safe to use in SQL
[[ "$cluster" =~ ^[a-z0-9-]+$ && "$namespace" =~ ^[a-z0-9-]+$ && "$max_age" =~ ^[0-9]+$ ]] || {
  echo "UNKNOWN - invalid arguments"; exit 3;
}

# runs a query, the result in $out (not a subshell, so that exit ends the check)
query() {
  out="$(mysql --defaults-extra-file=/etc/icinga2/kubernetes-check.cnf -N -B -e "$1" 2>&1)" || {
    echo "UNKNOWN - database query failed: ${out%%$'\n'*}"; exit 3;
  }
}

# the daemon of the cluster must be alive and reach the API server, or the data is stale
query "SELECT i.kubernetes_api_reachable, CAST(UNIX_TIMESTAMP() AS SIGNED) - CAST(i.heartbeat DIV 1000 AS SIGNED)
  FROM kubernetes_instance i JOIN cluster c ON c.uuid = i.cluster_uuid
  WHERE c.name = '$cluster' ORDER BY i.heartbeat DESC LIMIT 1"
instance="$out"
[ -n "$instance" ] || { echo "UNKNOWN - no Icinga for Kubernetes instance for cluster $cluster"; exit 3; }
read -r reachable age <<<"$instance"
[ "$age" -le "$max_age" ] || { echo "UNKNOWN - icinga-kubernetes@$cluster last heartbeat ${age}s ago"; exit 3; }
[ "$reachable" = "y" ] || { echo "UNKNOWN - icinga-kubernetes@$cluster cannot reach the API server"; exit 3; }

query "SELECT COUNT(*) FROM namespace n JOIN cluster c ON c.uuid = n.cluster_uuid
  WHERE c.name = '$cluster' AND n.name = '$namespace'"
[ "$out" -gt 0 ] || {
  echo "UNKNOWN - namespace $namespace not found in cluster $cluster"; exit 3;
}

# workloads only: their state already accounts for their pods; jobs are left out,
# the state of their CronJob reports failed runs
query "SELECT r.icinga_state, r.kind, r.name,
    REPLACE(REPLACE(COALESCE(r.icinga_state_reason, ''), '\n', ' '), '\t', ' ')
  FROM (
    SELECT 'Deployment' AS kind, cluster_uuid, namespace, name, icinga_state, icinga_state_reason FROM deployment
    UNION ALL SELECT 'StatefulSet', cluster_uuid, namespace, name, icinga_state, icinga_state_reason FROM stateful_set
    UNION ALL SELECT 'DaemonSet', cluster_uuid, namespace, name, icinga_state, icinga_state_reason FROM daemon_set
    UNION ALL SELECT 'CronJob', cluster_uuid, namespace, name, icinga_state, icinga_state_reason FROM cron_job
  ) r JOIN cluster c ON c.uuid = r.cluster_uuid
  WHERE c.name = '$cluster' AND r.namespace = '$namespace'
  ORDER BY FIELD(r.icinga_state, 'unknown', 'warning', 'critical') DESC, r.kind, r.name"

ok=0 warning=0 critical=0 unknown=0 details=""
while IFS=$'\t' read -r state kind name reason; do
  [ -n "$state" ] || continue
  case "$state" in
    critical) critical=$((critical + 1)) ;;
    warning) warning=$((warning + 1)) ;;
    unknown) unknown=$((unknown + 1)) ;;
    *) ok=$((ok + 1)); continue ;;
  esac
  details+=$'\n'"[${state^^}] $kind $name: ${reason:0:300}"
done <<<"$out"

if [ "$critical" -gt 0 ]; then status=CRITICAL rc=2
elif [ "$warning" -gt 0 ]; then status=WARNING rc=1
elif [ "$unknown" -gt 0 ]; then status=UNKNOWN rc=3
else status=OK rc=0
fi

echo "$status - namespace $namespace: $critical critical, $warning warning, $unknown unknown, $ok ok" \
  "| critical=$critical warning=$warning unknown=$unknown ok=$ok$details"
exit "$rc"
