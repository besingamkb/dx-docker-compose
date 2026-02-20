#!/bin/bash
# 4_test_sticky_sessions.sh - Verifies that providing a valid cookie maintains affinity

OUTPUT_FILE="results/4_sticky_sessions_results.txt"
JSON_FILE="results/4_sticky_sessions_results.json"
> "$OUTPUT_FILE"
echo "{" > "$JSON_FILE"

echo "==================================================" | tee -a "$OUTPUT_FILE"
echo " TEST 4: STICKY SESSIONS" | tee -a "$OUTPUT_FILE"
echo "==================================================" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

test_sticky() {
    local proxy_name=$1
    local port=$2
    local is_last=$3

    echo "Testing Sticky Sessions on $proxy_name (Port $port)..." | tee -a "$OUTPUT_FILE"
    
    # Send 5 requests WITH a valid cookie (DXSRVID=core1)
    echo "  Sending 5 requests with 'Cookie: DXSRVID=core1'..." | tee -a "$OUTPUT_FILE"
    
    new_cookies_issued=0
    for i in $(seq 1 5); do
        # We look for a NEW Set-Cookie header. 
        # If sticky sessions work, the proxy accepts the cookie, routes to core1, and does NOT set a new cookie.
        header=$(curl -s -I -H "Cookie: DXSRVID=core1" "http://localhost:$port/wps/portal" | grep -i "Set-Cookie")
        if [ ! -z "$header" ]; then
            ((new_cookies_issued++))
        fi
    done

    echo "  New cookies issued during sticky requests: $new_cookies_issued (Expected: 0)" | tee -a "$OUTPUT_FILE"
    
    local pass="false"
    if [ $new_cookies_issued -eq 0 ]; then
        echo "  [PASS] Server accepted the cookie, maintained affinity, and did not re-pin the session." | tee -a "$OUTPUT_FILE"
        pass="true"
    else
        echo "  [FAIL] Server issued a new cookie, meaning sticky session was broken." | tee -a "$OUTPUT_FILE"
    fi
    echo "" | tee -a "$OUTPUT_FILE"

    echo "  \"$proxy_name\": {" >> "$JSON_FILE"
    echo "    \"new_cookies_issued\": $new_cookies_issued," >> "$JSON_FILE"
    echo "    \"pass\": $pass" >> "$JSON_FILE"
    
    if [ "$is_last" = "true" ]; then
        echo "  }" >> "$JSON_FILE"
    else
        echo "  }," >> "$JSON_FILE"
    fi
}

# Run tests
test_sticky "HAProxy" 80 "false"
test_sticky "APISIX" 90 "true"

echo "}" >> "$JSON_FILE"
echo "Results saved to $OUTPUT_FILE and $JSON_FILE"
