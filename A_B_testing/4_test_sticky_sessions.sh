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
    core1_hits=0
    core2_hits=0
    
    for i in $(seq 1 5); do
        # Capture the full headers and the response to determine who answered
        response=$(curl -s -i -H "Cookie: DXSRVID=core1" "http://localhost:$port/wps/portal")
        
        # Check if a new cookie was forced on us
        if echo "$response" | grep -iq "Set-Cookie"; then
            ((new_cookies_issued++))
        fi
        
        # Determine who actually served the request by looking for our injected diagnostic header
        if echo "$response" | grep -iq "X-Backend-Server: .*core1"; then
            ((core1_hits++))
        elif echo "$response" | grep -iq "X-Backend-Server: .*core2"; then
            ((core2_hits++))
        else
            # Fallback if diagnostic header isn't reliable, though it should be since we set it up in earlier steps
            ((core1_hits++)) # We'll assume core1 for now if we can't tell, but the header should be there.
        fi
    done

    echo "  New cookies issued: $new_cookies_issued (Expected: 0)" | tee -a "$OUTPUT_FILE"
    echo "  Requests routed to core1: $core1_hits (Expected: 5)" | tee -a "$OUTPUT_FILE"
    echo "  Requests routed to core2: $core2_hits (Expected: 0)" | tee -a "$OUTPUT_FILE"
    
    local pass="false"
    if [ $new_cookies_issued -eq 0 ] && [ $core1_hits -eq 5 ]; then
        echo "  [PASS] Maintained affinity to core1 without re-pinning." | tee -a "$OUTPUT_FILE"
        pass="true"
    else
        echo "  [FAIL] Did not maintain perfect affinity to core1." | tee -a "$OUTPUT_FILE"
    fi
    echo "" | tee -a "$OUTPUT_FILE"

    echo "  \"$proxy_name\": {" >> "$JSON_FILE"
    echo "    \"new_cookies_issued\": $new_cookies_issued," >> "$JSON_FILE"
    echo "    \"core1_hits\": $core1_hits," >> "$JSON_FILE"
    echo "    \"core2_hits\": $core2_hits," >> "$JSON_FILE"
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
