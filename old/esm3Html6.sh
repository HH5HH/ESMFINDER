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

# ---------------- TREE ----------------
process_json() {
  local url="$1"
  local response
  response=$(curl -s -H "$auth_header" "$url")
  local url_clean="${url//$url_extras/}"

  if [[ "$url_clean" == *"/minute"* ]]; then ZMLEVEL="zmMIN"
  elif [[ "$url_clean" == *"/hour"* ]]; then ZMLEVEL="zmHR"
  elif [[ "$url_clean" == *"/day"* ]]; then ZMLEVEL="zmDAY"
  elif [[ "$url_clean" == *"/month"* ]]; then ZMLEVEL="zmMO"
  elif [[ "$url_clean" == *"/year"* ]]; then ZMLEVEL="zmYR"
  else ZMLEVEL="unknown"
  fi

  echo "<dl>"
  echo "<dt><a href=\"$url_clean\" class=\"$ZMLEVEL\" onclick=\"runEsm(this);return false;\">$url_clean</a></dt>"

  if echo "$response" | jq -e '.report and (.report|type=="array") and (.report[0]|type=="object")' >/dev/null 2>&1; then
    echo "<dd class=\"col-list\">$(echo "$response" | jq -r '.report[0] | keys[]')</dd>"
  else
    echo "<dd class=\"col-list\"><em>No report columns</em></dd>"
  fi

  echo "<dd class=\"esm-table-host\"></dd>"
  echo "</dl>"

  if echo "$response" | jq -e '._links."drill-down"' >/dev/null 2>&1; then
    echo "$response" | jq -r '._links."drill-down" | if type=="array" then .[] else . end | .href' |
    while read -r link; do
      process_json "$base_url$link$url_extras"
    done
  fi
}

# ---------------- HTML ----------------
cat <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>ESM3 FINDIT</title>

<style>
:root{
  --bg:#D5D5D8;
  --panel:#FFFFFF;
  --accent:#E26A5A;
  --table-head:#ECEFED;
  --table-row:#F9FAF9;
  --table-alt:#F1F3F1;
}

body{background:var(--bg);font-family:system-ui,Arial;margin:20px}
dl{background:var(--panel);padding:14px;border-radius:8px;margin-bottom:14px;box-shadow:0 1px 3px rgba(0,0,0,.06)}
dt{font-weight:600}
dd{margin-left:20px;margin-bottom:10px}
.col-list{color:#6A6A6A;font-size:13px}
a{color:var(--accent);text-decoration:none}
a:hover{text-decoration:underline}

.search-container{margin:20px 0}
input,select{padding:10px;font-size:15px}
button{padding:10px 20px}
.reset-button{background:var(--accent);color:#fff;border:none;border-radius:4px}

.esm-table-wrapper{max-height:14.5em;overflow:auto;border:1px solid #DDD;border-radius:6px}
table{border-collapse:collapse;width:100%;table-layout:fixed;font-size:13px}
th,td{padding:6px 10px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;border-bottom:1px solid #DDD;text-align:left}
thead th{position:sticky;top:0;background:var(--table-head)}
tfoot td{position:sticky;bottom:0;background:#fff}
tbody tr:nth-child(odd){background:var(--table-row)}
tbody tr:nth-child(even){background:var(--table-alt)}
tbody tr:hover{background:#F0EEE9}
</style>
</head>
<body>

<div class="search-container">
<select id="filterSelect" onchange="filterList()">
<option value=""></option>
<option value="YR">YR</option>
<option value="MO">MO</option>
<option value="DAY">DAY</option>
<option value="HR">HR</option>
<option value="MIN">MIN</option>
</select>
<input id="searchText" placeholder="ESM Column search...">
<button onclick="highlightText()">FIND IT</button>
<button class="reset-button" onclick="resetList()">RESET</button>
</div>
EOF

process_json "$ESM_URL$url_extras"

cat <<'EOF'
<script>
const METRIC_COLUMNS=new Set([
  'authn-attempts','authn-successful','authn-pending','authn-failed',
  'clientless-tokens','clientless-failures',
  'authz-attempts','authz-successful','authz-failed','authz-rejected',
  'authz-latency','media-tokens',
  'unique-accounts','unique-sessions','count'
]);
const DATE_PARTS=['year','month','day','hour','minute'];

function buildDate(r){
  const y=r.year??1970, m=(r.month??1)-1, d=r.day??1, h=r.hour??0, n=r.minute??0;
  return new Date(y,m,d,h,n).toLocaleString('en-US',{
    month:'2-digit',day:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit'
  });
}

function highlightText(){
  const t=searchText.value.toLowerCase();
  document.querySelectorAll('dl').forEach(dl=>{
    dl.style.display=dl.innerText.toLowerCase().includes(t)?'':'none';
  });
}
function resetList(){
  document.querySelectorAll('dl').forEach(dl=>dl.style.display='');
  searchText.value=''; filterSelect.selectedIndex=0;
}
function filterList(){
  const f=filterSelect.value;
  document.querySelectorAll('dl').forEach(dl=>{
    const a=dl.querySelector('a');
    dl.style.display=!f||a.classList.contains('zm'+f)?'':'none';
  });
}

async function runEsm(a){
  const url=a.href;
  const token=document.querySelector('input[name=access_token]').value;
  const host=a.closest('dl').querySelector('.esm-table-host');

  host.innerHTML='<div class="esm-table-wrapper"><table><thead><tr></tr></thead><tbody></tbody><tfoot><tr></tr></tfoot></table></div>';

  const r=await fetch(url,{headers:{Authorization:'Bearer '+token}});
  const json=await r.json();
  if(!json.report||!json.report[0]) return;

  const row0=json.report[0];
  const hasAuthN = row0['authn-attempts']!=null && row0['authn-successful']!=null;
  const hasAuthZ = row0['authz-attempts']!=null && row0['authz-successful']!=null;
  const hasCount = row0['count']!=null;

  const allCols=Object.keys(row0);
  const displayCols=allCols.filter(c=>!METRIC_COLUMNS.has(c)&&!DATE_PARTS.includes(c));

  const thead=host.querySelector('thead tr');
  const tbody=host.querySelector('tbody');
  const tfoot=host.querySelector('tfoot tr');

  const headers=['DATE'];
  if(hasAuthN && hasAuthZ){
    headers.push('AuthN Success','AuthZ Success');
  } else if(hasCount){
    headers.push('COUNT');
  }
  headers.push(...displayCols);

  headers.forEach(h=>{
    const th=document.createElement('th');
    th.textContent=h; th.title=h;
    thead.appendChild(th);
  });

  json.report.forEach(row=>{
    const tr=document.createElement('tr');
    tr.appendChild(td(buildDate(row)));

    if(hasAuthN && hasAuthZ){
      tr.appendChild(td(
        row['authn-attempts']&&row['authn-successful']
          ?((row['authn-successful']/row['authn-attempts'])*100).toFixed(2)+'%'
          :'—'
      ));
      tr.appendChild(td(
        row['authz-attempts']&&row['authz-successful']
          ?((row['authz-successful']/row['authz-attempts'])*100).toFixed(2)+'%'
          :'—'
      ));
    } else if(hasCount){
      tr.appendChild(td(row.count));
    }

    displayCols.forEach(c=>tr.appendChild(td(row[c]??'')));
    tbody.appendChild(tr);
  });

  const tdFoot=document.createElement('td');
  tdFoot.colSpan=headers.length;
  tdFoot.innerHTML='<a href="#" onclick="downloadCsv(\''+url+'\');return false;">CSV</a>';
  tfoot.appendChild(tdFoot);
}

function td(v){
  const td=document.createElement('td');
  td.textContent=v;
  return td;
}

// ORIGINAL CSV BEHAVIOR
async function downloadCsv(url){
  const token=document.querySelector('input[name=access_token]').value;
  const r=await fetch(url+'?format=csv',{headers:{Authorization:'Bearer '+token}});
  const blob=await r.blob();
  const a=document.createElement('a');
  a.href=URL.createObjectURL(blob);
  a.target='_blank';
  a.click();
  URL.revokeObjectURL(a.href);
}
</script>
</body>
</html>
EOF
