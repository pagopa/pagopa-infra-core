#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Icinga Web "pagopa" module (theme pagopa/default), files from
# templates/theme. Run by terraform_data.icinga_theme (07_theme.tf) after
# icinga-configure.sh, which sets the theme as default.
# The commands that write the files are added where Terraform runs, in place
# of the "@THEME_FILES@" line (templates/run-command.sh runs the result).
# The module is rebuilt in a staging directory and swapped, so files removed
# from the repository are removed from the VM too
# -----------------------------------------------------------------------------
: "${THEME_HASH:?THEME_HASH must be set}"

MODULES_DIR=/usr/share/icingaweb2/modules
MODULE_DIR="$MODULES_DIR/pagopa"

STAGE="$(mktemp -d "$MODULES_DIR/.pagopa.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

# @THEME_FILES@
chmod -R u=rwX,go=rX "$STAGE"

rm -rf "$MODULE_DIR.old"
if [[ -d "$MODULE_DIR" ]]; then
  mv "$MODULE_DIR" "$MODULE_DIR.old"
fi
mv "$STAGE" "$MODULE_DIR"
rm -rf "$MODULE_DIR.old"

# theme previously installed by continuos-platform-monitoring-app
rm -f /usr/share/icingaweb2/public/css/themes/bp-tiles.less

icingacli module enable pagopa
echo "pagopa module installed ($THEME_HASH)"
