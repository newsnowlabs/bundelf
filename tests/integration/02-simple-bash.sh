#!/bin/bash

# Test 02: Simple bash Test
# ---------------------------
# Tests bundling and executing a simple BusyBox binary with minimal dependencies.
# Supports two phases:
# - build: Creates bundle in source distribution
# - verify: Tests bundle in target distribution

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TEST_NAME="simple-bash"
BUNDLE_NAME="bash-bundle"

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
            apk add --no-cache bash
        elif command -v apt-get >/dev/null; then
            echo "Skipping pointless command: apt-get update && apt-get install -y bash"
        else
            echo "Unsupported package manager"
            exit 1
        fi

        # Create bundle directory if it doesn't exist
        mkdir -p "$BUNDELF_CODE_PATH"
        
        # Create the bundle
        export BUNDELF_BINARIES="bash"
        
        echo "Creating bash bundle in $BUNDELF_CODE_PATH..."
        $BUNDELF_PATH/make-bundelf-bundle.sh --bundle || exit 1
        ;;

    verify)
        echo "Phase: Verifying bundle..."
        
        # List bundle contents for debugging
        find "$BUNDELF_CODE_PATH" -type f

        # 1. Verify bundle structure
        verify_bundle_structure "bash" "$BUNDELF_MERGE_BINDIRS"

        # 2. Test basic bash functionality
        verify_bundle_execution "bash" "--help" "bash home page" "$BUNDELF_MERGE_BINDIRS"
        # verify_bundle_execution "bash" "echo test" "test" "$BUNDELF_MERGE_BINDIRS"

        # 3. Test bash applet functionality
        # verify_bundle_execution "bash" "true" "" "$BUNDELF_MERGE_BINDIRS"

        # rel_path=$(find_binary_path "bash" "$BUNDELF_MERGE_BINDIRS") || exit 1
        # binary_path="$BUNDELF_CODE_PATH/$rel_path"

        # 4. Test error handling: run invalid command (should fail with error message)
        # assert "invalid command error handling" \
        #     "! $binary_path invalid_command 2>&1 | grep -q 'applet not found'"

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
