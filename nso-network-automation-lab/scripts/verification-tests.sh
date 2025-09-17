#!/bin/bash
# NSO Verification and Testing Script
# Performs comprehensive tests on NSO deployment

set -e

# Configuration Variables
NSO_USER="admin"
TEST_RESULTS_DIR="../test-results"
TEST_LOG="$TEST_RESULTS_DIR/test-$(date +%Y%m%d_%H%M%S).log"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Functions
log_test_start() {
    echo -e "${BLUE}[TEST]${NC} $1" | tee -a "$TEST_LOG"
}

log_test_pass() {
    echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$TEST_LOG"
    ((TESTS_PASSED++))
}

log_test_fail() {
    echo -e "${RED}[FAIL]${NC} $1" | tee -a "$TEST_LOG"
    ((TESTS_FAILED++))
}

log_test_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1" | tee -a "$TEST_LOG"
    ((TESTS_SKIPPED++))
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$TEST_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$TEST_LOG"
}

setup_test_environment() {
    log_info "Setting up test environment..."
    mkdir -p "$TEST_RESULTS_DIR"
    echo "NSO Verification Tests - $(date)" > "$TEST_LOG"
    echo "======================================" >> "$TEST_LOG"
}

test_nso_status() {
    log_test_start "Testing NSO service status..."

    if ncs --status &> /dev/null; then
        log_test_pass "NSO service is running"
    else
        log_test_fail "NSO service is not running"
        return 1
    fi
}

test_nso_cli_access() {
    log_test_start "Testing NSO CLI access..."

    if ncs_cli -u $NSO_USER -C -c "show version" &> /dev/null; then
        log_test_pass "NSO CLI access successful"
    else
        log_test_fail "Cannot access NSO CLI"
    fi
}

test_web_ui_access() {
    log_test_start "Testing Web UI accessibility..."

    WEB_PORT=$(grep "<port>" /var/opt/nso/*/ncs.conf | head -1 | sed 's/.*<port>\(.*\)<\/port>.*/\1/')

    if curl -s -o /dev/null -w "%{http_code}" http://localhost:$WEB_PORT | grep -q "200\|302"; then
        log_test_pass "Web UI is accessible on port $WEB_PORT"
    else
        log_test_fail "Web UI is not accessible"
    fi
}

test_device_connectivity() {
    log_test_start "Testing device connectivity..."

    DEVICES=$(ncs_cli -u $NSO_USER -C -c "show devices list" | awk '/^[a-zA-Z]/ {print $1}' | tail -n +2)
    FAILED_DEVICES=""

    for device in $DEVICES; do
        echo -n "  Testing $device... " | tee -a "$TEST_LOG"

        if ncs_cli -u $NSO_USER -C -c "devices device $device connect" 2>&1 | grep -q "result true"; then
            echo -e "${GREEN}Connected${NC}" | tee -a "$TEST_LOG"
        else
            echo -e "${RED}Failed${NC}" | tee -a "$TEST_LOG"
            FAILED_DEVICES="$FAILED_DEVICES $device"
        fi
    done

    if [ -z "$FAILED_DEVICES" ]; then
        log_test_pass "All devices connected successfully"
    else
        log_test_fail "Failed to connect to:$FAILED_DEVICES"
    fi
}

test_device_sync_status() {
    log_test_start "Testing device sync status..."

    SYNC_OUTPUT=$(ncs_cli -u $NSO_USER -C -c "devices check-sync")
    OUT_OF_SYNC=$(echo "$SYNC_OUTPUT" | grep -c "out-of-sync" || true)

    if [ "$OUT_OF_SYNC" -eq 0 ]; then
        log_test_pass "All devices are in sync"
    else
        log_test_fail "$OUT_OF_SYNC devices are out of sync"
        echo "$SYNC_OUTPUT" | grep "out-of-sync" | tee -a "$TEST_LOG"
    fi
}

test_service_deployment() {
    log_test_start "Testing service deployments..."

    # Test VLAN services
    VLAN_SERVICES=$(ncs_cli -u $NSO_USER -C -c "show running-config services vlan-service" | grep -c "vlan-service" || true)

    if [ "$VLAN_SERVICES" -gt 0 ]; then
        log_test_pass "Found $VLAN_SERVICES VLAN services deployed"
    else
        log_test_fail "No VLAN services found"
    fi

    # Test DNS services
    DNS_SERVICES=$(ncs_cli -u $NSO_USER -C -c "show running-config services dns-config" | grep -c "dns-config" || true)

    if [ "$DNS_SERVICES" -gt 0 ]; then
        log_test_pass "Found $DNS_SERVICES DNS services deployed"
    else
        log_test_fail "No DNS services found"
    fi
}

test_package_status() {
    log_test_start "Testing package status..."

    PACKAGE_OUTPUT=$(ncs_cli -u $NSO_USER -C -c "show packages package oper-status")
    FAILED_PACKAGES=$(echo "$PACKAGE_OUTPUT" | grep -v "up" | grep "oper-status" || true)

    if [ -z "$FAILED_PACKAGES" ]; then
        log_test_pass "All packages are operational"
    else
        log_test_fail "Some packages are not operational"
        echo "$FAILED_PACKAGES" | tee -a "$TEST_LOG"
    fi
}

test_authgroup_configuration() {
    log_test_start "Testing authgroup configuration..."

    AUTHGROUPS=$(ncs_cli -u $NSO_USER -C -c "show running-config devices authgroups" | grep -c "authgroups group" || true)

    if [ "$AUTHGROUPS" -gt 0 ]; then
        log_test_pass "Found $AUTHGROUPS authgroups configured"
    else
        log_test_fail "No authgroups configured"
    fi
}

test_device_groups() {
    log_test_start "Testing device groups..."

    DEVICE_GROUPS=$(ncs_cli -u $NSO_USER -C -c "show running-config devices device-group" | grep -c "device-group" || true)

    if [ "$DEVICE_GROUPS" -gt 0 ]; then
        log_test_pass "Found $DEVICE_GROUPS device groups configured"
    else
        log_test_fail "No device groups configured"
    fi
}

test_service_validation() {
    log_test_start "Testing service validation..."

    # Perform service check
    if ncs_cli -u $NSO_USER -C -c "services check-sync" &> /dev/null; then
        log_test_pass "Service validation successful"
    else
        log_test_fail "Service validation failed"
    fi
}

test_rollback_capability() {
    log_test_start "Testing rollback capability..."

    # Get rollback files count
    ROLLBACK_COUNT=$(ncs_cli -u $NSO_USER -C -c "show configuration rollback" | grep -c "Rollback" || true)

    if [ "$ROLLBACK_COUNT" -gt 0 ]; then
        log_test_pass "Found $ROLLBACK_COUNT rollback points available"
    else
        log_test_skip "No rollback points available (this is normal for new installations)"
    fi
}

test_compliance_check() {
    log_test_start "Testing compliance reporting..."

    # Create a simple compliance report
    ncs_cli -u $NSO_USER -C << EOF > "$TEST_RESULTS_DIR/compliance-report.txt" 2>&1
devices device * compare-config
exit
EOF

    if [ -s "$TEST_RESULTS_DIR/compliance-report.txt" ]; then
        log_test_pass "Compliance report generated"
    else
        log_test_fail "Failed to generate compliance report"
    fi
}

performance_test() {
    log_test_start "Running performance test..."

    # Measure sync-from time
    START_TIME=$(date +%s%N)
    ncs_cli -u $NSO_USER -C -c "devices sync-from" &> /dev/null
    END_TIME=$(date +%s%N)
    ELAPSED=$((($END_TIME - $START_TIME) / 1000000))

    log_info "Sync-from completed in ${ELAPSED}ms"

    if [ "$ELAPSED" -lt 5000 ]; then
        log_test_pass "Performance test passed (${ELAPSED}ms < 5000ms)"
    else
        log_test_fail "Performance test failed (${ELAPSED}ms > 5000ms)"
    fi
}

generate_test_report() {
    log_info "Generating test report..."

    REPORT_FILE="$TEST_RESULTS_DIR/test-report-$(date +%Y%m%d_%H%M%S).html"

    cat > "$REPORT_FILE" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>NSO Verification Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .summary { background: #f0f0f0; padding: 10px; border-radius: 5px; margin: 20px 0; }
        .passed { color: green; font-weight: bold; }
        .failed { color: red; font-weight: bold; }
        .skipped { color: orange; font-weight: bold; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
    </style>
</head>
<body>
    <h1>NSO Verification Test Report</h1>
    <p>Generated: $(date)</p>

    <div class="summary">
        <h2>Test Summary</h2>
        <p>Total Tests: $((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))</p>
        <p class="passed">Passed: $TESTS_PASSED</p>
        <p class="failed">Failed: $TESTS_FAILED</p>
        <p class="skipped">Skipped: $TESTS_SKIPPED</p>
    </div>

    <h2>Test Results</h2>
    <pre>$(cat "$TEST_LOG")</pre>
</body>
</html>
EOF

    log_info "Test report generated: $REPORT_FILE"
}

print_summary() {
    echo
    echo "======================================"
    echo -e "${MAGENTA}Test Execution Summary${NC}"
    echo "======================================"
    echo -e "Total Tests: $((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo -e "${YELLOW}Skipped: $TESTS_SKIPPED${NC}"
    echo "======================================"

    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}All tests passed successfully!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed. Please check the log for details.${NC}"
        exit 1
    fi
}

# Main execution
main() {
    log_info "Starting NSO verification tests..."

    setup_test_environment

    # Core functionality tests
    test_nso_status
    test_nso_cli_access
    test_web_ui_access

    # Device tests
    test_device_connectivity
    test_device_sync_status

    # Configuration tests
    test_authgroup_configuration
    test_device_groups

    # Service tests
    test_service_deployment
    test_service_validation

    # Package tests
    test_package_status

    # Advanced tests
    test_rollback_capability
    test_compliance_check
    performance_test

    # Generate report
    generate_test_report

    # Print summary
    print_summary
}

# Run main function
main "$@"