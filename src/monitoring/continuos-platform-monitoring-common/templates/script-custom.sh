#!/usr/bin/env bash
set -euo pipefail

echo "CUSTOM!!!"

apt update
apt -y install apt-transport-https wget
apt -y install net-tools
wget -O icinga-archive-keyring.deb "https://packages.icinga.com/icinga-archive-keyring_latest+ubuntu$(
 . /etc/os-release; echo "$VERSION_ID"
).deb"

apt -y install ./icinga-archive-keyring.deb

cat >/etc/apt/sources.list.d/icinga.sources <<EOF
Types: deb deb-src
URIs: https://packages.icinga.com/ubuntu/
Suites: icinga-$(. /etc/os-release; echo "$VERSION_CODENAME")
Components: main
Signed-By: /usr/share/keyrings/icinga-archive-keyring.gpg
EOF

apt update

apt -y install icinga2 icingacli icingadb icingadb-redis icingadb-web icingaweb2 icinga-director monitoring-plugins
# Icinga Web modules: SSO (OIDC), Business Process, Certificate Monitoring
apt -y install icinga-businessprocess icinga-x509

# icinga-sso-web is not yet published for this release (only icinga-noble):
# the package is architecture independent, so install the noble build
ICINGA_SSO_WEB_DEB="icinga-sso-web_1.0.0-1+ubuntu24.04_all.deb"
wget -O "/tmp/${ICINGA_SSO_WEB_DEB}" "https://packages.icinga.com/ubuntu/pool/main/i/icinga-sso-web/${ICINGA_SSO_WEB_DEB}"
apt -y install "/tmp/${ICINGA_SSO_WEB_DEB}"
rm -f "/tmp/${ICINGA_SSO_WEB_DEB}"
apt -y install mysql-server

# -----------------------------------------------------------------------------
# Icinga DB - MySQL database and schema
# https://icinga.com/docs/icinga-db/latest/doc/02-Installation/Ubuntu/#setting-up-the-database
# -----------------------------------------------------------------------------
ICINGADB_DB_PASSWORD="$(openssl rand -hex 32)"

systemctl enable --now mysql

mysql <<SQL
CREATE DATABASE IF NOT EXISTS icingadb;
CREATE USER IF NOT EXISTS 'icingadb'@'localhost' IDENTIFIED BY '${ICINGADB_DB_PASSWORD}';
GRANT ALL ON icingadb.* TO 'icingadb'@'localhost';
FLUSH PRIVILEGES;
SQL

unset ICINGADB_DB_PASSWORD

# import the schema only once
if [ "$(mysql -N -s -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'icingadb'")" -eq 0 ]; then
  mysql icingadb < /usr/share/icingadb/schema/mysql/schema.sql
fi

# -----------------------------------------------------------------------------
# Icinga Certificate Monitoring - MySQL database and schema
# https://icinga.com/docs/x509/latest/doc/02-Installation/Ubuntu/
# -----------------------------------------------------------------------------
X509_DB_PASSWORD="$(openssl rand -hex 32)"

mysql <<SQL
CREATE DATABASE IF NOT EXISTS x509;
CREATE USER IF NOT EXISTS 'x509'@'localhost' IDENTIFIED BY '${X509_DB_PASSWORD}';
GRANT CREATE, SELECT, INSERT, UPDATE, DELETE, DROP, ALTER, CREATE VIEW, INDEX, EXECUTE ON x509.* TO 'x509'@'localhost';
FLUSH PRIVILEGES;
SQL

unset X509_DB_PASSWORD

# import the schema only once
if [ "$(mysql -N -s -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'x509'")" -eq 0 ]; then
  mysql x509 < /usr/share/icingaweb2/modules/x509/schema/mysql.schema.sql
fi
