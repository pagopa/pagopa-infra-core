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
apt -y install mysql-server
