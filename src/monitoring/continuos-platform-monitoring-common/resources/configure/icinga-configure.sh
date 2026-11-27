#!/usr/bin/env bash
set -euo pipefail

echo "icinga-configure!!!"

# -----------------------------------------------------------------------------
# Icinga - configure Icinga 2, Icinga DB and Icinga Web 2
# Run by terraform_data.icinga_configure (05_vm.tf) on top of the Packer
# image built by resources/packer/script-custom.sh, with the check plugins of
# resources/plugins. Idempotent: re-run to apply new passwords.
# Configuration only: files, databases, users, schemas, modules and services.
# No software is installed or downloaded here, it belongs to the image
# -----------------------------------------------------------------------------
: "${ICINGADB_DB_PASSWORD:?ICINGADB_DB_PASSWORD must be set}"
: "${ICINGAWEB_DB_PASSWORD:?ICINGAWEB_DB_PASSWORD must be set}"
: "${ICINGAWEB_ADMIN_USER:?ICINGAWEB_ADMIN_USER must be set}"
: "${ICINGAWEB_ADMIN_PASSWORD:?ICINGAWEB_ADMIN_PASSWORD must be set}"
: "${ICINGA_API_TERRAFORM_PASSWORD:?ICINGA_API_TERRAFORM_PASSWORD must be set}"
: "${ICINGA_API_SYNTHETIC_PASSWORD:?ICINGA_API_SYNTHETIC_PASSWORD must be set}"
: "${ICINGA_FQDN:?ICINGA_FQDN must be set}"
: "${TLS_SECRET_URL:?TLS_SECRET_URL must be set}"
: "${TLS_MSI_CLIENT_ID:?TLS_MSI_CLIENT_ID must be set}"
: "${SSO_TENANT_ID:?SSO_TENANT_ID must be set}"
: "${SSO_CLIENT_ID:?SSO_CLIENT_ID must be set}"
: "${SSO_CLIENT_SECRET:?SSO_CLIENT_SECRET must be set}"
: "${ROLE_GROUPS?ROLE_GROUPS must be set}"
: "${DATA_DISK_LUN:?DATA_DISK_LUN must be set}"
[[ "$DATA_DISK_LUN" =~ ^[0-9]+$ ]] || { echo "invalid DATA_DISK_LUN: $DATA_DISK_LUN" >&2; exit 1; }

# alphanumeric only: values go straight into SQL and config files
for var in ICINGADB_DB_PASSWORD ICINGAWEB_DB_PASSWORD ICINGAWEB_ADMIN_USER ICINGAWEB_ADMIN_PASSWORD ICINGA_API_TERRAFORM_PASSWORD ICINGA_API_SYNTHETIC_PASSWORD; do
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

# Icinga Web roles: "<role>=<object id>,...;..." (Admin, Editor, Viewer), object
# ids of the Entra ID groups mapped to each role (groups claim, sso/providers.ini)
UUID_RE='[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}'
ADMIN_GROUP_IDS="" EDITOR_GROUP_IDS="" VIEWER_GROUP_IDS=""
IFS=';' read -ra role_entries <<<"$ROLE_GROUPS"
for entry in "${role_entries[@]}"; do
  ids="${entry#*=}"
  [[ -z "$ids" || "$ids" =~ ^$UUID_RE(,$UUID_RE)*$ ]] || { echo "invalid group ids in ROLE_GROUPS: $entry" >&2; exit 1; }
  case "$entry" in
    Admin=*) ADMIN_GROUP_IDS="$ids" ;;
    Editor=*) EDITOR_GROUP_IDS="$ids" ;;
    Viewer=*) VIEWER_GROUP_IDS="$ids" ;;
    *) echo "invalid ROLE_GROUPS entry: $entry" >&2; exit 1 ;;
  esac
done

# "groups = ..." line of a role in roles.ini, nothing when no group is mapped
role_groups() {
  [[ -z "$1" ]] || echo "groups = \"$1\""
}

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
# local only database user of Icinga Reporting
REPORTING_DB_PASSWORD="$(openssl rand -hex 32)"

# write stdin to <path> with <owner:group> and <mode>
write_file() {
  cat > "$3"
  chown "$1" "$3"
  chmod "$2" "$3"
}

# -----------------------------------------------------------------------------
# Icinga data disk (06_disk.tf): the state that survives the VM recreation.
# One ext4 filesystem on the disk of the fixed LUN, mounted on DATA_MOUNT, with
# its mysql and icinga2 directories bind mounted on /var/lib/mysql and
# /var/lib/icinga2. First use: the data of the OS disk is moved to the disk.
# New VM: the data of the disk is used, the directories of the image are
# emptied. Unmounted before a detach by icinga-data-release.sh
# -----------------------------------------------------------------------------
DATA_DEVICE="/dev/disk/azure/scsi1/lun${DATA_DISK_LUN}"
DATA_MOUNT=/var/lib/icinga-data
# <directory of /var/lib>:<owner>
DATA_DIRS="mysql:mysql icinga2:nagios"

# the link of the LUN is created by udev shortly after the attach
for _ in $(seq 60); do
  [ -e "$DATA_DEVICE" ] && break
  sleep 1
done
[ -e "$DATA_DEVICE" ] || { echo "data disk not found: $DATA_DEVICE" >&2; exit 1; }

# without the disk the services don't start, instead of starting on an empty
# directory of the OS disk and creating a new state
for entry in mysql:/var/lib/mysql icinga2:/var/lib/icinga2; do
  install -d -m 0755 "/etc/systemd/system/${entry%%:*}.service.d"
  printf '[Unit]\nRequiresMountsFor=%s\n' "${entry#*:}" |
    write_file root:root 0644 "/etc/systemd/system/${entry%%:*}.service.d/icinga-data.conf"
done

if ! mountpoint -q /var/lib/mysql || ! mountpoint -q /var/lib/icinga2; then
  # nothing writes to the directories while they are moved
  systemctl stop icinga-director icinga-kubernetes 'icinga-kubernetes@*' icingadb icinga2 mysql

  # formatted only when blkid finds nothing (exit code 2): never a disk with data
  rc=0
  blkid -p "$DATA_DEVICE" >/dev/null || rc=$?
  if [ "$rc" -eq 2 ]; then
    mkfs.ext4 -q -F -L icinga-data "$DATA_DEVICE"
  elif [ "$rc" -ne 0 ]; then
    echo "blkid failed on $DATA_DEVICE (exit code $rc)" >&2
    exit 1
  fi

  # filesystem by UUID, nofail: the VM boots also without the disk
  DATA_UUID="$(blkid -s UUID -o value "$DATA_DEVICE")"
  awk -v m="$DATA_MOUNT" '$2 != m && $2 != "/var/lib/mysql" && $2 != "/var/lib/icinga2"' /etc/fstab > /etc/fstab.icinga
  {
    echo "UUID=${DATA_UUID} ${DATA_MOUNT} ext4 defaults,nofail 0 2"
    for entry in $DATA_DIRS; do
      echo "${DATA_MOUNT}/${entry%%:*} /var/lib/${entry%%:*} none bind,nofail,x-systemd.requires-mounts-for=${DATA_MOUNT} 0 0"
    done
  } >> /etc/fstab.icinga
  mv /etc/fstab.icinga /etc/fstab
  systemctl daemon-reload

  install -d -m 0755 "$DATA_MOUNT"
  mountpoint -q "$DATA_MOUNT" || mount "$DATA_MOUNT"

  for entry in $DATA_DIRS; do
    src="/var/lib/${entry%%:*}" dst="${DATA_MOUNT}/${entry%%:*}"
    mountpoint -q "$src" && continue
    # first use: copy of the OS disk, renamed only when complete
    if [ ! -d "$dst" ]; then
      rm -rf "${dst}.tmp"
      cp -a "$src" "${dst}.tmp"
      mv "${dst}.tmp" "$dst"
    fi
    # hidden by the bind mount: the copy on the OS disk or the image directory
    find "$src" -mindepth 1 -delete
    mount "$src"
  done
fi

# the UIDs of a new image may differ from the ones of the files on the disk
for entry in $DATA_DIRS; do
  owner="${entry#*:}" dst="${DATA_MOUNT}/${entry%%:*}"
  if [ "$(stat -c %u:%g "$dst")" != "$(id -u "$owner"):$(id -g "$owner")" ]; then
    chown -R "${owner}:${owner}" "$dst"
  fi
done

systemctl start mysql

# -----------------------------------------------------------------------------
# MySQL
# -----------------------------------------------------------------------------
# binary logs off: no replica and no point-in-time recovery here, while MySQL 8
# keeps them for 30 days by default and Icinga for Kubernetes writes ~100 MB of
# them every 20 minutes, filling the OS disk. MySQL is restarted only when the
# file changes, the binary logs already written are then removed
MYSQL_ICINGA_CNF=/etc/mysql/mysql.conf.d/zz-icinga.cnf
MYSQL_ICINGA_CNF_CONTENT='[mysqld]
skip-log-bin'
if [[ "$(cat "$MYSQL_ICINGA_CNF" 2>/dev/null)" != "$MYSQL_ICINGA_CNF_CONTENT" ]]; then
  printf '%s\n' "$MYSQL_ICINGA_CNF_CONTENT" | write_file root:root 0644 "$MYSQL_ICINGA_CNF"
  systemctl restart mysql
fi
rm -f /var/lib/mysql/binlog.[0-9]* /var/lib/mysql/binlog.index

# maintenance user of the package (logrotate, upgrades): its password is in
# debian.cnf of the image, its user in the databases of the data disk
DEBIAN_SYS_MAINT_PASSWORD="$(awk -F' *= *' '$1 == "password" { print $2; exit }' /etc/mysql/debian.cnf 2>/dev/null || true)"
if [[ "$DEBIAN_SYS_MAINT_PASSWORD" =~ ^[A-Za-z0-9]+$ ]]; then
  mysql -e "ALTER USER IF EXISTS 'debian-sys-maint'@'localhost' IDENTIFIED BY '${DEBIAN_SYS_MAINT_PASSWORD}'"
fi

# one database and one local user per component, passwords re-applied at every run
mysql <<SQL
-- Icinga DB: monitoring state and history, written by the icingadb daemon
CREATE DATABASE IF NOT EXISTS icingadb;
CREATE USER IF NOT EXISTS 'icingadb'@'localhost' IDENTIFIED BY '${ICINGADB_DB_PASSWORD}';
ALTER USER 'icingadb'@'localhost' IDENTIFIED BY '${ICINGADB_DB_PASSWORD}';
GRANT ALL ON icingadb.* TO 'icingadb'@'localhost';
-- Icinga Web 2: users, preferences, local admin
CREATE DATABASE IF NOT EXISTS icingaweb2;
CREATE USER IF NOT EXISTS 'icingaweb2'@'localhost' IDENTIFIED BY '${ICINGAWEB_DB_PASSWORD}';
ALTER USER 'icingaweb2'@'localhost' IDENTIFIED BY '${ICINGAWEB_DB_PASSWORD}';
GRANT ALL ON icingaweb2.* TO 'icingaweb2'@'localhost';
-- Certificate Monitoring (x509 module)
CREATE DATABASE IF NOT EXISTS x509;
CREATE USER IF NOT EXISTS 'x509'@'localhost' IDENTIFIED BY '${X509_DB_PASSWORD}';
ALTER USER 'x509'@'localhost' IDENTIFIED BY '${X509_DB_PASSWORD}';
GRANT CREATE, SELECT, INSERT, UPDATE, DELETE, DROP, ALTER, CREATE VIEW, INDEX, EXECUTE ON x509.* TO 'x509'@'localhost';
-- Icinga Director
CREATE DATABASE IF NOT EXISTS director CHARACTER SET 'utf8mb4' COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'director'@'localhost' IDENTIFIED BY '${DIRECTOR_DB_PASSWORD}';
ALTER USER 'director'@'localhost' IDENTIFIED BY '${DIRECTOR_DB_PASSWORD}';
GRANT ALL ON director.* TO 'director'@'localhost';
-- Icinga for Kubernetes: state of the AKS clusters
CREATE DATABASE IF NOT EXISTS kubernetes CHARACTER SET 'utf8mb4' COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'kubernetes'@'localhost' IDENTIFIED BY '${KUBERNETES_DB_PASSWORD}';
ALTER USER 'kubernetes'@'localhost' IDENTIFIED BY '${KUBERNETES_DB_PASSWORD}';
GRANT ALL ON kubernetes.* TO 'kubernetes'@'localhost';
-- read-only user of the check_k8s_namespace plugin
CREATE USER IF NOT EXISTS 'kubernetes_check'@'localhost' IDENTIFIED BY '${KUBERNETES_CHECK_DB_PASSWORD}';
ALTER USER 'kubernetes_check'@'localhost' IDENTIFIED BY '${KUBERNETES_CHECK_DB_PASSWORD}';
GRANT SELECT ON kubernetes.* TO 'kubernetes_check'@'localhost';
-- Icinga Reporting: reports, timeframes, schedules
CREATE DATABASE IF NOT EXISTS reporting CHARACTER SET 'utf8mb4' COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'reporting'@'localhost' IDENTIFIED BY '${REPORTING_DB_PASSWORD}';
ALTER USER 'reporting'@'localhost' IDENTIFIED BY '${REPORTING_DB_PASSWORD}';
GRANT SELECT, INSERT, UPDATE, DELETE, DROP, CREATE, ALTER, CREATE VIEW, INDEX, EXECUTE ON reporting.* TO 'reporting'@'localhost';
SQL

# import the schemas only once (empty database). Icinga Web 2 is below, Director
# and Icinga for Kubernetes create and migrate their own
import_schema() {
  if [ "$(mysql -N -s -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$1'")" -eq 0 ]; then
    mysql "$1" < "$2"
  fi
}
import_schema icingadb /usr/share/icingadb/schema/mysql/schema.sql
import_schema x509 /usr/share/icingaweb2/modules/x509/schema/mysql.schema.sql
import_schema reporting /usr/share/icingaweb2/modules/reporting/schema/mysql.schema.sql

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

# API user used by azure-synthetic-monitoring (runtime): creates its host and
# services and publishes the check results of the synthetic tests
write_file root:nagios 0640 /etc/icinga2/conf.d/api-user-synthetic.conf <<EOF
object ApiUser "synthetic" {
  password    = "${ICINGA_API_SYNTHETIC_PASSWORD}"
  permissions = [
    "objects/query/Host", "objects/query/Service",
    "objects/create/Host", "objects/create/Service",
    "actions/process-check-result"
  ]
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

# -----------------------------------------------------------------------------
# Custom check plugins: the files of resources/plugins, installed in PLUGINS_DIR
# without the extension (check_<name>.sh => check_<name>). The commands that
# write them in STAGE are added where Terraform runs, in place of the "@FILES@"
# line (resources/run-command/run-command.sh). A plugin removed from the
# repository stays on the VM, unused
# -----------------------------------------------------------------------------
PLUGINS_DIR=/usr/local/lib/nagios/plugins
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# @FILES@
install -d -m 0755 "$PLUGINS_DIR"
for f in "$STAGE"/*; do
  [[ -f "$f" ]] || continue
  name="$(basename "$f")"
  install -o root -g root -m 0755 "$f" "$PLUGINS_DIR/${name%.*}"
done
rm -rf "$STAGE"

# Kubernetes namespace check: worst Icinga for Kubernetes state of the workloads
# of a namespace, read from the kubernetes database (services created by Terraform)
write_file root:nagios 0640 /etc/icinga2/kubernetes-check.cnf <<EOF
[client]
user=kubernetes_check
password=${KUBERNETES_CHECK_DB_PASSWORD}
database=kubernetes
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

# -----------------------------------------------------------------------------
# Cosmos DB checks, services created by Terraform:
# - for MongoDB: authenticated round trip (ping + listDatabases) with the
#   read-only key of the account, read from ARM with the managed identity of the
#   VM (Cosmos DB Account Reader Role, 05_vm.tf)
# - for NoSQL: GET /dbs with an Entra ID token of the same identity
# -----------------------------------------------------------------------------
# pymongo: virtualenv /opt/icinga-plugins/venv of the image (resources/packer/script-custom.sh)

# read-only keys cache, readable by the plugin user only
install -d -o nagios -g nagios -m 0700 /var/cache/icinga2/cosmos-check

# $...$ are Icinga macros (escaped), the client id of the managed identity is
# expanded by the shell. azure_id is a var of every host created by Terraform
write_file root:nagios 0640 /etc/icinga2/conf.d/cosmos.conf <<EOF
object CheckCommand "cosmos_mongo" {
  command = [ "/usr/local/lib/nagios/plugins/check_cosmos_mongo" ]
  arguments = {
    "-i" = { value = "\$azure_id\$", required = true }
    "-H" = { value = "\$address\$", required = true }
    "-m" = { value = "\$cosmos_msi_client_id\$", required = true }
    "-w" = "\$cosmos_mongo_warning\$"
    "-c" = "\$cosmos_mongo_critical\$"
  }
  vars.cosmos_msi_client_id = "${TLS_MSI_CLIENT_ID}"
  vars.cosmos_mongo_warning = 500
  vars.cosmos_mongo_critical = 2000
}

// Cosmos DB for NoSQL: GET /dbs on the gateway with an Entra ID token of the
// managed identity (readMetadata only, data-plane role created by Terraform, app)
object CheckCommand "cosmos_nosql" {
  command = [ "/usr/local/lib/nagios/plugins/check_cosmos_nosql" ]
  arguments = {
    "-H" = { value = "\$address\$", required = true }
    "-m" = { value = "\$cosmos_msi_client_id\$", required = true }
    "-w" = "\$cosmos_nosql_warning\$"
    "-c" = "\$cosmos_nosql_critical\$"
  }
  vars.cosmos_msi_client_id = "${TLS_MSI_CLIENT_ID}"
  vars.cosmos_nosql_warning = 500
  vars.cosmos_nosql_critical = 2000
}
EOF

# Non-critical resources: the Azure resources tagged noncrit=true (host var
# "noncrit", set by Terraform, app) are in downtime from 18:00 to 09:00, so no
# notification is sent for them out of working hours. Checks keep running: the
# downtime only silences notifications and marks the objects in Icinga Web.
# The ranges are in the local time of the icinga2 process (the VM is in UTC):
# TZ is set on the service only, to follow the daylight saving time
install -d -m 0755 /etc/systemd/system/icinga2.service.d
write_file root:root 0644 /etc/systemd/system/icinga2.service.d/timezone.conf <<'EOF'
[Service]
Environment=TZ=Europe/Rome
EOF

write_file root:nagios 0640 /etc/icinga2/conf.d/noncrit.conf <<'EOF'
// one range per day, like the ITL 24x7 period: the "monday - sunday" form wraps
// around the week and is not reliable
const NoncritOffHours = {
  "monday" = "00:00-09:00,18:00-24:00"
  "tuesday" = "00:00-09:00,18:00-24:00"
  "wednesday" = "00:00-09:00,18:00-24:00"
  "thursday" = "00:00-09:00,18:00-24:00"
  "friday" = "00:00-09:00,18:00-24:00"
  "saturday" = "00:00-09:00,18:00-24:00"
  "sunday" = "00:00-09:00,18:00-24:00"
}

// the downtime is applied to the hosts and to their services: the notifications
// of a service are not silenced by the downtime of its host
apply ScheduledDowntime "noncrit-offhours" to Host {
  author = "icingaadmin"
  comment = "Non-critical resource: out of working hours (18:00-09:00)"
  fixed = true
  ranges = NoncritOffHours
  assign where host.vars.noncrit == "true"
}

apply ScheduledDowntime "noncrit-offhours" to Service {
  author = "icingaadmin"
  comment = "Non-critical resource: out of working hours (18:00-09:00)"
  fixed = true
  ranges = NoncritOffHours
  assign where host.vars.noncrit == "true"
}
EOF

icinga2 feature enable icingadb

systemctl enable --now icingadb-redis
systemctl enable icinga2
icinga2 daemon -C
systemctl daemon-reload
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

# history (state changes, notifications, downtimes, acknowledgements, comments)
# kept 30 days, SLA data (Icinga Reporting) one year: removed by Icinga DB itself
retention:
  history-days: 30
  sla-days: 365
EOF

systemctl enable icingadb
systemctl restart icingadb

# -----------------------------------------------------------------------------
# Icinga for Kubernetes - one daemon instance per AKS cluster
# https://icinga.com/docs/icinga-for-kubernetes/latest/doc/02-Installation/
# The schema is imported and migrated by the daemon itself
# -----------------------------------------------------------------------------
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
  /etc/icingaweb2/modules/kubernetes \
  /etc/icingaweb2/modules/pdfexport \
  /etc/icingaweb2/modules/reporting

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

; default resource name of Icinga Reporting, no reporting/config.ini needed
[reporting]
type = "db"
db = "mysql"
host = "localhost"
dbname = "reporting"
username = "reporting"
password = "${REPORTING_DB_PASSWORD}"
charset = "utf8mb4"
EOF

write_file root:icingaweb2 0660 /etc/icingaweb2/config.ini <<EOF
[global]
config_resource = "icingaweb_db"

; "pagopa" module, installed by terraform_data.icinga_theme (07_theme.tf)
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

# Roles of the Entra ID groups (object ids from the groups claim, map_groups in
# sso/providers.ini). In every role the values of the variables that may hold
# secrets are shown as *** (Bearer tokens of the AKS checks, check passwords).
# Read-only access to Icinga DB: no icingadb/command/* permission
write_file root:icingaweb2 0660 /etc/icingaweb2/roles.ini <<EOF
; everything, also to the local admin user (login without Entra ID)
[Admin]
users = "${ICINGAWEB_ADMIN_USER}"
$(role_groups "$ADMIN_GROUP_IDS")
permissions = "*"
icingadb/protect/variables = "http_header,*pass*,*token*"

; Business Process view and edit, Icinga DB read-only, reports view and edit
; (no schedules, templates and timeframes), no Director and Kubernetes
[Editor]
$(role_groups "$EDITOR_GROUP_IDS")
permissions = "module/businessprocess,businessprocess/showall,businessprocess/create,businessprocess/modify,module/icingadb,module/pagopa,module/reporting,reporting/reports"
icingadb/protect/variables = "http_header,*pass*,*token*"

; Business Process view, Icinga DB read-only, reports view
[Viewer]
$(role_groups "$VIEWER_GROUP_IDS")
permissions = "module/businessprocess,businessprocess/showall,module/icingadb,module/pagopa,module/reporting"
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
# in 06_sso.tf. offline_access gives the refresh token used to renew the
# session when the tokens expire. Groups mapped as Icinga Web groups: the groups
# claim holds the object ids of the groups assigned to the application (roles.ini)
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
map_groups = "y"
groups_claim = "groups"
EOF

for module in icingadb businessprocess x509 director sso kubernetes pdfexport reporting; do
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
# Apache: HTTPS for Icinga Web, certificate of icinga-tls-sync. Reverse proxy,
# with the same certificate, for the Icinga API (/v1/, port 5665) and the
# business process API (/bp-api/, port 8080, listening on localhost only):
# clients such as azure-synthetic-monitoring verify the Let's Encrypt
# certificate with the system CAs, without the Icinga CA nor the VM hostname
# -----------------------------------------------------------------------------
a2enmod -q ssl rewrite headers proxy proxy_http

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

    ProxyRequests     Off
    ProxyTimeout      30
    # the Icinga API is reached on loopback: its certificate is verified against
    # the Icinga CA, not its name (issued for the VM short hostname, not 127.0.0.1)
    SSLProxyEngine        on
    SSLProxyVerify        require
    SSLProxyCACertificateFile /var/lib/icinga2/certs/ca.crt
    SSLProxyCheckPeerName off

    # authentication of both APIs unchanged: the Authorization header is forwarded
    ProxyPass        /v1/ https://127.0.0.1:5665/v1/
    ProxyPassReverse /v1/ https://127.0.0.1:5665/v1/
    ProxyPass        /bp-api/ http://127.0.0.1:8080/
    ProxyPassReverse /bp-api/ http://127.0.0.1:8080/
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
