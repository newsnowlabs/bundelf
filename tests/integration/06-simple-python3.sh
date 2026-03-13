#!/bin/bash

# Test 06: Simple Python3 Test
# -----------------------------
# Bundles and verifies python3. Also validates stdlib dynamic modules load.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TEST_NAME="simple-python3"
BUNDLE_NAME="python3-bundle"
PRIMARY_BIN="python3"

# Set final bundle path before sourcing utils
export BUNDELF_CODE_PATH="${BUNDELF_BUNDLES_PATH}/${BUNDLE_NAME}"

source "$SCRIPT_DIR/../common/test-utils.sh"

# Initialize test environment (with validation)
init_test_env

case "${TEST_PHASE:-build}" in
    build)
        echo "Phase: Building bundle..."
        
        # Install required packages for bundle creation
        if command -v apk >/dev/null; then
            apk add --no-cache python3
        elif command -v apt-get >/dev/null; then
            apt-get update && apt-get install -y python3
        else
            echo "Unsupported package manager"
            exit 1
        fi

        # Create bundle directory if it doesn't exist
        mkdir -p "$BUNDELF_CODE_PATH"
        
        # Create the bundle
        export BUNDELF_BINARIES="$PRIMARY_BIN"
        
        echo "Creating $PRIMARY_BIN bundle in $BUNDELF_CODE_PATH..."
        $BUNDELF_PATH/make-bundelf-bundle.sh --bundle || exit 1
        ;;

    verify)
        echo "Phase: Verifying bundle..."
        
        # List bundle contents for debugging
        find "$BUNDELF_CODE_PATH" -type f

        # 1. Verify bundle structure
        verify_bundle_structure "$PRIMARY_BIN" "$BUNDELF_MERGE_BINDIRS"

        # 2. Test python3 works and can import common dynamic modules
        verify_bundle_execution "$PRIMARY_BIN" "--version" "^Python 3" "$BUNDELF_MERGE_BINDIRS"

        # Try import ssl, sqlite3, ctypes
        rel_path=$(find_binary_path "$PRIMARY_BIN" "$BUNDELF_MERGE_BINDIRS") || exit 1
        binary_path="$BUNDELF_CODE_PATH/$rel_path"
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        echo -n "Testing python3 dynamic imports ... "
        if echo 'import ssl,sqlite3,ctypes,hashlib; print("ok")' | "$binary_path" - 2>/dev/null | grep -q '^ok$'; then
          echo -e "${GREEN}PASS${NC}"; TESTS_PASSED=$((TESTS_PASSED + 1));
        else
          echo -e "${RED}FAIL${NC}"; TESTS_FAILED=$((TESTS_FAILED + 1));
        fi

        # Print in-container summary and return its status
        status=0
        print_test_summary || status=$?
        cleanup_test_env
        exit $status
        ;;

    *)
        echo "Error: Unknown test phase '${TEST_PHASE}'"
        exit 1
        ;;
 esac

# Clean up
cleanup_test_env
