#!/bin/bash

# Test 07: Simple Git Test with helper tools
# ------------------------------------------
# Bundles and verifies git and required off-PATH helper binaries.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TEST_NAME="simple-git"
BUNDLE_NAME="git"
PRIMARY_BIN="git"

# Set final bundle path before sourcing utils
export BUNDELF_CODE_PATH="${BUNDELF_BUNDLES_PATH}/${BUNDLE_NAME}"

source "$SCRIPT_DIR/../common/test-utils.sh"

# Initialize test environment (with validation)
init_test_env

# Enumerate common helper tools locations
_git_helpers_list() {
  # Alpine places in /usr/libexec/git-core, Debian in /usr/lib/git-core.
  local paths=(/usr/libexec/git-core /usr/lib/git-core)
  for p in "${paths[@]}"; do
    if [ -d "$p" ]; then
      find "$p" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null || ls -1 "$p" 2>/dev/null
      return 0
    fi
  done
  return 1
}

case "${TEST_PHASE:-build}" in
    build)
        echo "Phase: Building bundle..."
        
        # Install required packages for bundle creation
        if command -v apk >/dev/null; then
            apk add --no-cache git
        elif command -v apt-get >/dev/null; then
            apt-get update && apt-get install -y git
        else
            echo "Unsupported package manager"
            exit 1
        fi

        # Create bundle directory if it doesn't exist
        mkdir -p "$BUNDELF_CODE_PATH"
        
        # # Build the list of helper binaries to include explicitly
        # helpers=$(_git_helpers_list || true)
        # if [ -z "$helpers" ]; then
        #   echo "Warning: could not discover git-core helpers; proceeding with git only"
        #   export BUNDELF_BINARIES="$PRIMARY_BIN"
        # else
        #   # Pick existing helper directory
        #   if [ -d /usr/libexec/git-core ]; then helper_dir=/usr/libexec/git-core; else helper_dir=/usr/lib/git-core; fi
        #   # Compose BUNDELF_BINARIES as space-separated list: git plus helpers by absolute path
        #   BIN_LIST="$PRIMARY_BIN"
        #   for h in $helpers; do
        #     BIN_LIST+=" $helper_dir/$h"
        #   done
        #   export BUNDELF_BINARIES="$BIN_LIST"
        # fi
        
        export BUNDELF_BINARIES="git"
        export BUNDELF_DYNAMIC_PATHS="/usr/libexec/git-core /usr/lib/git-core"

        echo "Creating $PRIMARY_BIN bundle in $BUNDELF_CODE_PATH..."
        bash $BUNDELF_PATH/make-bundelf-bundle.sh --bundle || exit 1
        ;;

    verify)
        echo "Phase: Verifying bundle..."
        
        # List bundle contents for debugging
        find "$BUNDELF_CODE_PATH" -type f

        # 1. Verify bundle structure
        verify_bundle_structure "$PRIMARY_BIN" "$BUNDELF_MERGE_BINDIRS"

        # 2. Test basic git functionality
        verify_bundle_execution "$PRIMARY_BIN" "--version" "git version" "$BUNDELF_MERGE_BINDIRS"

        # 3. Run a tiny repo init + commit to force helper use (hash/object helpers)
        rel_path=$(find_binary_path "$PRIMARY_BIN" "$BUNDELF_MERGE_BINDIRS") || exit 1
        git_bin="$BUNDELF_CODE_PATH/$rel_path"
        tmpd=$(mktemp -d)
        pushd "$tmpd" >/dev/null
        TESTS_TOTAL=$((TESTS_TOTAL + 1)); echo -n "Testing git init and commit ... "
        if "$git_bin" init -q \
           && echo ok > f.txt \
           && "$git_bin" add f.txt \
           && GIT_AUTHOR_NAME=a GIT_AUTHOR_EMAIL=a@a GIT_COMMITTER_NAME=a GIT_COMMITTER_EMAIL=a@a "$git_bin" commit -qm msg; then
          echo -e "${GREEN}PASS${NC}"; TESTS_PASSED=$((TESTS_PASSED + 1));
        else
          echo -e "${RED}FAIL${NC}"; TESTS_FAILED=$((TESTS_FAILED + 1));
        fi
        popd >/dev/null
        rm -rf "$tmpd"

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
