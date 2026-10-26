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

# alphanumeric only: values go straight into SQL and config files
for var in ICINGADB_DB_PASSWORD ICINGAWEB_DB_PASSWORD ICINGAWEB_ADMIN_USER ICINGAWEB_ADMIN_PASSWORD; do
  [[ "${!var}" =~ ^[A-Za-z0-9]+$ ]] || { echo "$var must be alphanumeric" >&2; exit 1; }
done

# local only API user, used by Icinga DB Web to send commands to Icinga 2
ICINGA_API_PASSWORD="$(openssl rand -hex 32)"

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
# certificates use the VM hostname, so the API is set up here and not in the image
icinga2 api setup

write_file root:nagios 0640 /etc/icinga2/conf.d/api-user-icingaweb2.conf <<EOF
object ApiUser "icingaweb2" {
  password    = "${ICINGA_API_PASSWORD}"
  permissions = [ "actions/*", "objects/query/*", "objects/modify/*", "status/query" ]
}
EOF

icinga2 feature enable icingadb

systemctl enable --now icingadb-redis
systemctl enable icinga2
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
# Icinga Web 2 + Icinga DB Web module
# https://icinga.com/docs/icinga-web/latest/doc/05-Authentication/
# https://icinga.com/docs/icinga-db-web/latest/doc/03-Configuration/
# -----------------------------------------------------------------------------
icingacli setup config directory --group icingaweb2
install -d -o root -g icingaweb2 -m 2770 /etc/icingaweb2/modules/icingadb

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
EOF

write_file root:icingaweb2 0660 /etc/icingaweb2/config.ini <<EOF
[global]
config_resource = "icingaweb_db"

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

icingacli module enable icingadb
