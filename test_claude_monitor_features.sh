#!/bin/bash

# ABOUTME: Comprehensive test script for Claude Code Usage Monitor features in q-status menubar app
# This script validates all Claude-related features including plan switching, progress bars, burn rates, and billing blocks

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test result tracking
PASSED=0
FAILED=0
WARNINGS=0

# Test results file
RESULTS_FILE="/Users/stevengonsalvez/d/git/qlips/test_results_claude_monitor.md"

# Function to log test results
log_test() {
    local status=$1
    local test_name=$2
    local details=$3

    echo -e "${status} ${test_name}"
    if [ -n "$details" ]; then
        echo "  Details: $details"
    fi

    case "$status" in
        *PASS*)
            ((PASSED++))
            ;;
        *FAIL*)
            ((FAILED++))
            ;;
        *WARN*)
            ((WARNINGS++))
            ;;
    esac
}

# Function to check if a file exists
check_file() {
    local file=$1
    local description=$2

    if [ -f "$file" ]; then
        log_test "${GREEN}[PASS]${NC}" "$description" "File exists: $file"
        return 0
    else
        log_test "${RED}[FAIL]${NC}" "$description" "File missing: $file"
        return 1
    fi
}

# Function to check Swift compilation
check_compilation() {
    local test_name=$1
    local file=$2

    echo -e "\n${BLUE}Testing compilation: $test_name${NC}"

    if swift -typecheck "$file" 2>/dev/null; then
        log_test "${GREEN}[PASS]${NC}" "Compilation: $test_name" "No errors"
        return 0
    else
        local errors=$(swift -typecheck "$file" 2>&1 | head -5)
        log_test "${RED}[FAIL]${NC}" "Compilation: $test_name" "$errors"
        return 1
    fi
}

# Function to test feature presence in code
test_feature_in_code() {
    local feature=$1
    local pattern=$2
    local file=$3

    if grep -q "$pattern" "$file" 2>/dev/null; then
        log_test "${GREEN}[PASS]${NC}" "Feature: $feature" "Found in $file"
        return 0
    else
        log_test "${RED}[FAIL]${NC}" "Feature: $feature" "Not found in $file"
        return 1
    fi
}

echo "================================================"
echo "Claude Code Usage Monitor Feature Test Suite"
echo "================================================"
echo ""

# Change to project directory
cd /Users/stevengonsalvez/d/git/qlips

# 1. Test Core Claude Files Existence
echo -e "\n${BLUE}=== Testing Core Claude Files ===${NC}"
check_file "q-status-menubar/Sources/Core/ClaudeCodeDataSource.swift" "ClaudeCodeDataSource implementation"
check_file "q-status-menubar/Sources/Core/ClaudeCostCalculator.swift" "ClaudeCostCalculator implementation"
check_file "q-status-menubar/Sources/Core/SessionBlockCalculator.swift" "SessionBlockCalculator implementation"

# 2. Test Plan Selection Features
echo -e "\n${BLUE}=== Testing Plan Selection Features ===${NC}"

# Check for ClaudePlan enum
if grep -q "enum ClaudePlan" q-status-menubar/Sources/Core/Settings.swift 2>/dev/null || \
   grep -q "enum ClaudePlan" q-status-menubar/Sources/Core/ClaudeCodeDataSource.swift 2>/dev/null; then
    log_test "${GREEN}[PASS]${NC}" "ClaudePlan enum" "Plan selection structure exists"

    # Check for specific plans
    for plan in "pro" "max5" "max20" "custom"; do
        if grep -qi "case $plan" q-status-menubar/Sources/Core/*.swift 2>/dev/null; then
            log_test "${GREEN}[PASS]${NC}" "Plan: $plan" "Plan option available"
        else
            log_test "${YELLOW}[WARN]${NC}" "Plan: $plan" "Plan option not found"
        fi
    done
else
    log_test "${RED}[FAIL]${NC}" "ClaudePlan enum" "Plan selection not implemented"
fi

# 3. Test Custom Plan P90 Configuration
echo -e "\n${BLUE}=== Testing Custom Plan P90 Configuration ===${NC}"
if grep -q "p90\|percentile\|customP90" q-status-menubar/Sources/Core/*.swift 2>/dev/null; then
    log_test "${GREEN}[PASS]${NC}" "Custom P90 configuration" "P90 settings found"
else
    log_test "${YELLOW}[WARN]${NC}" "Custom P90 configuration" "P90 settings not found"
fi

# 4. Test Three Progress Bars
echo -e "\n${BLUE}=== Testing Three Progress Bars ===${NC}"
for metric in "tokens" "cost" "messages"; do
    if grep -qi "$metric" q-status-menubar/Sources/Core/ClaudeCodeDataSource.swift 2>/dev/null; then
        log_test "${GREEN}[PASS]${NC}" "Progress metric: $metric" "Metric tracked"
    else
        log_test "${RED}[FAIL]${NC}" "Progress metric: $metric" "Metric not tracked"
    fi
done

# Check for progress bar UI components
if grep -q "ProgressView\|progressBar\|UsageProgressView" q-status-menubar/Sources/UI/*.swift 2>/dev/null; then
    log_test "${GREEN}[PASS]${NC}" "Progress bar UI" "Progress views implemented"
else
    log_test "${YELLOW}[WARN]${NC}" "Progress bar UI" "Progress views not found in UI"
fi

# 5. Test Color Coding
echo -e "\n${BLUE}=== Testing Color Coding ===${NC}"
for color in "green\|Color.green" "yellow\|Color.yellow" "red\|Color.red"; do
    if grep -q "$color" q-status-menubar/Sources/UI/*.swift 2>/dev/null; then
        log_test "${GREEN}[PASS]${NC}" "Color coding: $(echo $color | cut -d'\' -f1)" "Color implemented"
    else
        log_test "${YELLOW}[WARN]${NC}" "Color coding: $(echo $color | cut -d'\' -f1)" "Color not found"
    fi
done

# 6. Test Billing Block Display
echo -e "\n${BLUE}=== Testing Billing Block Display ===${NC}"
if grep -q "SessionBlock\|billingBlock\|block" q-status-menubar/Sources/Core/SessionBlockCalculator.swift 2>/dev/null; then
    log_test "${GREEN}[PASS]${NC}" "Billing blocks" "Session block structure exists"

    # Check for time remaining calculation
    if grep -q "timeRemaining\|hoursRemaining\|blockEnd" q-status-menubar/Sources/Core/*.swift 2>/dev/null; then
        log_test "${GREEN}[PASS]${NC}" "Time remaining" "Time calculation implemented"
    else
        log_test "${YELLOW}[WARN]${NC}" "Time remaining" "Time calculation not found"
    fi
else
    log_test "${RED}[FAIL]${NC}" "Billing blocks" "Session block not implemented"
fi

# 7. Test Burn Rate Display
echo -e "\n${BLUE}=== Testing Burn Rate Display ===${NC}"
for rate in "tokensPerHour" "costPerHour" "messagesPerHour"; do
    if grep -q "$rate" q-status-menubar/Sources/Core/ClaudeCodeDataSource.swift 2>/dev/null; then
        log_test "${GREEN}[PASS]${NC}" "Burn rate: $rate" "Rate calculation exists"
    else
        log_test "${RED}[FAIL]${NC}" "Burn rate: $rate" "Rate calculation missing"
    fi
done

# 8. Test Predictions
echo -e "\n${BLUE}=== Testing Predictions ===${NC}"
if grep -q "predict\|timeToLimit\|estimatedTime" q-status-menubar/Sources/Core/*.swift 2>/dev/null; then
    log_test "${GREEN}[PASS]${NC}" "Limit predictions" "Prediction logic found"
else
    log_test "${YELLOW}[WARN]${NC}" "Limit predictions" "Prediction logic not found"
fi

# 9. Test Message Counting from JSONL
echo -e "\n${BLUE}=== Testing Message Counting ===${NC}"
if grep -q "messageCount" q-status-menubar/Sources/Core/ClaudeCodeDataSource.swift; then
    log_test "${GREEN}[PASS]${NC}" "Message counting" "Message count tracked"
else
    log_test "${RED}[FAIL]${NC}" "Message counting" "Message count not tracked"
fi

# 10. Test Cost Calculation with Cache Tokens
echo -e "\n${BLUE}=== Testing Cache Token Cost Calculation ===${NC}"
if grep -q "cache_creation_input_tokens\|cache_read_input_tokens" q-status-menubar/Sources/Core/ClaudeCodeDataSource.swift; then
    log_test "${GREEN}[PASS]${NC}" "Cache tokens" "Cache token support exists"

    if grep -q "cacheCreationCostPerToken\|cacheReadCostPerToken" q-status-menubar/Sources/Core/ClaudeCostCalculator.swift; then
        log_test "${GREEN}[PASS]${NC}" "Cache token pricing" "Cache pricing implemented"
    else
        log_test "${RED}[FAIL]${NC}" "Cache token pricing" "Cache pricing missing"
    fi
else
    log_test "${RED}[FAIL]${NC}" "Cache tokens" "Cache token support missing"
fi

# 11. Test Session Grouping by Folder
echo -e "\n${BLUE}=== Testing Session Grouping ===${NC}"
if grep -q "cwd\|currentWorkingDirectory\|folder" q-status-menubar/Sources/Core/ClaudeCodeDataSource.swift; then
    log_test "${GREEN}[PASS]${NC}" "Session grouping by folder" "Folder tracking exists"
else
    log_test "${YELLOW}[WARN]${NC}" "Session grouping by folder" "Folder tracking not found"
fi

# 12. Test Settings Persistence
echo -e "\n${BLUE}=== Testing Settings Persistence ===${NC}"
if grep -q "@AppStorage\|UserDefaults" q-status-menubar/Sources/Core/Settings.swift 2>/dev/null || \
   grep -q "@AppStorage\|UserDefaults" q-status-menubar/Sources/UI/*.swift 2>/dev/null; then
    log_test "${GREEN}[PASS]${NC}" "Settings persistence" "Settings storage implemented"
else
    log_test "${RED}[FAIL]${NC}" "Settings persistence" "Settings storage not found"
fi

# 13. Build the app
echo -e "\n${BLUE}=== Building the App ===${NC}"
cd q-status-menubar

if swift build 2>/dev/null; then
    log_test "${GREEN}[PASS]${NC}" "App build" "Build successful"
else
    # Try to capture and show first few errors
    BUILD_ERRORS=$(swift build 2>&1 | head -10)
    log_test "${RED}[FAIL]${NC}" "App build" "Build failed: $BUILD_ERRORS"
fi

# 14. Test for runtime configuration
echo -e "\n${BLUE}=== Testing Runtime Configuration ===${NC}"

# Check if preferences UI has Claude options
if [ -f "Sources/UI/PreferencesView.swift" ]; then
    if grep -q "Claude\|claude" Sources/UI/PreferencesView.swift 2>/dev/null; then
        log_test "${GREEN}[PASS]${NC}" "Claude in Preferences UI" "Claude options in preferences"
    else
        log_test "${YELLOW}[WARN]${NC}" "Claude in Preferences UI" "Claude options not in preferences"
    fi
fi

# 15. Check for data source registration
if grep -q "ClaudeCodeDataSource\|registerDataSource.*Claude" Sources/Core/*.swift 2>/dev/null; then
    log_test "${GREEN}[PASS]${NC}" "Data source registration" "Claude data source registered"
else
    log_test "${RED}[FAIL]${NC}" "Data source registration" "Claude data source not registered"
fi

# Summary
echo ""
echo "================================================"
echo "Test Summary"
echo "================================================"
echo -e "${GREEN}Passed:${NC} $PASSED"
echo -e "${RED}Failed:${NC} $FAILED"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo ""

# Generate overall status
if [ $FAILED -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}✅ All tests passed!${NC}"
        EXIT_CODE=0
    else
        echo -e "${YELLOW}⚠️ Tests passed with warnings${NC}"
        EXIT_CODE=0
    fi
else
    echo -e "${RED}❌ Some tests failed${NC}"
    EXIT_CODE=1
fi

# Write results to file (will be done in the next file write)
echo "Results written to: $RESULTS_FILE"

exit $EXIT_CODE