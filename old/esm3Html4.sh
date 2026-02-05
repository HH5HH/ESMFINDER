#!/bin/bash
if [ $# -ne 2 ]; then
  echo "Usage: $0 <ARG_SOFTWARE_STATEMENT> <ESM_URL>"
  exit 1
fi

base_url="https://mgmt.auth.adobe.com"
url_extras=".json?limit=1"

ARG_SOFTWARE_STATEMENT="$1"
ESM_URL="$2"

# ---------------- AUTH ----------------
RESPONSE1=$(curl -s -X POST -H 'Content-Type: application/json' \
  'https://sp.auth.adobe.com/o/client/register' \
  --data-raw "{\"software_statement\":\"$ARG_SOFTWARE_STATEMENT\"}")

CID=$(echo "$RESPONSE1" | jq -r '.client_id')
CSECRET=$(echo "$RESPONSE1" | jq -r '.client_secret')

RESPONSE2=$(curl -s -X POST -H 'Content-Type: application/json' \
  "https://sp.auth.adobe.com/o/client/token?grant_type=client_credentials&client_id=$CID&client_secret=$CSECRET")

TOKEN=$(echo "$RESPONSE2" | jq -r '.access_token')

auth_header="Authorization: Bearer $TOKEN"

echo "<input type='hidden' name='access_token' value='$TOKEN' />"

# ---------------- TREE (UNCHANGED STRUCTURE) ----------------
process_json() {
  local url="$1"
  local response
  response=$(curl -s -H "$auth_header" "$url")

  echo "<dl>"

  url_clean=${url//$url_extras/}

  # --- ZOOM CLASS (exact esm2Html.sh logic) ---
  if [[ "$url_clean" == *"/minute"* ]]; then
    ZMLEVEL="zmMIN"
  elif [[ "$url_clean" == *"/hour"* ]]; then
    ZMLEVEL="zmHR"
  elif [[ "$url_clean" == *"/day"* ]]; then
    ZMLEVEL="zmDAY"
  elif [[ "$url_clean" == *"/month"* ]]; then
    ZMLEVEL="zmMO"
  elif [[ "$url_clean" == *"/year"* ]]; then
    ZMLEVEL="zmYR"
  else
    ZMLEVEL="unknown"
  fi

  echo "<dt>
<a href=\"$url_clean\" class=\"$ZMLEVEL\" onclick=\"runEsm(this);return false;\">$url_clean</a>
</dt>"

  if echo "$response" | jq -e . >/dev/null 2>&1; then
    COLS=$(echo "$response" | jq -r '.report[0] | keys[]')
  else
    COLS="<code>$response</code>"
  fi

  # --- ORIGINAL COLUMN LIST (UNCHANGED) ---
  echo "<dd class=\"col-list\">$COLS</dd>"

  # --- TABLE HOST (NEW, SEPARATE DD) ---
  echo "<dd class=\"esm-table-host\"></dd>"

  if [[ "$response" == *"drill-down"* ]]; then
    links=$(echo "$response" | jq -r '._links."drill-down" | if type=="array" then .[] else . end | .href')
    for link in $links; do
      echo "</dl>"
      process_json "$base_url$link$url_extras"
    done
  fi

  echo "</dl>"
}

# ---------------- HTML ----------------
echo "<!DOCTYPE html>
<html lang=\"en\">
<head>
<meta charset=\"UTF-8\">
<title>ESM3 FINDIT</title>

<style>
a:hover{color:yellowgreen}
.zmMIN{color:#9a6e3b}
.zmHR{color:#e2862c}
.zmDAY{color:#f52f30}
.zmMO{color:#3ee841}
.zmYR{color:#000}

body{background:slategray;font-family:Arial;margin:20px}
dl{background:#f9f9f9;padding:15px;border-radius:5px}
dt{font-weight:700;margin-top:10px}
dd{margin-left:20px;margin-bottom:10px}

.col-list{color:#000}
.search-container{margin:20px 0}
input,select{padding:10px;font-size:16px}
button{padding:10px 20px;font-size:16px}
.reset-button{background:#f44336;color:#fff}

/* -------- TABLE -------- */
.esm-table-wrapper{
  max-height:14.5em;
  overflow:auto;
  border:1px solid #355;
  background:#111;
}

table{
  border-collapse:collapse;
  width:max-content;
  min-width:100%;
  color:#9ff;
}

th,td{
  padding:4px 8px;
  white-space:nowrap;
  border-bottom:1px solid #355;
}

thead th{
  position:sticky;
  top:0;
  background:#122;
}

tfoot td{
  position:sticky;
  bottom:0;
  background:#111;
}

tbody tr:nth-child(even){
  background:rgba(80,180,180,0.08);
}
</style>
</head>
<body>

<div class=\"search-container\">
<select id=\"filterSelect\" onchange=\"filterList()\">
<option value=\"\"></option>
<option value=\"YR\">YR</option>
<option value=\"MO\">MO</option>
<option value=\"DAY\">DAY</option>
<option value=\"HR\">HR</option>
<option value=\"MIN\">MIN</option>
</select>
<input id=\"searchText\" placeholder=\"ESM Column search...\">
<button onclick=\"highlightText()\">FIND IT</button>
<button class=\"reset-button\" onclick=\"resetList()\">RESET</button>
</div>
"

process_json "$ESM_URL$url_extras"

echo "
<script>
/* -------- ORIGINAL FIND / FILTER (UNCHANGED) -------- */
function highlightText(){
  const t=document.getElementById('searchText').value.toLowerCase();
  document.querySelectorAll('dl').forEach(dl=>{
    const dd=dl.querySelector('.col-list');
    dl.style.display=dd && dd.innerText.toLowerCase().includes(t)?'':'none';
  });
}
function resetList(){
  document.querySelectorAll('dl').forEach(dl=>dl.style.display='');
  document.getElementById('searchText').value='';
  document.getElementById('filterSelect').selectedIndex=0;
}
function filterList(){
  const f=document.getElementById('filterSelect').value;
  document.querySelectorAll('dl').forEach(dl=>{
    const a=dl.querySelector('a');
    dl.style.display=!f || a.classList.contains('zm'+f)?'':'none';
  });
}

/* -------- TABLE RENDER -------- */
async function runEsm(a){
  const token=document.querySelector('input[name=access_token]').value;
  const url=a.href;

  const host=a.closest('dl').querySelector('.esm-table-host');
  host.innerHTML='<div class=\"esm-table-wrapper\">Loading…</div>';

  const r=await fetch(url,{headers:{Authorization:'Bearer '+token}});
  const json=await r.json();

  const cols=Object.keys(json.report[0]);
  let html='<div class=\"esm-table-wrapper\"><table><thead><tr>';
  cols.forEach(c=>html+='<th>'+c+'</th>');
  html+='</tr></thead><tbody>';

  json.report.forEach(row=>{
    html+='<tr>';
    cols.forEach(c=>html+='<td>'+(row[c]??'')+'</td>');
    html+='</tr>';
  });

  html+='</tbody><tfoot><tr><td colspan=\"'+cols.length+'\">'+
        '<a href=\"#\" onclick=\"downloadCsv(\\''+url+'\\');return false;\">CSV</a>'+
        '</td></tr></tfoot></table></div>';

  host.innerHTML=html;
}

async function downloadCsv(url){
  const token=document.querySelector('input[name=access_token]').value;
  const r=await fetch(url+'?format=csv',{headers:{Authorization:'Bearer '+token}});
  const blob=await r.blob();
  const a=document.createElement('a');
  a.href=URL.createObjectURL(blob);
  a.target='_blank';
  a.click();
}
</script>
</body>
</html>"
