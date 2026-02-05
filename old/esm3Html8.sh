#!/bin/bash
set -e

if [ $# -ne 2 ]; then
  echo "Usage: $0 <ARG_SOFTWARE_STATEMENT> <ESM_URL>" >&2
  exit 1
fi

# ================= PROGRESS INDICATOR =================
PROGRESS_COUNT=0
SPINNER='|/-\'

progress_tick() {
  PROGRESS_COUNT=$((PROGRESS_COUNT + 1))
  local i=$((PROGRESS_COUNT % 4))
  printf "\r[%c] Crawling ESM tree… (%d)" "${SPINNER:$i:1}" "$PROGRESS_COUNT" >&2
}

progress_done() {
  printf "\r[✓] Crawl complete. %d ESM nodes processed.\n" "$PROGRESS_COUNT" >&2
}

trap progress_done EXIT

# ================= CONFIG =================
BASE_URL="https://mgmt.auth.adobe.com"
ARG_SOFTWARE_STATEMENT="$1"
START_URL="$2"

# Strip any query params from start URL (historical stable behavior)
START_PATH="${START_URL%%\?*}"

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

# ================= TREE WALK =================
process_json() {
  progress_tick
  local path="$1"

  local json_url="${path}.json?limit=1"
  local response
  response=$(curl -s -H "$AUTH_HEADER" "$json_url")

  # ---- terminal zoom detection (original semantics) ----
  local ZMLEVEL="unknown"
  case "$path" in
    */minute) ZMLEVEL="zmMIN" ;;
    */hour)   ZMLEVEL="zmHR"  ;;
    */day)    ZMLEVEL="zmDAY" ;;
    */month)  ZMLEVEL="zmMO"  ;;
    */year)   ZMLEVEL="zmYR"  ;;
  esac

  echo "<dl>"
  echo "<dt><a href=\"$path\" class=\"$ZMLEVEL\" onclick=\"runEsm(this);return false;\">$path</a></dt>"

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
      echo "$response" |
      jq -r '._links."drill-down" | if type=="array" then .[] else . end | .href'
    )
  fi
}

# ================= HTML HEADER =================
cat <<EOF
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
dl{background:var(--panel);padding:14px;border-radius:8px;margin-bottom:14px;
   box-shadow:0 1px 3px rgba(0,0,0,.06)}
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
th,td{padding:6px 10px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;
      border-bottom:1px solid #DDD;text-align:left}
thead th{position:sticky;top:0;background:var(--table-head)}
tfoot td{position:sticky;bottom:0;background:#fff}
tbody tr:nth-child(odd){background:var(--table-row)}
tbody tr:nth-child(even){background:var(--table-alt)}
tbody tr:hover{background:#F0EEE9}
.highlight {  background-color: #ff0;}
.parent-highlight { background-color: #d3f0d3;}
</style>
</head>
<body>

<input type="hidden" name="cid" value="$CID">
<input type="hidden" name="csc" value="$CSC">
<input type="hidden" name="access_token" value="$TOKEN">

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

# ================= RUN TREE =================
process_json "$START_PATH"

# ================= HTML FOOTER + JS =================
cat <<'EOF'
<script>
/* ---------- TOKEN MANAGEMENT ---------- */
function getToken(){
  return localStorage.getItem('access_token')
    || document.querySelector('input[name=access_token]').value;
}
function setToken(t){
  localStorage.setItem('access_token', t);
  document.querySelector('input[name=access_token]').value = t;
}
async function refreshToken(){
  const cid=document.querySelector('input[name=cid]').value;
  const csc=document.querySelector('input[name=csc]').value;
  const r=await fetch(
    'https://sp.auth.adobe.com/o/client/token?grant_type=client_credentials'
    +'&client_id='+encodeURIComponent(cid)
    +'&client_secret='+encodeURIComponent(csc),
    {method:'POST'}
  );
  if(!r.ok) throw new Error('Token refresh failed');
  const j=await r.json();
  setToken(j.access_token);
  return j.access_token;
}
async function fetchWithRefresh(url){
  let r=await fetch(url,{headers:{Authorization:'Bearer '+getToken()}});
  if(r.status===401){
    await refreshToken();
    r=await fetch(url,{headers:{Authorization:'Bearer '+getToken()}});
  }
  return r;
}

/* ---------- TIME WINDOW LOGIC (NEW, ADDITIVE) ---------- */
function iso(d){
  return d.toISOString().replace(/\.\d{3}Z$/,'Z');
}

function computeTimeWindow(anchor){
  const now = new Date();
  let start, end;

  if(anchor.classList.contains('zmYR')){
    start = new Date(now.getFullYear()-1,0,1);
    end   = new Date(now.getFullYear()+1,0,1);
    return { start: start.getFullYear(), end: end.getFullYear() };
  }
  if(anchor.classList.contains('zmMO')){
    start = new Date(now.getFullYear(), now.getMonth()-1, 1);
    end   = new Date(now.getFullYear(), now.getMonth()+1, 1);
    return {
      start: start.toISOString().slice(0,7),
      end:   end.toISOString().slice(0,7)
    };
  }
  if(anchor.classList.contains('zmDAY')){
    start = new Date(now);
    start.setDate(start.getDate()-1);
    return {
      start: start.toISOString().slice(0,10),
      end:   now.toISOString().slice(0,10)
    };
  }
  if(anchor.classList.contains('zmHR')){
    start = new Date(now.getTime() - 12*60*60*1000);
    return { start: iso(start), end: iso(now) };
  }
  if(anchor.classList.contains('zmMIN')){
    start = new Date(now.getTime() - 60*60*1000);
    return { start: iso(start), end: iso(now) };
  }
  return { start: iso(now), end: iso(now) };
}

function appendTimeParams(base, anchor){
  const t = computeTimeWindow(anchor);
  const sep = base.includes('?') ? '&' : '?';
  return `${base}${sep}start=${encodeURIComponent(t.start)}&end=${encodeURIComponent(t.end)}`;
}

/* ---------- UI FILTERS (UNCHANGED) ---------- */
function highlightText(){
  const input = document.getElementById("searchText");
  input.value = input.value.toLowerCase().split(" ").join("");
  const term = input.value;
  if (!term) return;

  document.querySelectorAll("dl").forEach(dl => {
    const dd = dl.querySelector(".col-list");
    if (!dd) return;

    const rawText = dd.innerText;
    const lower = rawText.toLowerCase();

    // reset state
    dd.innerHTML = rawText;
    dl.classList.remove("parent-highlight");

    if (lower.includes(term)) {
      dd.innerHTML = rawText.replace(
        new RegExp(term, "gi"),
        m => `<span class="highlight">${m}</span>`
      );
      dl.classList.add("parent-highlight");
      dl.style.display = "";
    } else {
      dl.style.display = "none";
    }
  });
}

function resetList(){
  document.querySelectorAll("dl").forEach(dl => {
    const dd = dl.querySelector(".col-list");
    if (dd) dd.innerHTML = dd.innerText;
    dl.classList.remove("parent-highlight");
    dl.style.display = "";
  });
  searchText.value = "";
  filterSelect.selectedIndex = 0;
}

function filterList(){
  const filter = document.getElementById("filterSelect").value;
  const dlElements = document.querySelectorAll("dl");

  const zoomTokens = [
    { key: "YR",  token: "/year"   },
    { key: "MO",  token: "/month"  },
    { key: "DAY", token: "/day"    },
    { key: "HR",  token: "/hour"   },
    { key: "MIN", token: "/minute" }
  ];

  dlElements.forEach(dl => {
    const anchor = dl.querySelector("a");
    if (!anchor) {
      dl.style.display = "none";
      return;
    }

    const href = anchor.href;
    let detectedZoom = null;
    let lastIndex = -1;

    zoomTokens.forEach(z => {
      const idx = href.lastIndexOf(z.token);
      if (idx > lastIndex) {
        lastIndex = idx;
        detectedZoom = z.key;
      }
    });

    if (!filter) {
      dl.style.display = "";
      return;
    }

    dl.style.display = detectedZoom === filter ? "" : "none";
  });
}

/* ---------- TABLE LOGIC (UNCHANGED + TIME-AWARE) ---------- */
const METRIC_COLUMNS=new Set([
  'authn-attempts','authn-successful','authn-pending','authn-failed',
  'clientless-tokens','clientless-failures',
  'authz-attempts','authz-successful','authz-failed','authz-rejected',
  'authz-latency','media-tokens',
  'unique-accounts','unique-sessions','count'
]);
const DATE_PARTS=['year','month','day','hour','minute'];

function buildDate(r){
  return new Date(
    r.year??1970,(r.month??1)-1,r.day??1,r.hour??0,r.minute??0
  ).toLocaleString('en-US',{
    month:'2-digit',day:'2-digit',year:'numeric',
    hour:'2-digit',minute:'2-digit'
  });
}

async function runEsm(a){
  const timedBase = appendTimeParams(a.href, a);
  const jsonUrl = timedBase + '&format=json';

  const host=a.closest('dl').querySelector('.esm-table-host');
  host.innerHTML='<div class="esm-table-wrapper"><table><thead><tr></tr></thead><tbody></tbody><tfoot><tr></tr></tfoot></table></div>';

  const r=await fetchWithRefresh(jsonUrl);
  if(!r.ok) return;
  const json=await r.json();
  if(!json.report||!json.report[0]) return;

  const row0=json.report[0];
  const hasAuthN=row0['authn-attempts']!=null&&row0['authn-successful']!=null;
  const hasAuthZ=row0['authz-attempts']!=null&&row0['authz-successful']!=null;
  const hasCount=row0['count']!=null;

  const displayCols=Object.keys(row0)
    .filter(c=>!METRIC_COLUMNS.has(c)&&!DATE_PARTS.includes(c));

  const thead=host.querySelector('thead tr');
  const tbody=host.querySelector('tbody');
  const tfoot=host.querySelector('tfoot tr');

  const headers=['DATE'];
  if(hasAuthN) headers.push('AuthN Success');
  if(hasAuthZ) headers.push('AuthZ Success');
  if(!hasAuthN&&!hasAuthZ&&hasCount) headers.push('COUNT');
  headers.push(...displayCols);

  headers.forEach(h=>{
    const th=document.createElement('th');
    th.textContent=h;
    th.title=h;
    thead.appendChild(th);
  });

  json.report.forEach(r=>{
    const tr=document.createElement('tr');
    tr.appendChild(td(buildDate(r)));
    if(hasAuthN){
      tr.appendChild(td(
        r['authn-attempts']
          ?((r['authn-successful']/r['authn-attempts'])*100).toFixed(2)+'%'
          :'—'));
    }
    if(hasAuthZ){
      tr.appendChild(td(
        r['authz-attempts']
          ?((r['authz-successful']/r['authz-attempts'])*100).toFixed(2)+'%'
          :'—'));
    }
    if(!hasAuthN&&!hasAuthZ&&hasCount){
      tr.appendChild(td(r.count));
    }
    displayCols.forEach(c=>tr.appendChild(td(r[c]??'')));
    tbody.appendChild(tr);
  });

  const ftd=document.createElement('td');
  ftd.colSpan=headers.length;
  ftd.innerHTML='<a href="#" onclick="downloadCsv(this,\''+a.href+'\');return false;">CSV</a>';
  tfoot.appendChild(ftd);
}

function td(v){
  const td=document.createElement('td');
  td.textContent=v;
  td.title=v;
  return td;
}

async function downloadCsv(link, base){
  const a = link.closest('dl').querySelector('a');
  const csvUrl = appendTimeParams(base, a) + '&format=csv';
  const r=await fetchWithRefresh(csvUrl);
  const b=await r.blob();
  const a2=document.createElement('a');
  a2.href=URL.createObjectURL(b);
  a2.target='_blank';
  a2.click();
  URL.revokeObjectURL(a2.href);
}
</script>
</body>
</html>
EOF
