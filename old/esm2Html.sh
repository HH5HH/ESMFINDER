#!/bin/bash
# Prefix for all _links.drill_down.href
base_url="https://mgmt.auth.adobe.com"
# limit=1 for faster ESM calls, column and drill-down checks
url_extras=".json?limit=1"
# ESM deep-link case examples
# 0 - year/month/day/dc
#   ./crawlESM2.sh "https://mgmt.auth.adobe.com/esm/v2.1/media-company/year/month/dc"
# 1 - year
#   ./crawlESM2.sh "https://mgmt.auth.adobe.com/esm/v2.1/media-company/year"
# many - year/month/day
#   ./crawlESM2.sh "https://mgmt.auth.adobe.com/esm/v2.1/media-company/year/month/day"

# TODO: figure out smooth way to APIGEE or DCR with SH
#   -> PORT TO V3
#   -> include SS in usage call
#   -> script "SS" "ESM.URL" > callThisSomethingUseful.html
auth_header="Authorization: Bearer zRmLVwnIvBG5xWMrCfGHtbvA6Pb9"    # <-- NOTE: if your use the wrong access token, this script will bonk

# Function to process the drill-down _links and get the next JSON
process_json() {
    # grab incoming url para
    local url=$1

    # Fetch the initial JSON response
    response=$(curl -s -X GET -H "$auth_header" "$url")

    # TODO: figure out easy formatting for XL or other ESM full map ingest
    # Start with SITEMAP.XML
    echo "<dl>"
    
    # REMOVE url_extras so only end url ends up in visible clickable HTML
    url_clean=${url//$url_extras/}
    
    # echo "<dt><a href='$url_clean' target='_blank'>$url_clean</a></dt>"
    # ZM-LEVEL UPDATE
    # Determine ZMLEVEL based on $url_clean
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
    ZMLEVEL="unknown" # Default or fallback value
fi

# Use ZMLEVEL in your echo statement
echo "<dt><a href='$url_clean' target='_blank' class='$ZMLEVEL'>$url_clean</a></dt>"


    # Check if the response is valid JSON
    if echo "$response" | jq -e . >/dev/null 2>&1; then
    # if echo "$response" | jq empty > /dev/null 2>&1; then
        # Extract column list if response is valid JSON
        # grab column list if JSON was returned
        COLS=$(echo "$response" | jq -r '.report[0] | keys[]')
    else
        # Handle invalid JSON or error message
        # echo "<p style='color:red'><tt><code>$response</code></tt></p>"
        COLS="<p style='color:red'><code>$response</code></p>"
    fi

    echo "<dd>$COLS</dd>"

    # GOT drill-downs ? 
    if [[ $response == *"drill-down"* ]]; then

        # JUST get the drill-down.hrefs whether it's 1 looking like {} or Many in [{}] form
        links1=$(echo "$response" | jq -r '._links."drill-down" | if type == "array" then map(.href) else [.href] end | .[]')

         for link in $links1; do
 
            # close DL before calling new URL
            echo "</dl>"
            # ESM v2 url fix: Modify the URL to use '/v2.1' instead of '/v2'
            # Also jam it all together 
            new_url=$base_url$(echo $link | sed 's|/v2/|/v2.1/|')$url_extras

            # Recursively call the process_json function with the new URL
            (process_json $new_url)&

            # Wait for all background processes to finish before continuing
            wait

          done

    fi

}

# spit out top of HTML HEADER, H1, FINDER FORM
#echo "<!DOCTYPE html><html lang=\"en\"><head><title>ESM2.1 FINDIT click list</title><meta charset=\"UTF-8\" /><meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" /><style>a:hover{color:royalblue}.zmMIN{color:darkred;} .zmHR{color:darkorange;} .zmDAY{color:darkgoldenrod;} .zmMO{color:darkcyan;} .zmYR{color:navy;} body{font-family:Arial,sans-serif;margin:20px}dl{background-color:#f9f9f9;padding:15px;border-radius:5px}dt{font-weight:700;margin-top:10px}dd{margin-left:20px;margin-bottom:10px}.highlight{background-color:#ff0}.parent-highlight{background-color:#d3f0d3}.hidden{display:none}.search-container{margin:20px 0}input{width:300px;padding:10px;font-size:16px}select{width:100px;padding:10px;font-size:16px}button{padding:10px 20px;font-size:16px;cursor:pointer}.reset-button{background-color:#f44336;color:#fff}</style></head><body><!-- Finder Form --><div class=\"search-container\"><button class=\"reset-button\" onclick=\"resetList()\">RESET</button><!-- New SELECT picker --><select id=\"filterSelect\" onchange=\"filterList()\"><option value=\"\"></option><option value=\"YR\">YR</option><option value=\"MO\">MO</option><option value=\"DAY\">DAY</option><option value=\"HR\">HR</option><option value=\"MIN\">MIN</option></select><input type=\"text\" id=\"searchText\" placeholder=\"ESM Column search...\"><button onclick=\"highlightText()\">FIND IT</button></div>"
echo "<!DOCTYPE html><html lang=\"en\"><head><title>ESM2.1 FINDIT click list</title><meta charset=\"UTF-8\" /><meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" /><style>a:hover { color: yellowgreen; } .zmMIN { color: #9a6e3b; } .zmHR { color: #e2862c; } .zmDAY { color: #f52f30; } .zmMO { color: #3ee841; } .zmYR { color: #000000; } body{background-color:slategray; font-family:Arial,sans-serif;margin:20px}dl{background-color:#f9f9f9;padding:15px;border-radius:5px}dt{font-weight:700;margin-top:10px}dd{margin-left:20px;margin-bottom:10px}.highlight{background-color:#ff0}.parent-highlight{background-color:#d3f0d3}.hidden{display:none}.search-container{margin:20px 0}input{width:300px;padding:10px;font-size:16px}select{width:100px;padding:10px;font-size:16px}button{padding:10px 20px;font-size:16px;cursor:pointer}.reset-button{background-color:#f44336;color:#fff}</style></head><body><!-- Finder Form --><div class=\"search-container\"><select id=\"filterSelect\" onchange=\"filterList()\"><option value=\"\"></option><option value=\"YR\">YR</option><option value=\"MO\">MO</option><option value=\"DAY\">DAY</option><option value=\"HR\">HR</option><option value=\"MIN\">MIN</option></select><input type=\"text\" id=\"searchText\" placeholder=\"ESM Column search...\"><button onclick=\"highlightText()\">FIND IT</button><button class=\"reset-button\" onclick=\"resetList()\">RESET</button></div>"
echo "<!-- OPEN DLs -->"
# SAUSAGE MAKER
# USAGE : pass in full ESM url without slash or trailing queryString
# ./esm2Html.sh "https://mgmt.auth.adobe.com/esm/v2.1/media-company/year/month/day" > esmtree.html 
process_json $1$url_extras
# CLOSE THE LIST
echo "</dl>"
echo "<!-- END DLs -->"
# INJECT FINDR FORM SCRIPT AND CLOSE THE SHOW
# echo "<script>const BASE_URL=\"https://mgmt.auth.adobe.com/esm/v2.1/media-company/\";function highlightText(){var e=document.getElementById(\"searchText\");e.value=e.value.toLowerCase().split(\" \").join(\"\");var t=e.value;if(null==t||\"\"==t)return;console.log(\"SEARCHING FOR '\"+t+\"'\");document.querySelectorAll(\"dl\").forEach(function(e){if(getComputedStyle(e).display!==\"none\"){var l=e.querySelector(\"dd\");var s=l.innerText.toLowerCase();l.innerHTML=s;e.classList.remove(\"parent-highlight\");l.querySelectorAll(\".highlight\").forEach(function(e){e.classList.remove(\"highlight\")});if(s.includes(t)){l.innerHTML=l.innerHTML.replace(new RegExp(t,\"gi\"),function(e){return'<span class=\"highlight\">'+e+\"</span>\"});e.classList.add(\"parent-highlight\");e.style.display=\"\"}else{e.classList.remove(\"parent-highlight\");e.style.display=\"none\"}}})}function resetList(){document.querySelectorAll(\"dl\").forEach(function(e){if(getComputedStyle(e).display!==\"none\"){var t=e.querySelector(\"dd\");t.innerHTML=t.innerText;e.classList.remove(\"parent-highlight\");e.style.display=\"\"}});document.getElementById(\"searchText\").value=\"\";var _menu=document.getElementById(\"filterSelect\");_menu.selectedIndex=0;_menu.dispatchEvent(new Event(\"change\"));}function filterList(){const filter=document.getElementById(\"filterSelect\").value;const dlElements=document.querySelectorAll(\"dl\");dlElements.forEach((dl)=>{const anchor=dl.querySelector(\"a\");if(anchor){const anchorClass=anchor.className;const matchesFilter=(()=>{switch(filter){case \"YR\":return anchorClass===\"zmYR\";case \"MO\":return anchorClass===\"zmMO\";case \"DAY\":return anchorClass===\"zmDAY\";case \"HR\":return anchorClass===\"zmHR\";case \"MIN\":return anchorClass===\"zmMIN\";default:return!0}})();dl.style.display=matchesFilter?\"\":\"none\"}else{dl.style.display=\"none\"}})}</script>"
echo "<script>const BASE_URL=\"https://mgmt.auth.adobe.com/esm/v2.1/media-company/\";function highlightText(){var e=document.getElementById(\"searchText\");e.value=e.value.toLowerCase().split(\" \").join(\"\");var t=e.value;if(null==t||\"\"==t)return;console.log(\"SEARCHING FOR '\"+t+\"'\");document.querySelectorAll(\"dl\").forEach(function(e){if(getComputedStyle(e).display!==\"none\"){var l=e.querySelector(\"dd\");var s=l.innerText.toLowerCase();l.innerHTML=s;e.classList.remove(\"parent-highlight\");l.querySelectorAll(\".highlight\").forEach(function(e){e.classList.remove(\"highlight\")});if(s.includes(t)){l.innerHTML=l.innerHTML.replace(new RegExp(t,\"gi\"),function(e){return'<span class=\"highlight\">'+e+\"</span>\"});e.classList.add(\"parent-highlight\");e.style.display=\"\"}else{e.classList.remove(\"parent-highlight\");e.style.display=\"none\"}}})}function resetList(){document.querySelectorAll(\"dl\").forEach(function(e){if(getComputedStyle(e).display!==\"none\"){var t=e.querySelector(\"dd\");t.innerHTML=t.innerText;e.classList.remove(\"parent-highlight\");e.style.display=\"\"}});document.getElementById(\"searchText\").value=\"\";var _menu=document.getElementById(\"filterSelect\");_menu.selectedIndex=0;_menu.dispatchEvent(new Event(\"change\"));}function filterList(){const filter=document.getElementById(\"filterSelect\").value;const dlElements=document.querySelectorAll(\"dl\");dlElements.forEach((dl)=>{const anchor=dl.querySelector(\"a\");if(anchor){const anchorClass=anchor.className;const matchesFilter=(()=>{switch(filter){case \"YR\":return anchorClass===\"zmYR\";case \"MO\":return anchorClass===\"zmMO\";case \"DAY\":return anchorClass===\"zmDAY\";case \"HR\":return anchorClass===\"zmHR\";case \"MIN\":return anchorClass===\"zmMIN\";default:return!0}})();dl.style.display=matchesFilter?\"\":\"none\"}else{dl.style.display=\"none\"}})}</script>"
echo "</body></html>"