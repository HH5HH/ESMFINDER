#!/bin/bash
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <ARG_SOFTWARE_STATEMENT> <ESM_URL>" >&2
  exit 1
fi

# ================= PROGRESS INDICATOR =================
PROGRESS_COUNT=0
SPINNER='|/-\\'

progress_tick() {
  PROGRESS_COUNT=$((PROGRESS_COUNT + 1))
  local i=$((PROGRESS_COUNT % 4))
  printf "\r[%c] Crawling ESM tree... (%d)" "${SPINNER:$i:1}" "$PROGRESS_COUNT" >&2
}

progress_done() {
  printf "\r[✓] Crawl complete. %d ESM nodes processed.\n" "$PROGRESS_COUNT" >&2
}

trap progress_done EXIT

# ================= CONFIG =================
BASE_URL="https://mgmt.auth.adobe.com"
ARG_SOFTWARE_STATEMENT="$1"
START_URL="$2"
START_PATH="${START_URL%%\?*}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/clickESM.html"

if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "Template not found: $TEMPLATE_FILE" >&2
  exit 1
fi

FIRST_DL_LINE="$(grep -n '^<dl>$' "$TEMPLATE_FILE" | head -n 1 | cut -d: -f1)"
LAST_DL_LINE="$(grep -n '^</dl>$' "$TEMPLATE_FILE" | tail -n 1 | cut -d: -f1)"

if [ -z "${FIRST_DL_LINE:-}" ] || [ -z "${LAST_DL_LINE:-}" ] || [ "$FIRST_DL_LINE" -ge "$LAST_DL_LINE" ]; then
  echo "Template parse failed (could not detect <dl> section bounds in $TEMPLATE_FILE)." >&2
  exit 1
fi

# ================= AUTH BOOTSTRAP =================
RESPONSE1=$(curl -s -X POST -H 'Content-Type: application/json' \
  'https://sp.auth.adobe.com/o/client/register' \
  --data-raw "{\"software_statement\":\"$ARG_SOFTWARE_STATEMENT\"}")

CID=$(echo "$RESPONSE1" | jq -r '.client_id')
CSC=$(echo "$RESPONSE1" | jq -r '.client_secret')

RESPONSE2=$(curl -s -X POST -H 'Content-Type: application/json' \
  "https://sp.auth.adobe.com/o/client/token?grant_type=client_credentials&client_id=$CID&client_secret=$CSC")

TOKEN=$(echo "$RESPONSE2" | jq -r '.access_token')
AUTH_HEADER="Authorization: Bearer $TOKEN"

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\\&#/]/\\\\&/g'
}

emit_template_header() {
  local cid_esc csc_esc token_esc
  cid_esc="$(escape_sed_replacement "$CID")"
  csc_esc="$(escape_sed_replacement "$CSC")"
  token_esc="$(escape_sed_replacement "$TOKEN")"

  sed -n "1,$((FIRST_DL_LINE - 1))p" "$TEMPLATE_FILE" \
    | sed -E \
      -e "s#<input type=\"hidden\" name=\"cid\" value=\"[^\"]*\">#<input type=\"hidden\" name=\"cid\" value=\"${cid_esc}\">#" \
      -e "s#<input type=\"hidden\" name=\"csc\" value=\"[^\"]*\">#<input type=\"hidden\" name=\"csc\" value=\"${csc_esc}\">#" \
      -e "s#<input type=\"hidden\" name=\"access_token\" value=\"[^\"]*\">#<input type=\"hidden\" name=\"access_token\" value=\"${token_esc}\">#"
}

emit_template_footer() {
  sed -n "$((LAST_DL_LINE + 1)),\$p" "$TEMPLATE_FILE"
}

# ================= TREE WALK =================
process_json() {
  progress_tick
  local path="$1"

  local json_url="${path}.json?limit=1"
  local response
  response=$(curl -s -H "$AUTH_HEADER" "$json_url")

  local zm_level="unknown"
  case "$path" in
    *"/minute"*) zm_level="zmMIN" ;;
    *"/hour"*)   zm_level="zmHR"  ;;
    *"/day"*)    zm_level="zmDAY" ;;
    *"/month"*)  zm_level="zmMO"  ;;
    *"/year"*)   zm_level="zmYR"  ;;
  esac

  echo "<dl>"
  echo "<dt><a href=\"$path\" class=\"$zm_level\" onclick=\"runEsm(this);return false;\">$path</a></dt>"

  if echo "$response" | jq -e '.report and .report[0] and (.report[0]|type=="object")' >/dev/null 2>&1; then
    echo "<dd class=\"col-list\">$(echo "$response" | jq -r '.report[0] | keys[]')</dd>"
  else
    echo "<dd class=\"col-list\"><em>No report columns</em></dd>"
  fi

  echo "<dd class=\"esm-table-host\"></dd>"
  echo "</dl>"

  if echo "$response" | jq -e '._links."drill-down"' >/dev/null 2>&1; then
    while read -r link; do
      process_json "$BASE_URL$link"
    done < <(
      echo "$response" \
      | jq -r '._links."drill-down" | if type=="array" then .[] else . end | .href'
    )
  fi
}

# ================= OUTPUT =================
emit_template_header
process_json "$START_PATH"
emit_template_footer
