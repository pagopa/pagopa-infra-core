#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Icinga - configure Icinga 2, Icinga DB and Icinga Web 2
# Runs via azurerm_virtual_machine_run_command (00_vm.tf) on top of the Packer
# image built by script-custom.sh. Idempotent: re-run to apply new passwords.
# -----------------------------------------------------------------------------
: "${ICINGADB_DB_PASSWORD:?ICINGADB_DB_PASSWORD must be set}"
: "${ICINGAWEB_DB_PASSWORD:?ICINGAWEB_DB_PASSWORD must be set}"
: "${ICINGAWEB_ADMIN_USER:?ICINGAWEB_ADMIN_USER must be set}"
: "${ICINGAWEB_ADMIN_PASSWORD:?ICINGAWEB_ADMIN_PASSWORD must be set}"
: "${ICINGA_API_TERRAFORM_PASSWORD:?ICINGA_API_TERRAFORM_PASSWORD must be set}"

# alphanumeric only: values go straight into SQL and config files
for var in ICINGADB_DB_PASSWORD ICINGAWEB_DB_PASSWORD ICINGAWEB_ADMIN_USER ICINGAWEB_ADMIN_PASSWORD ICINGA_API_TERRAFORM_PASSWORD; do
  [[ "${!var}" =~ ^[A-Za-z0-9]+$ ]] || { echo "$var must be alphanumeric" >&2; exit 1; }
done

# Icinga for Kubernetes: "<key>=<cluster name> ...", kubeconfig (base64) in AKS_KUBECONFIG_<KEY>
AKS_CLUSTERS="${AKS_CLUSTERS:-}"
for entry in $AKS_CLUSTERS; do
  key="${entry%%=*}"
  name="${entry#*=}"
  var="AKS_KUBECONFIG_${key^^}"
  [[ "$key" =~ ^[a-z0-9]+$ && "$name" =~ ^[a-z0-9-]+$ ]] || { echo "invalid AKS_CLUSTERS entry: $entry" >&2; exit 1; }
  [[ "${!var:-}" =~ ^[A-Za-z0-9+/=]+$ ]] || { echo "$var must be set (base64)" >&2; exit 1; }
done

# local only API user, used by Icinga DB Web to send commands to Icinga 2
ICINGA_API_PASSWORD="$(openssl rand -hex 32)"
# local only database user of the x509 module
X509_DB_PASSWORD="$(openssl rand -hex 32)"
# local only database user of Icinga Director
DIRECTOR_DB_PASSWORD="$(openssl rand -hex 32)"
# local only API user, used by Icinga Director to deploy its configuration
DIRECTOR_API_PASSWORD="$(openssl rand -hex 32)"
# local only database user of Icinga for Kubernetes
KUBERNETES_DB_PASSWORD="$(openssl rand -hex 32)"
# local only read-only database user of the check_k8s_namespace plugin
KUBERNETES_CHECK_DB_PASSWORD="$(openssl rand -hex 32)"

# write stdin to <path> with <owner:group> and <mode>
write_file() {
  cat > "$3"
  chown "$1" "$3"
  chmod "$2" "$3"
}

# -----------------------------------------------------------------------------
# MySQL
# -----------------------------------------------------------------------------
mysql <<SQL
ALTER USER 'icingadb'@'localhost' IDENTIFIED BY '${ICINGADB_DB_PASSWORD}';
CREATE DATABASE IF NOT EXISTS icingaweb2;
CREATE USER IF NOT EXISTS 'icingaweb2'@'localhost' IDENTIFIED BY '${ICINGAWEB_DB_PASSWORD}';
ALTER USER 'icingaweb2'@'localhost' IDENTIFIED BY '${ICINGAWEB_DB_PASSWORD}';
GRANT ALL ON icingaweb2.* TO 'icingaweb2'@'localhost';
ALTER USER 'x509'@'localhost' IDENTIFIED BY '${X509_DB_PASSWORD}';
CREATE DATABASE IF NOT EXISTS director CHARACTER SET 'utf8mb4' COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'director'@'localhost' IDENTIFIED BY '${DIRECTOR_DB_PASSWORD}';
ALTER USER 'director'@'localhost' IDENTIFIED BY '${DIRECTOR_DB_PASSWORD}';
GRANT ALL ON director.* TO 'director'@'localhost';
CREATE DATABASE IF NOT EXISTS kubernetes CHARACTER SET 'utf8mb4' COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'kubernetes'@'localhost' IDENTIFIED BY '${KUBERNETES_DB_PASSWORD}';
ALTER USER 'kubernetes'@'localhost' IDENTIFIED BY '${KUBERNETES_DB_PASSWORD}';
GRANT ALL ON kubernetes.* TO 'kubernetes'@'localhost';
CREATE USER IF NOT EXISTS 'kubernetes_check'@'localhost' IDENTIFIED BY '${KUBERNETES_CHECK_DB_PASSWORD}';
ALTER USER 'kubernetes_check'@'localhost' IDENTIFIED BY '${KUBERNETES_CHECK_DB_PASSWORD}';
GRANT SELECT ON kubernetes.* TO 'kubernetes_check'@'localhost';
SQL

# import the Icinga Web 2 schema only once
if [ "$(mysql -N -s -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'icingaweb2'")" -eq 0 ]; then
  for schema in /usr/share/icingaweb2/schema/mysql.schema.sql /usr/share/icingaweb2/etc/schema/mysql.schema.sql; do
    [ -f "$schema" ] && break
  done
  mysql icingaweb2 < "$schema"
fi

# Icinga Web 2 admin user (bcrypt hash, password read from the environment)
export ICINGAWEB_ADMIN_PASSWORD
ICINGAWEB_ADMIN_HASH="$(php -r 'echo password_hash(getenv("ICINGAWEB_ADMIN_PASSWORD"), PASSWORD_DEFAULT);')"

mysql icingaweb2 <<SQL
INSERT INTO icingaweb_user (name, active, password_hash)
  VALUES ('${ICINGAWEB_ADMIN_USER}', 1, '${ICINGAWEB_ADMIN_HASH}')
  ON DUPLICATE KEY UPDATE active = 1, password_hash = VALUES(password_hash);
SQL

# -----------------------------------------------------------------------------
# Icinga 2
# https://icinga.com/docs/icinga-2/latest/doc/02-installation/02-Ubuntu/
# -----------------------------------------------------------------------------
# certificates use the VM hostname, so the API is set up here and not in the image.
# The short hostname is used as CN: the Azure FQDN exceeds the 64 chars X.509 limit
icinga2 api setup --cn "$(hostname -s)"

# api setup names the local zone after the CN: hosts created by Terraform
# (continuos-platform-monitoring-app) are placed in the "master" zone
sed -i 's/^const ZoneName = .*/const ZoneName = "master"/' /etc/icinga2/constants.conf

write_file root:nagios 0640 /etc/icinga2/zones.conf <<EOF
object Endpoint NodeName {
}

object Zone ZoneName {
  endpoints = [ NodeName ]
}

object Zone "global-templates" {
  global = true
}

object Zone "director-global" {
  global = true
}
EOF

write_file root:nagios 0640 /etc/icinga2/conf.d/api-user-icingaweb2.conf <<EOF
object ApiUser "icingaweb2" {
  password    = "${ICINGA_API_PASSWORD}"
  permissions = [ "actions/*", "objects/query/*", "objects/modify/*", "status/query" ]
}
EOF

# API user used by Terraform (continuos-platform-monitoring-app) to manage hosts and services
write_file root:nagios 0640 /etc/icinga2/conf.d/api-user-terraform.conf <<EOF
object ApiUser "terraform" {
  password    = "${ICINGA_API_TERRAFORM_PASSWORD}"
  permissions = [ "objects/query/*", "objects/create/*", "objects/modify/*", "objects/delete/*", "status/query" ]
}
EOF

# https://icinga.com/docs/icinga-director/latest/doc/02-Installation/
write_file root:nagios 0640 /etc/icinga2/conf.d/api-user-director.conf <<EOF
object ApiUser "director" {
  password    = "${DIRECTOR_API_PASSWORD}"
  permissions = [ "*" ]
}
EOF

# the packaged services.conf applies ping4/ping6/ssh to every host with an address,
# so also to the Azure resources created by Terraform, which do not answer ICMP.
# Only the checks of the Icinga node itself are kept
write_file root:nagios 0640 /etc/icinga2/conf.d/services.conf <<'EOF'
apply Service "icinga" {
  import "generic-service"
  check_command = "icinga"
  assign where host.name == NodeName
}

apply Service "disk" {
  import "generic-service"
  check_command = "disk"
  assign where host.name == NodeName
}

apply Service "load" {
  import "generic-service"
  check_command = "load"
  assign where host.name == NodeName
}

apply Service "procs" {
  import "generic-service"
  check_command = "procs"
  assign where host.name == NodeName
}

apply Service "swap" {
  import "generic-service"
  check_command = "swap"
  assign where host.name == NodeName
}

apply Service "users" {
  import "generic-service"
  check_command = "users"
  assign where host.name == NodeName
}
EOF

# Kubernetes namespace check: worst Icinga for Kubernetes state of the workloads
# of a namespace, read from the kubernetes database (services created by Terraform)
write_file root:nagios 0640 /etc/icinga2/kubernetes-check.cnf <<EOF
[client]
user=kubernetes_check
password=${KUBERNETES_CHECK_DB_PASSWORD}
database=kubernetes
EOF

install -d /usr/local/lib/nagios/plugins
write_file root:root 0755 /usr/local/lib/nagios/plugins/check_k8s_namespace <<'EOF'
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
EOF

write_file root:nagios 0640 /etc/icinga2/conf.d/kubernetes.conf <<'EOF'
object CheckCommand "k8s_namespace" {
  command = [ "/usr/local/lib/nagios/plugins/check_k8s_namespace" ]
  arguments = {
    "-c" = { value = "$k8s_cluster$", required = true }
    "-n" = { value = "$k8s_namespace$", required = true }
    "-a" = "$k8s_heartbeat_max_age$"
  }
  vars.k8s_heartbeat_max_age = 300
}
EOF

icinga2 feature enable icingadb

systemctl enable --now icingadb-redis
systemctl enable icinga2
icinga2 daemon -C
systemctl restart icinga2

# -----------------------------------------------------------------------------
# Icinga DB
# https://icinga.com/docs/icinga-db/latest/doc/03-Configuration/
# -----------------------------------------------------------------------------
write_file root:icingadb 0640 /etc/icingadb/config.yml <<EOF
database:
  type: mysql
  host: localhost
  database: icingadb
  user: icingadb
  password: ${ICINGADB_DB_PASSWORD}

redis:
  host: localhost
  port: 6380
EOF

systemctl enable icingadb
systemctl restart icingadb

# -----------------------------------------------------------------------------
# Icinga for Kubernetes - one daemon instance per AKS cluster
# https://icinga.com/docs/icinga-for-kubernetes/latest/doc/02-Installation/
# The schema is imported and migrated by the daemon itself
# -----------------------------------------------------------------------------
# already in images built with the current script-custom.sh, installed here on older ones
ICINGA_KUBERNETES_VERSION="0.4.0-1+ubuntu$(. /etc/os-release; echo "$VERSION_ID")"
for pkg in icinga-kubernetes icinga-kubernetes-web; do
  if [ "$(dpkg-query -W -f '${Version}' "$pkg" 2>/dev/null)" != "$ICINGA_KUBERNETES_VERSION" ]; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      "icinga-kubernetes=${ICINGA_KUBERNETES_VERSION}" "icinga-kubernetes-web=${ICINGA_KUBERNETES_VERSION}"
    break
  fi
done

# icinga-kubernetes-web 0.4.0: HighlightDelta throws "Short name must be part of
# long name" when a pod name does not contain its ReplicaSet name (Kubernetes
# truncates the generated prefix to 58 chars), breaking the Deployment view.
# The full name is shown instead. No-op once patched or fixed upstream
sed -i "s|throw new InvalidArgumentException('Short name must be part of long name');|\$this->short = '';|" \
  /usr/share/icingaweb2/modules/kubernetes/library/Kubernetes/Web/Widget/HighlightDelta.php

write_file root:icinga-kubernetes 0640 /etc/icinga-kubernetes/config.yml <<EOF
database:
  host: localhost
  database: kubernetes
  user: kubernetes
  password: ${KUBERNETES_DB_PASSWORD}
EOF

# the packaged units only wait for mariadb.service and restart after 100ms, so
# a failing instance (e.g. DB not ready yet) would quickly hit the start limit
install -d /etc/systemd/system/icinga-kubernetes@.service.d
write_file root:root 0644 /etc/systemd/system/icinga-kubernetes@.service.d/override.conf <<'EOF'
[Unit]
Wants=mysql.service
After=mysql.service
StartLimitIntervalSec=0

[Service]
RestartSec=10s
EOF
rm -f /etc/systemd/system/icinga-kubernetes@.service.d/mysql.conf

# every *.env is an instance: the packaged default.env (in-cluster config) is
# removed too, as are clusters no longer listed in AKS_CLUSTERS
systemctl stop icinga-kubernetes
rm -f /etc/icinga-kubernetes/*.env /etc/icinga-kubernetes/*.kubeconfig
# also forgets instances whose env file is gone (e.g. the packaged "default")
systemctl reset-failed 'icinga-kubernetes@*' || true

for entry in $AKS_CLUSTERS; do
  key="${entry%%=*}"
  name="${entry#*=}"
  var="AKS_KUBECONFIG_${key^^}"

  base64 -d <<<"${!var}" | write_file root:icinga-kubernetes 0640 "/etc/icinga-kubernetes/${name}.kubeconfig"
  write_file root:icinga-kubernetes 0640 "/etc/icinga-kubernetes/${name}.env" <<EOF
KUBECONFIG=/etc/icinga-kubernetes/${name}.kubeconfig
ICINGA_FOR_KUBERNETES_CLUSTER_NAME=${name}
EOF
done

# the generator creates one icinga-kubernetes@<name> per env file
systemctl daemon-reload
systemctl enable icinga-kubernetes
systemctl start icinga-kubernetes

# -----------------------------------------------------------------------------
# Icinga Web 2 + Icinga DB Web module
# https://icinga.com/docs/icinga-web/latest/doc/05-Authentication/
# https://icinga.com/docs/icinga-db-web/latest/doc/03-Configuration/
# -----------------------------------------------------------------------------
# same result as "icingacli setup config directory", the setup module is not packaged
install -d -o root -g icingaweb2 -m 2770 \
  /etc/icingaweb2 \
  /etc/icingaweb2/modules \
  /etc/icingaweb2/modules/icingadb \
  /etc/icingaweb2/modules/x509 \
  /etc/icingaweb2/modules/director \
  /etc/icingaweb2/modules/businessprocess \
  /etc/icingaweb2/modules/businessprocess/processes \
  /etc/icingaweb2/modules/sso \
  /etc/icingaweb2/modules/kubernetes

write_file root:icingaweb2 0660 /etc/icingaweb2/resources.ini <<EOF
[icingaweb_db]
type = "db"
db = "mysql"
host = "localhost"
dbname = "icingaweb2"
username = "icingaweb2"
password = "${ICINGAWEB_DB_PASSWORD}"
charset = "utf8mb4"

[icingadb]
type = "db"
db = "mysql"
host = "localhost"
dbname = "icingadb"
username = "icingadb"
password = "${ICINGADB_DB_PASSWORD}"
charset = "utf8mb4"

[x509]
type = "db"
db = "mysql"
host = "localhost"
dbname = "x509"
username = "x509"
password = "${X509_DB_PASSWORD}"
charset = "utf8mb4"

[director_db]
type = "db"
db = "mysql"
host = "localhost"
dbname = "director"
username = "director"
password = "${DIRECTOR_DB_PASSWORD}"
charset = "utf8mb4"

[kubernetes]
type = "db"
db = "mysql"
host = "localhost"
dbname = "kubernetes"
username = "kubernetes"
password = "${KUBERNETES_DB_PASSWORD}"
charset = "utf8mb4"
EOF

write_file root:icingaweb2 0660 /etc/icingaweb2/config.ini <<EOF
[global]
config_resource = "icingaweb_db"

; theme installed by continuos-platform-monitoring-app (02_icinga_bp.tf)
[themes]
default = "bp-tiles"

[logging]
log = "syslog"
level = "ERROR"
application = "icingaweb2"
facility = "user"
EOF

write_file root:icingaweb2 0660 /etc/icingaweb2/authentication.ini <<EOF
[icingaweb2]
backend = "db"
resource = "icingaweb_db"
EOF

write_file root:icingaweb2 0660 /etc/icingaweb2/groups.ini <<EOF
[icingaweb2]
backend = "db"
resource = "icingaweb_db"
EOF

write_file root:icingaweb2 0660 /etc/icingaweb2/roles.ini <<EOF
[Administrators]
users = "${ICINGAWEB_ADMIN_USER}"
permissions = "*"
groups = "Administrators"
; valori mostrati come *** (token Bearer dei check AKS, password dei check)
icingadb/protect/variables = "http_header,*pass*,*token*"
EOF

write_file root:icingaweb2 0660 /etc/icingaweb2/modules/icingadb/config.ini <<EOF
[icingadb]
resource = "icingadb"
EOF

write_file root:icingaweb2 0660 /etc/icingaweb2/modules/icingadb/redis.ini <<EOF
[redis1]
host = "localhost"
port = "6380"
EOF

write_file root:icingaweb2 0660 /etc/icingaweb2/modules/icingadb/commandtransports.ini <<EOF
[icinga2]
transport = "api"
host = "localhost"
port = "5665"
username = "icingaweb2"
password = "${ICINGA_API_PASSWORD}"
EOF

write_file root:icingaweb2 0660 /etc/icingaweb2/modules/x509/config.ini <<EOF
[backend]
resource = "x509"
EOF

write_file root:icingaweb2 0660 /etc/icingaweb2/modules/director/config.ini <<EOF
[db]
resource = "director_db"
EOF

write_file root:icingaweb2 0660 /etc/icingaweb2/modules/kubernetes/config.ini <<EOF
[database]
resource = "kubernetes"
EOF

write_file root:icingaweb2 0660 /etc/icingaweb2/modules/director/kickstart.ini <<EOF
[config]
endpoint = "$(hostname -s)"
host = "127.0.0.1"
port = "5665"
username = "director"
password = "${DIRECTOR_API_PASSWORD}"
EOF

# sso providers (/etc/icingaweb2/modules/sso/providers.ini) are configured later
for module in icingadb businessprocess x509 director sso kubernetes; do
  icingacli module enable "$module"
done

# trusted root CAs of the system store, needed to validate the scanned chains.
# Already imported certificates are skipped, so it is safe to re-run
# https://icinga.com/docs/icinga-certificate-monitoring/latest/doc/03-Configuration/#importing-ca-certificates
icingacli x509 import --file /etc/ssl/certs/ca-certificates.crt

# -----------------------------------------------------------------------------
# Icinga Director
# https://icinga.com/docs/icinga-director/latest/doc/03-Automation/
# -----------------------------------------------------------------------------
# creates or upgrades the schema, then imports endpoint, zones and ITL commands
# from the Icinga 2 API. Kickstart is re-run to store the new API password
icingacli director migration run --verbose
icingacli director kickstart run

systemctl enable icinga-director
systemctl restart icinga-director
