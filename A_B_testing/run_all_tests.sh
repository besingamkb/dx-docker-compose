#!/bin/bash
# run_all_tests.sh - Runs all A/B testing scripts and generates JSON data for the dashboard

echo "Running all A/B Tests..."
echo ""

cd "$(dirname "$0")"

mkdir -p results

./1_test_loadbalancing.sh
./2_test_path_routing.sh
./3_test_cookie_management.sh
./4_test_sticky_sessions.sh
./5_test_session_tracking.sh

echo ""
echo "All tests complete! JSON result files are ready for the dashboard."
