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

echo "<!--  ARG_SOFTWARE_STATEMENT: $ARG_SOFTWARE_STATEMENT"
echo "ESM_URL: $ESM_URL -->"

RESPONSE1=$(curl -s 'https://sp.auth.adobe.com/o/client/register' -X POST -H 'Content-Type: application/json' --data-raw "{\"software_statement\":\"$ARG_SOFTWARE_STATEMENT\"}")
CID=$(echo "$RESPONSE1" | jq -r '.client_id')
CSECRET=$(echo "$RESPONSE1" | jq -r '.client_secret')
[ -z "$CID" -o -z "$CSECRET" ] && exit 1

RESPONSE2=$(curl -s "https://sp.auth.adobe.com/o/client/token?grant_type=client_credentials&client_id=$CID&client_secret=$CSECRET" -X POST -H 'Content-Type: application/json')
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

    echo "<dt><input type='radio' name='url' value='$url_clean' /><a href='$url_clean' target='_blank' class='$Z'>$url_clean</a></dt>"

    if echo "$response" | jq -e . >/dev/null 2>&1; then
        COLS=$(echo "$response" | jq -r '.report[0] | keys[]')
    else
        COLS="<p style='color:red'><code>$response</code></p>"
    fi

    echo "<dd>$COLS</dd>"

    if [[ $response == *\"drill-down\"* ]]; then
        for link in $(echo "$response" | jq -r '._links."drill-down" | if type=="array" then map(.href) else [.href] end | .[]'); do
            echo "</dl>"
            process_json "$base_url$link$url_extras"
        done
    fi
}

echo "<!DOCTYPE html><html lang=\"en\"><head><title>ESM3 FINDIT click list</title><meta charset=\"UTF-8\" /><meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" /><style>a:hover{color:#99ff99;}.zmMIN{color:#6591c4;}.zmHR{color:#1d79d3;}.zmDAY{color:#0aadcf;}.zmMO{color:#c11ebe;}.zmYR{color:#fff;}body{color:gold;background-color:#b1a1c4;font-family:Arial,sans-serif;margin:20px;}dl{background-color:#060606;padding:15px;border-radius:5px;}dt{font-weight:700;margin-top:10px;}dd{margin-left:20px;margin-bottom:10px;}.highlight{background-color:#00f;}.parent-highlight{background-color:#2c0f2c;}.hidden{display:none;}.search-container{margin:20px 0;}input{width:300px;padding:10px;font-size:16px;}select{width:100px;padding:10px;font-size:16px;}button{padding:10px 20px;font-size:16px;cursor:pointer;}.reset-button{background-color:#0bbcc9;color:#000;}</style></head><body><!-- Finder Form --><div class=\"search-container\"><select id=\"filterSelect\" onchange=\"filterList()\"><option value=\"\"></option><option value=\"YR\">YR</option><option value=\"MO\">MO</option><option value=\"DAY\">DAY</option><option value=\"HR\">HR</option><option value=\"MIN\">MIN</option></select><input type=\"text\" id=\"searchText\" placeholder=\"ESM Column search...\"><button onclick=\"highlightText()\">FIND IT</button><button class=\"reset-button\" onclick=\"resetList()\">RESET</button></div>"

process_json "$ESM_URL$url_extras"

echo "</dl><button id=\"runBtn\" disabled>RUN IT</button>"

echo "<script>const BASE_URL=\"https://mgmt.auth.adobe.com/esm/v3/media-company/\";function highlightText(){var e=document.getElementById(\"searchText\");e.value=e.value.toLowerCase().split(\" \").join(\"\");var t=e.value;if(null==t||\"\"==t)return;document.querySelectorAll(\"dl\").forEach(function(e){if(getComputedStyle(e).display!==\"none\"){var l=e.querySelector(\"dd\");var s=l.innerText.toLowerCase();l.innerHTML=s;e.classList.remove(\"parent-highlight\");l.querySelectorAll(\".highlight\").forEach(function(e){e.classList.remove(\"highlight\")});if(s.includes(t)){l.innerHTML=l.innerHTML.replace(new RegExp(t,\"gi\"),function(e){return'<span class=\"highlight\">'+e+\"</span>\"});e.classList.add(\"parent-highlight\");e.style.display=\"\"}else{e.classList.remove(\"parent-highlight\");e.style.display=\"none\"}}})}function resetList(){document.querySelectorAll(\"dl\").forEach(function(e){if(getComputedStyle(e).display!==\"none\"){var t=e.querySelector(\"dd\");t.innerHTML=t.innerText;e.classList.remove(\"parent-highlight\");e.style.display=\"\"}});document.getElementById(\"searchText\").value=\"\";var _menu=document.getElementById(\"filterSelect\");_menu.selectedIndex=0;_menu.dispatchEvent(new Event(\"change\"));}function filterList(){const filter=document.getElementById(\"filterSelect\").value;const dlElements=document.querySelectorAll(\"dl\");dlElements.forEach((dl)=>{const anchor=dl.querySelector(\"a\");if(anchor){const anchorClass=anchor.className;const matchesFilter=(()=>{switch(filter){case \"YR\":return anchorClass===\"zmYR\";case \"MO\":return anchorClass===\"zmMO\";case \"DAY\":return anchorClass===\"zmDAY\";case \"HR\":return anchorClass===\"zmHR\";case \"MIN\":return anchorClass===\"zmMIN\";default:return!0}})();dl.style.display=matchesFilter?\"\":\"none\"}else{dl.style.display=\"none\"}})}document.addEventListener(\"DOMContentLoaded\",()=>{const b=document.getElementById(\"runBtn\");document.querySelectorAll(\"input[type=radio][name=url]\").forEach(r=>r.addEventListener(\"change\",()=>b.disabled=!1));b.addEventListener(\"click\",async()=>{const s=document.querySelector(\"input[name=url]:checked\");if(!s)return;const t=document.querySelector(\"input[name=access_token]\").value,u=s.value,d=s.closest(\"dt\");d.querySelectorAll(\".esm-response\").forEach(e=>e.remove());const v=document.createElement(\"div\");v.className=\"esm-response\",v.style.cssText=\"max-height:300px;overflow:auto;background:#111;color:#9ff;border:1px solid #444;padding:10px;margin-top:8px;font-family:monospace;font-size:12px\",v.textContent=\"Loading…\",d.appendChild(v);try{const r=await fetch(u,{headers:{Authorization:\"Bearer \"+t}});if(!r.ok)throw Error(r.status);v.textContent=JSON.stringify(await r.json(),null,2)}catch(e){v.textContent=\"ERROR: \"+e.message,v.style.color=\"#f66\"}})});</script>"

echo "</body></html>"
