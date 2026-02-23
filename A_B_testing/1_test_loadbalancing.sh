#!/bin/bash
# 1_test_loadbalancing.sh - Tests round-robin distribution for HAProxy and APISIX

OUTPUT_FILE="results/1_loadbalancing_results.txt"
JSON_FILE="results/1_loadbalancing_results.json"
> "$OUTPUT_FILE"

# Initialize JSON output
echo "{" > "$JSON_FILE"

echo "==================================================" | tee -a "$OUTPUT_FILE"
echo " TEST 1: LOAD BALANCING (Round Robin)" | tee -a "$OUTPUT_FILE"
echo "==================================================" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# Function to run LB test
test_lb() {
    local proxy_name=$1
    local port=$2
    local iters=30
    local is_last=$3

    echo "Testing $proxy_name (Port $port) with $iters requests..." | tee -a "$OUTPUT_FILE"
    
    core1_count=0
    core2_count=0
    error_count=0

    local start_time=$(python3 -c 'import time; print(time.time())')

    for i in $(seq 1 $iters); do
        headers=$(curl -s -I -w "\nHTTP_STATUS:%{http_code}" http://localhost:$port/wps/portal 2>/dev/null)
        status=$(echo "$headers" | grep "HTTP_STATUS:" | cut -d':' -f2)
        if [ -z "$status" ] || [[ "$status" =~ ^[45] ]]; then
            ((error_count++))
            continue
        fi
        cookie=$(echo "$headers" | grep -i "Set-Cookie: DXSRVID")
        if echo "$cookie" | grep -q "core1"; then
            ((core1_count++))
        elif echo "$cookie" | grep -q "core2"; then
            ((core2_count++))
        else
            ((error_count++))
        fi
    done

    local end_time=$(python3 -c 'import time; print(time.time())')
    local elapsed=$(python3 -c "print(round($end_time - $start_time, 3))")

    echo "  Results for $proxy_name:" | tee -a "$OUTPUT_FILE"
    echo "    dx-core  (core1) handled: $core1_count requests" | tee -a "$OUTPUT_FILE"
    echo "    dx-core-2 (core2) handled: $core2_count requests" | tee -a "$OUTPUT_FILE"
    echo "    Errors/no cookie:          $error_count requests" | tee -a "$OUTPUT_FILE"
    echo "    Execution time: ${elapsed}s" | tee -a "$OUTPUT_FILE"
    
    local pass="false"
    if [[ $core1_count -gt 0 && $core2_count -gt 0 && $error_count -eq 0 ]]; then
        echo "  [PASS] Traffic is being load-balanced across multiple cores." | tee -a "$OUTPUT_FILE"
        pass="true"
    elif [[ $core1_count -gt 0 && $core2_count -gt 0 && $error_count -gt 0 ]]; then
        echo "  [WARN] Traffic is load-balanced but $error_count requests had errors." | tee -a "$OUTPUT_FILE"
        pass="true"
    else
        echo "  [FAIL] Traffic is NOT being load-balanced." | tee -a "$OUTPUT_FILE"
    fi
    echo "" | tee -a "$OUTPUT_FILE"

    # Append to JSON
    echo "  \"$proxy_name\": {" >> "$JSON_FILE"
    echo "    \"core1_count\": $core1_count," >> "$JSON_FILE"
    echo "    \"core2_count\": $core2_count," >> "$JSON_FILE"
    echo "    \"error_count\": $error_count," >> "$JSON_FILE"
    echo "    \"execution_time\": $elapsed," >> "$JSON_FILE"
    echo "    \"pass\": $pass" >> "$JSON_FILE"
    if [ "$is_last" = "true" ]; then
        echo "  }" >> "$JSON_FILE"
    else
        echo "  }," >> "$JSON_FILE"
    fi
}

# Test HAProxy (80)
test_lb "HAProxy" 80 "false"

# Test APISIX (90)
test_lb "APISIX" 90 "true"

echo "}" >> "$JSON_FILE"

echo "Results saved to $OUTPUT_FILE and $JSON_FILE"
