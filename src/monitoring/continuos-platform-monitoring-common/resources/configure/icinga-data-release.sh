#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Releases the Icinga data disk before its detach (VM recreation, 06_disk.tf):
# stops the services that write to it and unmounts it, so the detach doesn't
# cut off a running MySQL. Run by the destroy of terraform_data.icinga_data_release.
# The VM is not usable afterwards: it is about to be replaced
# -----------------------------------------------------------------------------
DATA_MOUNT=/var/lib/icinga-data

systemctl stop icinga-director icinga-kubernetes 'icinga-kubernetes@*' icingadb icinga2 mysql

# bind mounts first, then the filesystem; fails if something still uses it
for dir in /var/lib/mysql /var/lib/icinga2 "$DATA_MOUNT"; do
  if mountpoint -q "$dir"; then
    umount "$dir"
  fi
done
sync

echo "Icinga data disk released"
