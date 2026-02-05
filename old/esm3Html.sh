#!/bin/bash
# Ensure required arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <ARG_SOFTWARE_STATEMENT> <ESM_URL>"
    exit 1
fi

# Prefix for all _links.drill_down.href
base_url="https://mgmt.auth.adobe.com"
# limit=1 for faster ESM calls, column and drill-down checks
url_extras=".json?limit=1"

ARG_SOFTWARE_STATEMENT="$1"
ESM_URL="$2"

# debug
echo "<!--  ARG_SOFTWARE_STATEMENT: $ARG_SOFTWARE_STATEMENT"
echo "ESM_URL: $ESM_URL -->"

# REQUEST 1: Register the client
# echo "Making REQUEST 1 to register client..."
RESPONSE1=$(curl -s 'https://sp.auth.adobe.com/o/client/register' \
  -X 'POST' \
  -H 'Content-Type: application/json' \
  --data-raw "{\"software_statement\":\"$ARG_SOFTWARE_STATEMENT\"}")

# Extract client_id and client_secret from RESPONSE 1
RESPONSE1_CLIENT_ID=$(echo "$RESPONSE1" | jq -r '.client_id')
RESPONSE1_CLIENT_SECRET=$(echo "$RESPONSE1" | jq -r '.client_secret')

# confirm client_id and client_secret values were captured
if [ -z "$RESPONSE1_CLIENT_ID" ] || [ -z "$RESPONSE1_CLIENT_SECRET" ]; then
    echo "Failed to extract client_id or client_secret from RESPONSE 1."
    exit 1
fi

# debug
echo "<!--  RESPONSE1_CLIENT_ID: $RESPONSE1_CLIENT_ID"
echo "RESPONSE1_CLIENT_SECRET: $RESPONSE1_CLIENT_SECRET -->"

# REQUEST 2: Fetch the access token
RESPONSE2=$(curl -s "https://sp.auth.adobe.com/o/client/token?grant_type=client_credentials&client_id=$RESPONSE1_CLIENT_ID&client_secret=$RESPONSE1_CLIENT_SECRET" \
    -X 'POST' \
    -H 'Content-Type: application/json' )

# Extract access_token from RESPONSE 2
RESPONSE2_ACCESS_TOKEN=$(echo "$RESPONSE2" | jq -r '.access_token')

# Confirm access token
if [ -z "$RESPONSE2_ACCESS_TOKEN" ]; then
    echo "Failed to extract access_token from RESPONSE 2."
    exit 1
fi

# debug
echo "<!--  RESPONSE2_ACCESS_TOKEN: $RESPONSE2_ACCESS_TOKEN -->"

# Construct the Authorization header
auth_header="Authorization: Bearer $RESPONSE2_ACCESS_TOKEN"

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

            # NOTE: V3 ESM HREFs shouldn't need any fixing
            new_url=$base_url$link$url_extras

            # Recursively call the process_json function with the new URL
            (process_json $new_url)&

            # Wait for all background processes to finish before continuing
            wait

          done

    fi

}


# spit out top of HTML HEADER, H1, FINDER FORM
echo "<!DOCTYPE html><html lang=\"en\"><head><title>ESM3 FINDIT click list</title><meta charset=\"UTF-8\" /><meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" /><style>a:hover{color:#99ff99;}.zmMIN{color:#6591c4;}.zmHR{color:#1d79d3;}.zmDAY{color:#0aadcf;}.zmMO{color:#c11ebe;}.zmYR{color:#fff;}body{color:gold;background-color:#b1a1c4;font-family:Arial,sans-serif;margin:20px;}dl{background-color:#060606;padding:15px;border-radius:5px;}dt{font-weight:700;margin-top:10px;}dd{margin-left:20px;margin-bottom:10px;}.highlight{background-color:#00f;}.parent-highlight{background-color:#2c0f2c;}.hidden{display:none;}.search-container{margin:20px 0;}input{width:300px;padding:10px;font-size:16px;}select{width:100px;padding:10px;font-size:16px;}button{padding:10px 20px;font-size:16px;cursor:pointer;}.reset-button{background-color:#0bbcc9;color:#000;}</style></head><body><!-- Finder Form --><div class=\"search-container\"><select id=\"filterSelect\" onchange=\"filterList()\"><option value=\"\"></option><option value=\"YR\">YR</option><option value=\"MO\">MO</option><option value=\"DAY\">DAY</option><option value=\"HR\">HR</option><option value=\"MIN\">MIN</option></select><input type=\"text\" id=\"searchText\" placeholder=\"ESM Column search...\"><button onclick=\"highlightText()\">FIND IT</button><button class=\"reset-button\" onclick=\"resetList()\">RESET</button></div>"
echo "<!-- OPEN DLs -->"
# SAUSAGE MAKER
# USAGE : pass in full ESM url without slash or trailing queryString
# ./esm3Html.sh 'eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJjODkyNjg5Ni0wYzI4LTQxODItOTc5Mi1hNGI0ZDdjMzUwNjQiLCJuYmYiOjE3MzE5NDc4NzUsImlzcyI6ImF1dGguYWRvYmUuY29tIiwiaWF0IjoxNzMxOTQ3ODc1fQ.KaMchis9kjwnIlsKJuCDWXyBhJt3oRuD1CnydxOw9atda9k-YKRYDUEBiod1yK9ZH9YptaRQRCNlZEOWexEU66uSHI8Qa9kBe0qH64zRuvtRQvU9LiPBOPUQNDnQGlkRvDpHc0xnOQjOm8QnvwUSLux2QaYZJL0Fd5vLTn1Xhg87AQfaFCiKFYjJLQ6iVBgVa5anbBNAJmLbwxwRV9aQZCsbHw6BQAH8HYw0H0hMF4OpxFS-7-8-r0bbaG4qIQZdUdBmKdyEXnIpdx9Ggqzc3yj2po5y05VR4LhDoYNv517L1bPx8u4mvmZYGGVRDYyE1foXhJ8WPXYPBKOmA4p9qA', 'https://mgmt.auth.adobe.com/esm/v3/media-company/year' > esm3fndr.html
process_json $ESM_URL$url_extras
# CLOSE THE LIST
echo "</dl>"
echo "<!-- END DLs -->"
# INJECT FINDR FORM SCRIPT AND CLOSE THE SHOW
echo "<script>const BASE_URL=\"https://mgmt.auth.adobe.com/esm/v3/media-company/\";function highlightText(){var e=document.getElementById(\"searchText\");e.value=e.value.toLowerCase().split(\" \").join(\"\");var t=e.value;if(null==t||\"\"==t)return;console.log(\"SEARCHING FOR '\"+t+\"'\");document.querySelectorAll(\"dl\").forEach(function(e){if(getComputedStyle(e).display!==\"none\"){var l=e.querySelector(\"dd\");var s=l.innerText.toLowerCase();l.innerHTML=s;e.classList.remove(\"parent-highlight\");l.querySelectorAll(\".highlight\").forEach(function(e){e.classList.remove(\"highlight\")});if(s.includes(t)){l.innerHTML=l.innerHTML.replace(new RegExp(t,\"gi\"),function(e){return'<span class=\"highlight\">'+e+\"</span>\"});e.classList.add(\"parent-highlight\");e.style.display=\"\"}else{e.classList.remove(\"parent-highlight\");e.style.display=\"none\"}}})}function resetList(){document.querySelectorAll(\"dl\").forEach(function(e){if(getComputedStyle(e).display!==\"none\"){var t=e.querySelector(\"dd\");t.innerHTML=t.innerText;e.classList.remove(\"parent-highlight\");e.style.display=\"\"}});document.getElementById(\"searchText\").value=\"\";var _menu=document.getElementById(\"filterSelect\");_menu.selectedIndex=0;_menu.dispatchEvent(new Event(\"change\"));}function filterList(){const filter=document.getElementById(\"filterSelect\").value;const dlElements=document.querySelectorAll(\"dl\");dlElements.forEach((dl)=>{const anchor=dl.querySelector(\"a\");if(anchor){const anchorClass=anchor.className;const matchesFilter=(()=>{switch(filter){case \"YR\":return anchorClass===\"zmYR\";case \"MO\":return anchorClass===\"zmMO\";case \"DAY\":return anchorClass===\"zmDAY\";case \"HR\":return anchorClass===\"zmHR\";case \"MIN\":return anchorClass===\"zmMIN\";default:return!0}})();dl.style.display=matchesFilter?\"\":\"none\"}else{dl.style.display=\"none\"}})}</script>"
echo "</body></html>"