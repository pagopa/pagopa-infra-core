#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Icinga - configure Icinga 2, Icinga DB and Icinga Web 2
# Runs via azurerm_virtual_machine_run_command (03_vm.tf) on top of the Packer
# image built by script-custom.sh. Idempotent: re-run to apply new passwords.
# -----------------------------------------------------------------------------
: "${ICINGADB_DB_PASSWORD:?ICINGADB_DB_PASSWORD must be set}"
: "${ICINGAWEB_DB_PASSWORD:?ICINGAWEB_DB_PASSWORD must be set}"
: "${ICINGAWEB_ADMIN_USER:?ICINGAWEB_ADMIN_USER must be set}"
: "${ICINGAWEB_ADMIN_PASSWORD:?ICINGAWEB_ADMIN_PASSWORD must be set}"
: "${ICINGA_API_TERRAFORM_PASSWORD:?ICINGA_API_TERRAFORM_PASSWORD must be set}"
: "${ICINGA_FQDN:?ICINGA_FQDN must be set}"
: "${TLS_SECRET_URL:?TLS_SECRET_URL must be set}"
: "${TLS_MSI_CLIENT_ID:?TLS_MSI_CLIENT_ID must be set}"
: "${SSO_TENANT_ID:?SSO_TENANT_ID must be set}"
: "${SSO_CLIENT_ID:?SSO_CLIENT_ID must be set}"
: "${SSO_CLIENT_SECRET:?SSO_CLIENT_SECRET must be set}"
: "${SSO_ADMIN_USERS:?SSO_ADMIN_USERS must be set}"

# alphanumeric only: values go straight into SQL and config files
for var in ICINGADB_DB_PASSWORD ICINGAWEB_DB_PASSWORD ICINGAWEB_ADMIN_USER ICINGAWEB_ADMIN_PASSWORD ICINGA_API_TERRAFORM_PASSWORD; do
  [[ "${!var}" =~ ^[A-Za-z0-9]+$ ]] || { echo "$var must be alphanumeric" >&2; exit 1; }
done

# values go into the Apache and systemd configuration
[[ "$ICINGA_FQDN" =~ ^[a-z0-9.-]+$ ]] || { echo "invalid ICINGA_FQDN: $ICINGA_FQDN" >&2; exit 1; }
[[ "$TLS_SECRET_URL" =~ ^https://[a-z0-9-]+\.vault\.azure\.net/secrets/[A-Za-z0-9-]+$ ]] || { echo "invalid TLS_SECRET_URL: $TLS_SECRET_URL" >&2; exit 1; }
for var in TLS_MSI_CLIENT_ID SSO_TENANT_ID SSO_CLIENT_ID; do
  [[ "${!var}" =~ ^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$ ]] || { echo "invalid $var: ${!var}" >&2; exit 1; }
done

# values go into the Icinga Web ini files (double quoted)
[[ "$SSO_CLIENT_SECRET" =~ ^[A-Za-z0-9~._-]+$ ]] || { echo "SSO_CLIENT_SECRET contains unexpected characters" >&2; exit 1; }
[[ "$SSO_ADMIN_USERS" =~ ^[A-Za-z0-9._@-]+(,[A-Za-z0-9._@-]+)*$ ]] || { echo "invalid SSO_ADMIN_USERS: $SSO_ADMIN_USERS" >&2; exit 1; }

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

; "pagopa" module, installed by azurerm_virtual_machine_run_command.icinga_theme (05_theme.tf)
[themes]
default = "pagopa/default"

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

; Entra ID users (preferred_username, see sso/providers.ini)
[SSO Administrators]
users = "${SSO_ADMIN_USERS}"
permissions = "*"
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

# "Login with Microsoft Entra ID" button on the login page, Entra ID application
# in 04_sso.tf. offline_access gives the refresh token used to renew the
# session when the tokens expire, groups are not mapped (no groups claim)
# https://icinga.com/docs/icinga-sso/latest/doc/03-Configuration/
write_file root:icingaweb2 0660 /etc/icingaweb2/modules/sso/providers.ini <<EOF
[entra]
name = "Microsoft Entra ID"
base_url = "https://login.microsoftonline.com/${SSO_TENANT_ID}/v2.0/.well-known/openid-configuration"
client_id = "${SSO_CLIENT_ID}"
client_secret = "${SSO_CLIENT_SECRET}"
scopes = "openid profile email offline_access"
redirect_url = "https://${ICINGA_FQDN}/icingaweb2/sso/oidc/redirection-endpoint"
username_claim = "preferred_username"
map_groups = "n"
groups_claim = "groups"
EOF

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

# deploys the pending changes (all of them at the first run); skipped when the
# configuration checksum matches the last deployment. --wait fails the run if
# Icinga 2 doesn't activate the configuration
icingacli director config deploy --wait 60

systemctl enable icinga-director
systemctl restart icinga-director

# -----------------------------------------------------------------------------
# TLS certificate of Icinga Web, synced from domain_kv by icinga-tls-sync
# Same unit at the first configuration (started below, before Apache) and at
# every certificate renewal (icinga-tls-sync.timer, hourly). Each version gets
# its own directory, "current" is swapped atomically so certificate and key
# always change together, then Apache is reloaded
# -----------------------------------------------------------------------------
write_file root:root 0600 /etc/default/icinga-tls-sync <<EOF
TLS_SECRET_URL=${TLS_SECRET_URL}
TLS_MSI_CLIENT_ID=${TLS_MSI_CLIENT_ID}
ICINGA_FQDN=${ICINGA_FQDN}
EOF

write_file root:root 0755 /usr/local/sbin/icinga-tls-sync <<'EOF'
#!/usr/bin/env bash
# Installs the latest version of the TLS certificate of Icinga Web from Key Vault
# Idempotent: exits without changes when the installed version is the latest one
set -euo pipefail
umask 077

: "${TLS_SECRET_URL:?TLS_SECRET_URL must be set}"
: "${TLS_MSI_CLIENT_ID:?TLS_MSI_CLIENT_ID must be set}"
: "${ICINGA_FQDN:?ICINGA_FQDN must be set}"

DIR=/var/lib/icinga-tls
KEEP=2 # installed versions kept on disk
VHOST=/etc/apache2/sites-enabled/icingaweb2-ssl.conf

die() { echo "ERROR: $*" >&2; exit 1; }

mkdir -p "$DIR"
work="$(mktemp -d "$DIR/.tmp.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# access token of the user assigned identity, the identity endpoint may not be
# ready yet at the first boot
token="$(curl -sS --fail --max-time 30 --retry 10 --retry-connrefused --retry-delay 5 -H Metadata:true \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net&client_id=${TLS_MSI_CLIENT_ID}" |
  jq -er .access_token)"

# versionless URL: always the latest version. The header is read from stdin,
# so the token doesn't show up in the process list
curl -sS --fail --max-time 30 --retry 5 --retry-delay 5 -H @- -o "$work/secret.json" \
  "${TLS_SECRET_URL}?api-version=7.4" <<<"Authorization: Bearer ${token}"
unset token

version="$(jq -er '.id | split("/") | last' "$work/secret.json")"
[[ "$version" =~ ^[0-9a-f]{32}$ ]] || die "unexpected secret version: $version"
[[ "$(jq -r .contentType "$work/secret.json")" == "application/x-pkcs12" ]] || die "secret is not a PKCS12 certificate"

if [[ "$(cat "$DIR/installed-version" 2>/dev/null)" == "$version" && -s "$DIR/current/fullchain.pem" ]]; then
  echo "version $version already installed"
  exit 0
fi
echo "installing version $version"

# certificates exported by Key Vault have no password
jq -er .value "$work/secret.json" | base64 -d > "$work/cert.pfx"
rm -f "$work/secret.json"
openssl pkcs12 -in "$work/cert.pfx" -passin pass: -nocerts -nodes | openssl pkey -out "$work/privkey.pem"
# leaf: the certificate bound to the private key (localKeyID), then the chain
openssl pkcs12 -in "$work/cert.pfx" -passin pass: -nokeys -clcerts | openssl x509 -out "$work/leaf.pem"
openssl pkcs12 -in "$work/cert.pfx" -passin pass: -nokeys -cacerts |
  awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' > "$work/chain.pem"

# checks before touching the installed certificate
[[ "$(openssl pkey -in "$work/privkey.pem" -pubout | sha256sum)" == "$(openssl x509 -in "$work/leaf.pem" -noout -pubkey | sha256sum)" ]] ||
  die "private key doesn't match the certificate"
openssl x509 -in "$work/leaf.pem" -noout -checkhost "$ICINGA_FQDN" | grep -q "does match" ||
  die "certificate isn't valid for $ICINGA_FQDN"
openssl x509 -in "$work/leaf.pem" -noout -checkend 0 > /dev/null || die "certificate is expired"
openssl x509 -in "$work/leaf.pem" -noout -subject -enddate

rm -rf "${DIR:?}/$version"
mkdir "$DIR/$version"
cat "$work/leaf.pem" "$work/chain.pem" > "$DIR/$version/fullchain.pem"
mv "$work/privkey.pem" "$DIR/$version/privkey.pem"

previous="$(readlink "$DIR/current" || true)"
ln -sfn "$version" "$DIR/current.new"
mv -Tf "$DIR/current.new" "$DIR/current"

# Apache uses the certificate only after its virtual host is configured
if [[ -e "$VHOST" ]]; then
  if ! apachectl configtest; then
    if [[ -n "$previous" ]]; then
      ln -sfn "$previous" "$DIR/current.new"
      mv -Tf "$DIR/current.new" "$DIR/current"
    fi
    die "Apache configuration test failed, restored version ${previous:-none}"
  fi
  systemctl reload apache2
fi

echo "$version" > "$DIR/installed-version.new"
mv -f "$DIR/installed-version.new" "$DIR/installed-version"

# keeps the newest $KEEP versions, always including the current one
current="$(readlink "$DIR/current")"
find "$DIR" -mindepth 1 -maxdepth 1 -type d -regextype posix-extended -regex '.*/[0-9a-f]{32}' -printf '%T@ %f\n' |
  sort -rn | tail -n +$((KEEP + 1)) | cut -d' ' -f2 |
  while read -r old; do
    [[ "$old" == "$current" ]] || rm -rf "${DIR:?}/$old"
  done
echo "version $version installed"
EOF

write_file root:root 0644 /etc/systemd/system/icinga-tls-sync.service <<'EOF'
[Unit]
Description=Sync the TLS certificate of Icinga Web from Key Vault
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/default/icinga-tls-sync
ExecStart=/usr/local/sbin/icinga-tls-sync
TimeoutStartSec=10min
ProtectSystem=full
PrivateTmp=yes
NoNewPrivileges=yes
EOF

write_file root:root 0644 /etc/systemd/system/icinga-tls-sync.timer <<'EOF'
[Unit]
Description=Hourly sync of the TLS certificate of Icinga Web from Key Vault

[Timer]
OnBootSec=5min
OnCalendar=hourly
RandomizedDelaySec=10min
# runs missed while the VM was stopped are executed at the next boot
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
# synchronous (oneshot): a failure stops this script before Apache is configured
systemctl start icinga-tls-sync.service
systemctl enable --now icinga-tls-sync.timer

# -----------------------------------------------------------------------------
# Apache: HTTPS for Icinga Web, certificate of icinga-tls-sync
# -----------------------------------------------------------------------------
a2enmod -q ssl rewrite headers

write_file root:root 0644 /etc/apache2/sites-available/icingaweb2-ssl.conf <<EOF
<VirtualHost *:80>
    ServerName ${ICINGA_FQDN}
    RewriteEngine On
    RewriteRule ^/?(.*) https://${ICINGA_FQDN}/\$1 [R=301,L]
</VirtualHost>

<VirtualHost *:443>
    ServerName ${ICINGA_FQDN}
    DocumentRoot /var/www/html

    SSLEngine on
    SSLCertificateFile    /var/lib/icinga-tls/current/fullchain.pem
    SSLCertificateKeyFile /var/lib/icinga-tls/current/privkey.pem

    RedirectMatch ^/$ /icingaweb2/
</VirtualHost>
EOF

# the default site also listens on :80 and would answer instead of the redirect
if [[ -e /etc/apache2/sites-enabled/000-default.conf ]]; then
  a2dissite -q 000-default
fi
a2ensite -q icingaweb2-ssl

apachectl configtest
# restart, not reload: a2enmod requires it
systemctl restart apache2
