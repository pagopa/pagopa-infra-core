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

# -----------------------------------------------------------------------------
# Titillium Web (Google Fonts), font of the theme. Downloaded here and served
# by Apache from the public directory of Icinga Web as
# /icingaweb2/font/pagopa/titillium-web-<weight>.woff2 (default.less), so the
# browsers don't contact Google. Not fatal: without the files the theme falls
# back to the system fonts, a failed download keeps the files already installed
# -----------------------------------------------------------------------------
FONT_DIR=/usr/share/icingaweb2/public/font/pagopa
FONT_CSS_URL='https://fonts.googleapis.com/css2?family=Titillium+Web:wght@300;400;600;700&display=swap'
FONT_WEIGHTS=4
# Google Fonts serves woff2 only to a modern user agent
FONT_UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36'

install_fonts() {
  local css fonts weight url tmp
  css="$(curl -sS --fail --max-time 30 --retry 3 -A "$FONT_UA" "$FONT_CSS_URL")" || return 1

  # "<weight> <url>" of the "latin" subset, one @font-face per weight
  fonts="$(awk '
    /\/\* latin \*\// { latin = 1 }
    latin && /font-weight:/ { weight = $2; sub(/;/, "", weight) }
    latin && /src: url\(/ {
      match($0, /url\([^)]+\)/)
      print weight, substr($0, RSTART + 4, RLENGTH - 5)
      latin = 0
    }' <<<"$css")"
  [[ "$(grep -cE '^[0-9]+ https://fonts\.gstatic\.com/[^ ]+\.woff2$' <<<"$fonts")" == "$FONT_WEIGHTS" ]] || return 1

  install -d -m 0755 "$FONT_DIR"
  while read -r weight url; do
    tmp="$(mktemp "$FONT_DIR/.font.XXXXXX")"
    if ! curl -sS --fail --max-time 30 --retry 3 -o "$tmp" "$url" || [[ "$(head -c 4 "$tmp")" != "wOF2" ]]; then
      rm -f "$tmp"
      return 1
    fi
    chmod 0644 "$tmp"
    mv -f "$tmp" "$FONT_DIR/titillium-web-$weight.woff2"
  done <<<"$fonts"
}

if install_fonts; then
  echo "Titillium Web installed in $FONT_DIR"
else
  echo "WARNING: Titillium Web not downloaded, the theme uses the files already in $FONT_DIR or the system fonts" >&2
fi

icingacli module enable pagopa
echo "pagopa module installed ($THEME_HASH)"
