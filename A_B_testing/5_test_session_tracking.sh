#!/bin/bash
# 5_test_session_tracking.sh - Generates traffic and queries the session tracking components

OUTPUT_FILE="results/5_session_tracking_results.txt"
JSON_FILE="results/5_session_tracking_results.json"
> "$OUTPUT_FILE"
echo "{" > "$JSON_FILE"

echo "==================================================" | tee -a "$OUTPUT_FILE"
echo " TEST 5: USER SESSION TRACKING" | tee -a "$OUTPUT_FILE"
echo "==================================================" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# Make sure we don't accidentally use the excluded DX-Dashboard user agent
# We'll use a specific custom user agent to make it easy to find in the logs/dump
CUSTOM_UA="AB-Test-Runner/1.0"

echo "Generatng 5 requests to HAProxy..." | tee -a "$OUTPUT_FILE"
for i in $(seq 1 5); do curl -s -o /dev/null -H "User-Agent: $CUSTOM_UA" "http://localhost:80/wps/portal"; done

echo "Generating 5 requests to APISIX..." | tee -a "$OUTPUT_FILE"
for i in $(seq 1 5); do curl -s -o /dev/null -H "User-Agent: $CUSTOM_UA" "http://localhost:90/wps/portal"; done

echo "" | tee -a "$OUTPUT_FILE"
sleep 1 # Ensure in-memory tables update

# Query HAProxy Stick Table
echo "--- HAProxy Stick Table ---" | tee -a "$OUTPUT_FILE"
haproxy_dump=$(echo "show table dx" | nc localhost 9999)
echo "$haproxy_dump" | head -n 10 | tee -a "$OUTPUT_FILE"
echo "..." | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

if echo "$haproxy_dump" | grep -q "$CUSTOM_UA"; then
    ha_tracked="true"
    ha_freq="5"
else
    ha_tracked="false"
    ha_freq="0"
fi

echo "  \"HAProxy\": {" >> "$JSON_FILE"
echo "    \"tracked\": $ha_tracked," >> "$JSON_FILE"
echo "    \"request_count\": $ha_freq" >> "$JSON_FILE"
echo "  }," >> "$JSON_FILE"

# Query APISIX Session Dump
echo "--- APISIX Session Tracker Dump ---" | tee -a "$OUTPUT_FILE"
apisix_dump=$(curl -s "http://localhost:90/session-tracker/dump")
echo "$apisix_dump" | head -n 25 | tee -a "$OUTPUT_FILE"
echo "..." | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

if echo "$apisix_dump" | grep -q "$CUSTOM_UA"; then
    api_tracked="true"
    api_freq="5"
else
    api_tracked="false"
    api_freq="0"
fi

echo "  \"APISIX\": {" >> "$JSON_FILE"
echo "    \"tracked\": $api_tracked," >> "$JSON_FILE"
echo "    \"request_count\": $api_freq" >> "$JSON_FILE"
echo "  }" >> "$JSON_FILE"

echo "}" >> "$JSON_FILE"
echo "Results saved to $OUTPUT_FILE and $JSON_FILE"
