#!/usr/bin/env bash
set -euo pipefail

echo "CUSTOM!!!"

# -----------------------------------------------------------------------------
# Icinga image: the software only, with pinned versions. No state and no
# passwords: databases, users, schemas and configuration files are created by
# resources/configure/icinga-configure.sh. Any change here needs a new
# icinga_image_version (env/<env>/terraform.tfvars), which recreates the VM
# -----------------------------------------------------------------------------

# base tools: HTTPS apt sources, downloads, network troubleshooting
apt update
apt -y install apt-transport-https wget
apt -y install net-tools
# JSON of the Key Vault REST API, used by icinga-tls-sync (icinga-configure.sh)
apt -y install jq
# virtualenv of the Python check plugins, with pymongo (below)
apt -y install python3-venv

# Icinga package repository: signing key and apt source for this Ubuntu release
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

# Icinga 2, Icinga DB (+ Redis), Icinga Web 2 with Icinga DB Web, Director, check plugins
apt -y install icinga2 icingacli icingadb icingadb-redis icingadb-web icingaweb2 icinga-director monitoring-plugins
# Icinga Web modules: Business Process, Certificate Monitoring
apt -y install icinga-businessprocess icinga-x509
# local MySQL 8 of all the Icinga databases (created by icinga-configure.sh)
apt -y install mysql-server

# -----------------------------------------------------------------------------
# Icinga for Kubernetes: daemon + Icinga Web module
# -----------------------------------------------------------------------------
ICINGA_KUBERNETES_VERSION="0.4.0-1+ubuntu$(. /etc/os-release; echo "$VERSION_ID")"
apt -y install "icinga-kubernetes=${ICINGA_KUBERNETES_VERSION}" "icinga-kubernetes-web=${ICINGA_KUBERNETES_VERSION}"

# icinga-kubernetes-web 0.4.0: HighlightDelta throws "Short name must be part of
# long name" when a pod name does not contain its ReplicaSet name (Kubernetes
# truncates the generated prefix to 58 chars), breaking the Deployment view.
# The full name is shown instead. No-op once fixed upstream
sed -i "s|throw new InvalidArgumentException('Short name must be part of long name');|\$this->short = '';|" \
  /usr/share/icingaweb2/modules/kubernetes/library/Kubernetes/Web/Widget/HighlightDelta.php

# -----------------------------------------------------------------------------
# Icinga SSO: icinga-sso-web is not yet published for this release (only
# icinga-noble), the package is architecture independent, so install the noble build
# -----------------------------------------------------------------------------
ICINGA_SSO_WEB_DEB="icinga-sso-web_1.0.0-1+ubuntu24.04_all.deb"
wget -O "/tmp/${ICINGA_SSO_WEB_DEB}" "https://packages.icinga.com/ubuntu/pool/main/i/icinga-sso-web/${ICINGA_SSO_WEB_DEB}"
apt -y install "/tmp/${ICINGA_SSO_WEB_DEB}"
rm -f "/tmp/${ICINGA_SSO_WEB_DEB}"

# -----------------------------------------------------------------------------
# Icinga Web modules not published as stable packages for this release:
# Reporting (SLA reports on the Icinga DB data) and PDF Export, which Reporting
# requires. Release tarballs from GitHub, pinned by version and sha256. A new
# Reporting version may need the scripts of schema/mysql-upgrades on the
# reporting database. No Chrome: reports are shown in Icinga Web, the PDF export
# and the scheduled reports don't work
# https://icinga.com/docs/icinga-reporting/latest/doc/02-Installation/
# -----------------------------------------------------------------------------
install_web_module() {
  local name="$1" repo="$2" version="$3" sha256="$4"
  local dir="/usr/share/icingaweb2/modules/$name" tgz
  tgz="$(mktemp)"
  wget -q -O "$tgz" "https://github.com/Icinga/${repo}/archive/refs/tags/v${version}.tar.gz"
  echo "${sha256}  ${tgz}" | sha256sum -c --quiet -
  rm -rf "$dir"
  install -d -m 0755 "$dir"
  tar -xzf "$tgz" -C "$dir" --strip-components=1 --no-same-owner
  rm -f "$tgz"
}

install_web_module pdfexport icingaweb2-module-pdfexport 0.13.0 79b97d235fa5d4a45255b4de9dc6ac86322297a397831a7b0c1bd9e3ee944d09
install_web_module reporting icingaweb2-module-reporting 1.1.0 2318e67be3d4eeb809387be273fc89b4befa867f85ef2b5416d3f2b718ab7b9e

# -----------------------------------------------------------------------------
# Python check plugins (resources/plugins): virtualenv with pymongo, shebang of
# check_cosmos_mongo. Not the Ubuntu package: pymongo 4.14+ refuses MongoDB 4.0
# servers (wire version 7), still used by some accounts. NO_EXT: pure Python,
# no compiler needed and no wheel required for the Python version of the image
# -----------------------------------------------------------------------------
PLUGINS_VENV=/opt/icinga-plugins/venv
PYMONGO_VERSION=4.13.2

python3 -m venv "$PLUGINS_VENV"
NO_EXT=1 "$PLUGINS_VENV/bin/pip" install --quiet --no-cache-dir "pymongo==${PYMONGO_VERSION}"
"$PLUGINS_VENV/bin/python3" -c 'import pymongo; print("pymongo", pymongo.version)'

# MySQL started at boot, needed by icinga-configure.sh
systemctl enable mysql
