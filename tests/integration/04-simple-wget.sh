#!/bin/bash

# Test 04: Simple wget Test
# --------------------------
# Bundles and verifies GNU Wget, which pulls in SSL, zlib, pcre2, idn2.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TEST_NAME="simple-wget"
BUNDLE_NAME="wget-bundle"
PRIMARY_BIN="wget"

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
            apk add --no-cache wget
        elif command -v apt-get >/dev/null; then
            apt-get update && apt-get install -y wget
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

        # 2. Test basic wget functionality
        verify_bundle_execution "$PRIMARY_BIN" "--version" "GNU Wget" "$BUNDELF_MERGE_BINDIRS"

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
