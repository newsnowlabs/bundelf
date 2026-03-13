#!/bin/bash

# Common test utilities for BundELF tests
# --------------------------------------

# Set strict error handling
set -euo pipefail

# Test result tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

escape_regex() {
  local s=$1 d=${2:-/}
  printf '%s' "$s" | sed -e "s/[][(){}.^\$*+?|\\\\$d]/\\\\&/g"
}

# Initialize test environment
init_test_env() {
    if [ -z "${BUNDELF_CODE_PATH:-}" ]; then
        echo "Error: BUNDELF_CODE_PATH must be set"
        exit 1
    fi

  BUNDELF_CODE_PATH_REGEX=$(escape_regex "$BUNDELF_CODE_PATH")
}

# Clean up test environment
cleanup_test_env() {
    # No-op in container environment
    :
}

# Assert function for tests
assert() {
    local message="$1"
    local command="$2"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    echo -n "Testing $message ... "
    if eval "$command"; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Find binary path in bundle
find_binary_path() {
    local binary="$1"
    local merge_bindirs="$2"
    
    if [ -n "$merge_bindirs" ]; then
        echo "bin/$binary"
        return 0
    fi
    
    # Search .binelfs for the binary path
    if [ ! -f "$BUNDELF_CODE_PATH/.binelfs" ]; then
        echo "Error: .binelfs not found in bundle" >&2
        return 1
    fi
    
    local binary_regex="$(escape_regex "$binary")"

    # Extract path from .binelfs, removing BUNDELF_CODE_PATH prefix
    local path=$(grep -m1 "/$binary_regex\$" "$BUNDELF_CODE_PATH/.binelfs" | sed "s|^$BUNDELF_CODE_PATH_REGEX/||")
    if [ -z "$path" ]; then
        echo "Error: Binary '$binary' not found in .binelfs" >&2
        return 1
    fi
    
    echo "$path"
}

# Verify bundle structure based on BUNDELF_MERGE_BINDIRS setting
verify_bundle_structure() {
    local binary="$1"
    local merge_bindirs="$2"
    
    local rel_path=$(find_binary_path "$binary" "$merge_bindirs") || return 1
    assert "binary in expected location" "[ -f \"$BUNDELF_CODE_PATH/$rel_path\" ]"
}

# Verify bundle execution
verify_bundle_execution() {
    local binary="$1"
    local test_command="$2"
    local expected_output="$3"
    local merge_bindirs="$4"

    # Use find_binary_path to determine the binary path
    local rel_path=$(find_binary_path "$binary" "$merge_bindirs") || return 1
    local binary_path="$BUNDELF_CODE_PATH/$rel_path"

    # Execute the test command and capture output
    local actual_output
    actual_output=$($binary_path $test_command 2>&1)

    assert "command execution" "echo ${actual_output@Q} | grep -q ${expected_output@Q}"
}

# Print test summary
print_test_summary() {
    echo
    echo "Test Summary:"
    echo "-------------"
    echo "Total tests:  $TESTS_TOTAL"
    echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"
    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"
        return 1
    fi
    return 0
}

# Export functions
export -f init_test_env
export -f cleanup_test_env
export -f assert
export -f verify_bundle_structure
export -f verify_bundle_execution
export -f print_test_summary