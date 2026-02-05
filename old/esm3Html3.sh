#!/bin/bash
# Ensure required arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <ARG_SOFTWARE_STATEMENT> <ESM_URL>"
    exit 1
fi

base_url="https://mgmt.auth.adobe.com"
url_extras=".json?limit=1"

ARG_SOFTWARE_STATEMENT="$1"
ESM_URL="$2"

echo "<!-- ARG_SOFTWARE_STATEMENT: $ARG_SOFTWARE_STATEMENT"
echo "ESM_URL: $ESM_URL -->"

RESPONSE1=$(curl -s 'https://sp.auth.adobe.com/o/client/register' \
  -X POST -H 'Content-Type: application/json' \
  --data-raw "{\"software_statement\":\"$ARG_SOFTWARE_STATEMENT\"}")

CID=$(echo "$RESPONSE1" | jq -r '.client_id')
CSECRET=$(echo "$RESPONSE1" | jq -r '.client_secret')
[ -z "$CID" -o -z "$CSECRET" ] && exit 1

RESPONSE2=$(curl -s \
  "https://sp.auth.adobe.com/o/client/token?grant_type=client_credentials&client_id=$CID&client_secret=$CSECRET" \
  -X POST -H 'Content-Type: application/json')

TOKEN=$(echo "$RESPONSE2" | jq -r '.access_token')
[ -z "$TOKEN" ] && exit 1

echo "<input type='hidden' name='access_token' value='$TOKEN' />"
auth_header="Authorization: Bearer $TOKEN"

process_json() {
    local url=$1
    response=$(curl -s -H "$auth_header" "$url")
    echo "<dl>"
    url_clean=${url//$url_extras/}

    if [[ "$url_clean" == *"/minute"* ]]; then Z=zmMIN
    elif [[ "$url_clean" == *"/hour"* ]]; then Z=zmHR
    elif [[ "$url_clean" == *"/day"* ]]; then Z=zmDAY
    elif [[ "$url_clean" == *"/month"* ]]; then Z=zmMO
    elif [[ "$url_clean" == *"/year"* ]]; then Z=zmYR
    else Z=unknown
    fi

    echo "<dt>
<a href=\"$url_clean\" class=\"$Z\" onclick=\"runEsm(this); return false;\">$url_clean</a>
</dt>"

    if echo "$response" | jq -e . >/dev/null 2>&1; then
        COLS=$(echo "$response" | jq -r '.report[0] | keys[]')
    else
        COLS="<p style='color:red'><code>$response</code></p>"
    fi

    echo "<dd>$COLS</dd>"

    if [[ $response == *\"drill-down\"* ]]; then
        for link in $(echo "$response" | jq -r \
          '._links.\"drill-down\" | if type==\"array\" then map(.href) else [.href] end | .[]'); do
            echo "</dl>"
            process_json \"$base_url$link$url_extras\"
        done
    fi
}

echo "<!DOCTYPE html><html lang=\"en\"><head>
<title>ESM3 FINDIT click list</title>
<meta charset=\"UTF-8\" />
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />
<style>
a:hover{color:#99ff99;cursor:pointer;}
.zmMIN{color:#6591c4;}
.zmHR{color:#1d79d3;}
.zmDAY{color:#0aadcf;}
.zmMO{color:#c11ebe;}
.zmYR{color:#fff;}
body{color:gold;background-color:#b1a1c4;font-family:Arial,sans-serif;margin:20px;}
dl{background-color:#060606;padding:15px;border-radius:5px;}
dt{font-weight:700;margin-top:10px;}
dd{margin-left:20px;margin-bottom:10px;}
.highlight{background-color:#00f;}
.parent-highlight{background-color:#2c0f2c;}
.search-container{margin:20px 0;}
input{width:300px;padding:10px;font-size:16px;}
select{width:100px;padding:10px;font-size:16px;}
button{padding:10px 20px;font-size:16px;cursor:pointer;}
.reset-button{background-color:#0bbcc9;color:#000;}

/* teal report table */
table{border-collapse:collapse;width:100%;color:#9ff;}
th,td{padding:4px;border-bottom:1px solid #355;white-space:nowrap;}
th{background:#122;color:#6ff;border-bottom:1px solid #4aa;text-align:left;}
</style>
</head><body>"

echo "<div class=\"search-container\">
<select id=\"filterSelect\" onchange=\"filterList()\">
<option value=\"\"></option>
<option value=\"YR\">YR</option>
<option value=\"MO\">MO</option>
<option value=\"DAY\">DAY</option>
<option value=\"HR\">HR</option>
<option value=\"MIN\">MIN</option>
</select>
<input type=\"text\" id=\"searchText\" placeholder=\"ESM Column search...\">
<button onclick=\"highlightText()\">FIND IT</button>
<button class=\"reset-button\" onclick=\"resetList()\">RESET</button>
</div>"

process_json "$ESM_URL$url_extras"

echo "<script>
function highlightText(){
  var e=document.getElementById(\"searchText\");
  e.value=e.value.toLowerCase().split(\" \").join(\"\");
  var t=e.value;if(!t)return;
  document.querySelectorAll(\"dl\").forEach(function(d){
    if(getComputedStyle(d).display!==\"none\"){
      var dd=d.querySelector(\"dd\");
      var s=dd.innerText.toLowerCase();
      dd.innerHTML=s;
      d.classList.remove(\"parent-highlight\");
      if(s.includes(t)){
        dd.innerHTML=dd.innerHTML.replace(new RegExp(t,\"gi\"),m=>'<span class=\"highlight\">'+m+'</span>');
        d.classList.add(\"parent-highlight\");
        d.style.display=\"\";
      }else d.style.display=\"none\";
    }
  });
}

function resetList(){
  document.querySelectorAll(\"dl\").forEach(d=>{
    d.style.display=\"\";
    d.classList.remove(\"parent-highlight\");
    var dd=d.querySelector(\"dd\");
    dd.innerHTML=dd.innerText;
  });
  document.getElementById(\"searchText\").value=\"\";
  var m=document.getElementById(\"filterSelect\");
  m.selectedIndex=0;
  m.dispatchEvent(new Event(\"change\"));
}

function filterList(){
  const f=document.getElementById(\"filterSelect\").value;
  document.querySelectorAll(\"dl\").forEach(dl=>{
    const a=dl.querySelector(\"a\");
    if(!a){dl.style.display=\"none\";return;}
    dl.style.display=(!f||a.className===\"zm\"+f)?\"\":\"none\";
  });
}

async function runEsm(anchor){
  const token=document.querySelector(\"input[name=access_token]\").value;
  const url=anchor.getAttribute(\"href\");
  const dt=anchor.closest(\"dt\");

  dt.querySelectorAll(\".esm-response\").forEach(e=>e.remove());

  const box=document.createElement(\"div\");
  box.className=\"esm-response\";
  box.style.cssText=\"max-height:300px;overflow:auto;background:#111;color:#9ff;border:1px solid #355;padding:10px;margin-top:8px;font-size:12px\";
  box.textContent=\"Loading…\";
  dt.appendChild(box);

  try{
    const r=await fetch(url,{headers:{Authorization:\"Bearer \"+token}});
    if(!r.ok)throw Error(r.status);
    const json=await r.json();

    if(!Array.isArray(json.report)||!json.report.length){
      box.textContent=\"No report data found.\";return;
    }

    const table=document.createElement(\"table\");
    const thead=document.createElement(\"thead\");
    const tbody=document.createElement(\"tbody\");
    const cols=Object.keys(json.report[0]);

    const hr=document.createElement(\"tr\");
    cols.forEach(c=>{const th=document.createElement(\"th\");th.textContent=c;hr.appendChild(th);});
    thead.appendChild(hr);

    json.report.forEach(row=>{
      const tr=document.createElement(\"tr\");
      cols.forEach(c=>{const td=document.createElement(\"td\");td.textContent=row[c]??\"\";tr.appendChild(td);});
      tbody.appendChild(tr);
    });

    table.appendChild(thead);
    table.appendChild(tbody);
    box.innerHTML=\"\";
    box.appendChild(table);

  }catch(e){
    box.textContent=\"ERROR: \"+e.message;
    box.style.color=\"#f66\";
  }
}
</script>"

echo "</body></html>"
