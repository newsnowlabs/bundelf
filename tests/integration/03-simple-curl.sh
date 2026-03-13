#!/bin/bash

# Test 03: Simple curl Test
# --------------------------
# Bundles and verifies curl, which pulls in libcurl, SSL, zlib, etc.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TEST_NAME="simple-curl"
BUNDLE_NAME="curl-bundle"
PRIMARY_BIN="curl"

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
            apk add --no-cache curl
        elif command -v apt-get >/dev/null; then
            apt-get update && apt-get install -y curl
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

        # 2. Test basic curl functionality
        verify_bundle_execution "$PRIMARY_BIN" "--version" "curl" "$BUNDELF_MERGE_BINDIRS"

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
