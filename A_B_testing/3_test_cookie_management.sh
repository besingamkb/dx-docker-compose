#!/bin/bash
# 3_test_cookie_management.sh - Verifies DXSRVID cookie attributes (HttpOnly)

OUTPUT_FILE="results/3_cookie_management_results.txt"
JSON_FILE="results/3_cookie_management_results.json"
> "$OUTPUT_FILE"
echo "{" > "$JSON_FILE"

echo "==================================================" | tee -a "$OUTPUT_FILE"
echo " TEST 3: COOKIE MANAGEMENT" | tee -a "$OUTPUT_FILE"
echo "==================================================" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

test_cookie() {
    local proxy_name=$1
    local port=$2
    local is_last=$3

    echo "Testing Cookie on $proxy_name (Port $port)..." | tee -a "$OUTPUT_FILE"
    
    headers=$(curl -s -I "http://localhost:$port/wps/portal")
    cookie_line=$(echo "$headers" | grep -i "Set-Cookie: DXSRVID")
    
    local has_cookie="false"
    local has_httponly="false"
    local has_path="false"
    local cookie_val=""
    
    if [ -z "$cookie_line" ]; then
        echo "  [FAIL] No DXSRVID cookie found!" | tee -a "$OUTPUT_FILE"
    else
        has_cookie="true"
        cookie_val=$(echo "$cookie_line" | tr -d '\r')
        echo "  Found Cookie: $cookie_val" | tee -a "$OUTPUT_FILE"
        
        if echo "$cookie_line" | grep -iq "HttpOnly"; then
            echo "  [PASS] HttpOnly flag is present." | tee -a "$OUTPUT_FILE"
            has_httponly="true"
        else
            echo "  [FAIL] HttpOnly flag is MISSING!" | tee -a "$OUTPUT_FILE"
        fi
        
        if echo "$cookie_line" | grep -iq "Path=/"; then
            echo "  [PASS] Path=/ is present." | tee -a "$OUTPUT_FILE"
            has_path="true"
        else
            echo "  [FAIL] Path=/ is MISSING!" | tee -a "$OUTPUT_FILE"
        fi
    fi
    echo "" | tee -a "$OUTPUT_FILE"

    echo "  \"$proxy_name\": {" >> "$JSON_FILE"
    echo "    \"has_cookie\": $has_cookie," >> "$JSON_FILE"
    echo "    \"cookie_value\": \"${cookie_val//\"/\\\"}\"," >> "$JSON_FILE"
    echo "    \"has_httponly\": $has_httponly," >> "$JSON_FILE"
    echo "    \"has_path\": $has_path" >> "$JSON_FILE"
    
    if [ "$is_last" = "true" ]; then
        echo "  }" >> "$JSON_FILE"
    else
        echo "  }," >> "$JSON_FILE"
    fi
}

# Run tests
test_cookie "HAProxy" 80 "false"
test_cookie "APISIX" 90 "true"

echo "}" >> "$JSON_FILE"
echo "Results saved to $OUTPUT_FILE and $JSON_FILE"
