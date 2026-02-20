#!/bin/bash
# 2_test_path_routing.sh - Tests if path routing works identically on HAProxy and APISIX

OUTPUT_FILE="results/2_path_routing_results.txt"
JSON_FILE="results/2_path_routing_results.json"
> "$OUTPUT_FILE"

echo "{" > "$JSON_FILE"

echo "==================================================" | tee -a "$OUTPUT_FILE"
echo " TEST 2: PATH ROUTING" | tee -a "$OUTPUT_FILE"
echo "==================================================" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

PATHS=(
    "/wps/portal"
    "/dx/api/dam/v1/collections"
    "/invalid-path-should-404"
)

test_routing() {
    local proxy_name=$1
    local port=$2
    local is_last=$3

    echo "Testing Paths on $proxy_name (Port $port)..." | tee -a "$OUTPUT_FILE"
    
    echo "  \"$proxy_name\": {" >> "$JSON_FILE"
    
    local path_count=${#PATHS[@]}
    local i=1
    
    for path in "${PATHS[@]}"; do
        local full_url="http://localhost:$port$path"
        # Display nicely in text output:
        if [ "$port" = "80" ]; then
            display_url="http://localhost$path"
        else
            display_url="$full_url"
        fi
        
        status=$(curl -s -o /dev/null -w "%{http_code}" "$full_url")
        echo "  [GET $display_url] -> HTTP $status" | tee -a "$OUTPUT_FILE"
        
        if [ $i -eq $path_count ]; then
            echo "    \"$display_url\": $status" >> "$JSON_FILE"
        else
            echo "    \"$display_url\": $status," >> "$JSON_FILE"
        fi
        ((i++))
    done
    
    if [ "$is_last" = "true" ]; then
        echo "  }" >> "$JSON_FILE"
    else
        echo "  }," >> "$JSON_FILE"
    fi
    echo "" | tee -a "$OUTPUT_FILE"
}

# Run tests
test_routing "HAProxy" 80 "false"
test_routing "APISIX" 90 "true"

echo "}" >> "$JSON_FILE"

echo "Conclusion: If the HTTP status codes match between HAProxy and APISIX," | tee -a "$OUTPUT_FILE"
echo "then both are routing paths to the appropriate (or identically missing) backends." | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "Results saved to $OUTPUT_FILE and $JSON_FILE"
