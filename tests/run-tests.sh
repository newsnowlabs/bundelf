#!/bin/bash

# Main test runner for BundELF tests
# --------------------------------

# Source common test utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common/test-utils.sh"

# Check for required tools and Docker capabilities
check_requirements() {
    local missing=""
    for cmd in docker realpath dirname find; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done
    
    if [ -n "$missing" ]; then
        echo "Error: Required commands not found:$missing"
        exit 1
    fi
    
    # Ensure docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        echo "Error: Docker daemon is not running"
        exit 1
    fi

    # Verify Docker volume support
    echo "Verifying Docker volume support..."
    local test_volume="bundelf-test-volume"
    if ! docker volume create "$test_volume" >/dev/null 2>&1; then
        echo "Error: Failed to create Docker volume"
        exit 1
    fi
    docker volume rm "$test_volume" >/dev/null 2>&1
}

# Create test workspace
TEST_WORKSPACE="/tmp/bundelf-test"
mkdir -p "$TEST_WORKSPACE"

# Run requirement checks
check_requirements

# Default test matrix parameters
TEST_PATTERN="*.sh" # Default to all tests
DISTRIBUTIONS=("alpine:latest" "debian:stable-slim")
ARCHITECTURES=("amd64" "arm64")
MERGE_BINDIRS=("" "1")
LIBPATH_TYPES=("relative" "absolute")

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dist=*)
            DISTRIBUTIONS=(${1#*=})
            ;;
        --arch=*)
            ARCHITECTURES=(${1#*=})
            ;;
        --test=*)
            TEST_PATTERN=${1#*=}
            ;;
        *)
            echo "Unknown parameter: $1"
            exit 1
            ;;
    esac
    shift
done

# Create results directory with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="$SCRIPT_DIR/test-results/$TIMESTAMP"
mkdir -p "$RESULTS_DIR/logs"

# For storing test results [unimplemented]
# mkdir -p "$RESULTS_DIR/bundles"

# Global counters for container-level results
CONTAINER_BUILD_ATTEMPTS=0
CONTAINER_BUILD_SUCCESSES=0
CONTAINER_RUN_ATTEMPTS=0
CONTAINER_RUN_SUCCESSES=0
# Independent test counter (number of high-level test configurations executed)
TESTS_TOTAL=0

excerpt_log() {
    local log_file="$1"

    tail -n 10 "$log_file" | sed 's/^/ > /'
}

# Function to handle the build phase
_run_build_phase() {
    local build_dist=$1
    local arch=$2
    local merge_bindirs=$3
    local libpath_type=$4
    local build_config=$5
    local bundle_volume=$6
    local docker_dir=$7
    local build_log=$8

    echo "Building bundles for test pattern '$TEST_PATTERN' and configuration: $build_config ..."

    # Create build container with package installation support
    mkdir -p "$docker_dir"

    cat > "$docker_dir/Dockerfile" << EOF
FROM $build_dist
RUN if command -v apk >/dev/null; then \
        apk add --no-cache bash file patchelf hexdump; \
    elif command -v apt-get >/dev/null; then \
        apt-get update && \
        apt-get install -y file patchelf bsdextrautils; \
    fi
WORKDIR /tests
EOF

    # Build the bundle creation container image
    echo -n "Building container image for bundle creation ... "
    CONTAINER_BUILD_ATTEMPTS=$((CONTAINER_BUILD_ATTEMPTS + 1))
    if ! docker build --platform "linux/$arch" -t "bundelf-build:$build_config" --progress=plain "$docker_dir" >>"$build_log" 2>&1; then
        echo -e "${RED}Failed to build container image${NC}"
        echo "See log file: $build_log"
        excerpt_log "$build_log"
        return 1
    else
        CONTAINER_BUILD_SUCCESSES=$((CONTAINER_BUILD_SUCCESSES + 1))
        echo -e "${GREEN}✓ Image built${NC}"
    fi

    # Find and run all test scripts in build mode
    local build_failed=0
    for test_script in $(find "$SCRIPT_DIR/integration" -name "${TEST_PATTERN:-*.sh}" | sort); do
        echo -n "Creating bundle: $(basename "$test_script") ... "

        # Run test script in build mode
        CONTAINER_RUN_ATTEMPTS=$((CONTAINER_RUN_ATTEMPTS + 1))
        if docker run --rm --platform "linux/$arch" \
            -v "$SCRIPT_DIR:/tests/:ro" \
            -v "$(dirname "$SCRIPT_DIR"):/bundelf:ro" \
            -v "$bundle_volume:/bundles" \
            -e TEST_PHASE=build \
            -e BUNDELF_PATH="/bundelf" \
            -e BUNDELF_MERGE_BINDIRS="$merge_bindirs" \
            -e BUNDELF_LIBPATH_TYPE="$libpath_type" \
            -e BUNDELF_BUNDLES_PATH="/bundles" \
            -e DIST="$build_dist" \
            -e ARCH="$arch" \
            "bundelf-build:$build_config" \
            bash "/tests/integration/$(basename "$test_script")" >>"$build_log" 2>&1; then
            CONTAINER_RUN_SUCCESSES=$((CONTAINER_RUN_SUCCESSES + 1))
            echo -e "${GREEN}✓ Bundle created${NC}"
        else
            echo -e "${RED}✗ Bundle creation failed${NC}"
            echo "Reproduce build container with: docker run --rm -it --platform linux/$arch -v $SCRIPT_DIR:/tests/:ro -v $(dirname "$SCRIPT_DIR"):/bundelf:ro -v $bundle_volume:/bundles -e TEST_PHASE=build -e BUNDELF_PATH=/bundelf -e BUNDELF_MERGE_BINDIRS=$merge_bindirs -e BUNDELF_LIBPATH_TYPE=$libpath_type -e BUNDELF_BUNDLES_PATH=/bundles -e DIST=$build_dist -e ARCH=$arch bundelf-build:$build_config bash"
            echo "See log file: $build_log"
            excerpt_log "$build_log"
            build_failed=1
            break
        fi
    done

    return $build_failed
}

# Function to handle the verify phase
_run_verify_phase() {
    local arch=$1
    local merge_bindirs=$2
    local libpath_type=$3
    local build_config=$4
    local bundle_volume=$5
    local docker_dir=$6
    local build_log=$7

    # Test the bundles on all supported distributions
    for test_dist in "${DISTRIBUTIONS[@]}"; do
        local test_config="${test_dist//:/}"
        local test_log="$RESULTS_DIR/logs/$CONTAINER_RUN_ATTEMPTS-$build_config-test-on-$test_config.log"

        echo -n "Building container image for bundle tests (from $test_dist) ... "

        # Create minimal test container image
        cat > "$docker_dir/Dockerfile.test" << EOF
FROM $test_dist
RUN if command -v apk >/dev/null; then \
        apk add --no-cache bash; \
    elif command -v apt-get >/dev/null; then \
        apt-get update && \
        apt-get install -y bash; \
    fi
WORKDIR /tests
EOF

        # Build test container image
        CONTAINER_BUILD_ATTEMPTS=$((CONTAINER_BUILD_ATTEMPTS + 1))
        if ! docker build -f "$docker_dir/Dockerfile.test" --platform "linux/$arch" \
            -t "bundelf-test:$test_config" --progress=plain \
            "$docker_dir" >>"$test_log" 2>&1; then
            echo -e "${RED}Failed to build test container image${NC}"
            echo "See log file: $test_log"
            excerpt_log "$test_log"
            return 1
        else
            CONTAINER_BUILD_SUCCESSES=$((CONTAINER_BUILD_SUCCESSES + 1))
            echo -e "${GREEN}✓ Image built${NC}"
        fi

        # Run tests in verification mode
        local verify_failed=0
        for test_script in $(find "$SCRIPT_DIR/integration" -name "${TEST_PATTERN:-*.sh}" | sort); do
            echo -n "Testing bundle $(basename "$test_script") on $test_dist ... "

            CONTAINER_RUN_ATTEMPTS=$((CONTAINER_RUN_ATTEMPTS + 1))
            if docker run --rm --platform "linux/$arch" \
                -v "$SCRIPT_DIR:/tests/:ro" \
                -v "$bundle_volume:/bundles:ro" \
                -e TEST_PHASE=verify \
                -e BUNDELF_MERGE_BINDIRS="$merge_bindirs" \
                -e BUNDELF_LIBPATH_TYPE="$libpath_type" \
                -e BUNDELF_BUNDLES_PATH="/bundles" \
                -e DIST="$test_dist" \
                -e ARCH="$arch" \
                "bundelf-test:$test_config" \
                bash "/tests/integration/$(basename "$test_script")" >>"$test_log" 2>&1; then
                CONTAINER_RUN_SUCCESSES=$((CONTAINER_RUN_SUCCESSES + 1))
                echo -e "${GREEN}✓ Test passed${NC}"
            else
                echo -e "${RED}✗ Test failed on $test_dist${NC}"
                echo "Reproduce test container with : docker run --rm -it --platform linux/$arch -v $SCRIPT_DIR:/tests/:ro -v $bundle_volume:/bundles:ro -e TEST_PHASE=verify -e BUNDELF_MERGE_BINDIRS=$merge_bindirs -e BUNDELF_LIBPATH_TYPE=$libpath_type -e BUNDELF_BUNDLES_PATH=/bundles -e DIST=$test_dist -e ARCH=$arch bundelf-test:$test_config bash"
                echo "See log file: $test_log"
                excerpt_log "$test_log"
                verify_failed=1
                break
            fi
        done

        if [ $verify_failed -eq 1 ]; then
            return 1
        fi
    done

    return $verify_failed
}

# Internal function to run the actual build and test phases
_run_integration_tests() {
    local build_dist=$1
    local arch=$2
    local merge_bindirs=$3
    local libpath_type=$4
    local build_config=$5
    local bundle_volume=$6
    local docker_dir=$7
    local build_log=$8

    # Run build phase
    _run_build_phase "$build_dist" "$arch" "$merge_bindirs" "$libpath_type" \
        "$build_config" "$bundle_volume" "$docker_dir" "$build_log"
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Run verify phase
    _run_verify_phase "$arch" "$merge_bindirs" "$libpath_type" \
        "$build_config" "$bundle_volume" "$docker_dir" "$build_log"
}

# Wrapper function to handle volume creation/cleanup and call _run_integration_tests
run_integration_tests() {
    local dist=$1
    local arch=$2
    local merge_bindirs=$3
    local libpath_type=$4
    
    # Generate configuration variables
    local build_config="${dist//:/}-${arch}-${merge_bindirs:-no}mergebin-${libpath_type}"
    local build_log="$RESULTS_DIR/logs/$CONTAINER_BUILD_ATTEMPTS-$build_config-build.log"
    local bundle_volume="bundelf-bundles-$build_config"
    local docker_dir="$TEST_WORKSPACE/docker/$build_config"

    # Increment independent test counter and log start
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo "--- TEST #$TESTS_TOTAL START ---"
    echo "Testing with config: build_dist=$dist; arch=$arch; merge_bindirs=${merge_bindirs:-no}; libpath_type=$libpath_type"

    # Create docker volume for sharing bundles
    echo "Creating bundle volume: $bundle_volume"
    docker volume create "$bundle_volume" >>"$build_log" 2>&1
    
    # Run the tests and capture exit code
    _run_integration_tests "$dist" "$arch" "$merge_bindirs" "$libpath_type" \
        "$build_config" "$bundle_volume" "$docker_dir" "$build_log"
    local exit_code=$?
    
    # Clean up volume
    echo "Cleaning up volume: $bundle_volume"
    docker volume rm "$bundle_volume" >/dev/null 2>&1

    echo "RESULT: $( [ $exit_code -eq 0 ] && echo -e "${GREEN}✓ PASS${NC}" || echo -e "${RED}✗ FAIL${NC}" )"

    echo "--- TEST #$TESTS_TOTAL END ---"

    return $exit_code
}

print_summary() {
    local exitcode=$?

    # Clear signal handlers, so they don't run again
    # Clear EXIT as we're in this signal handler
    trap '' EXIT INT QUIT TERM

    # Print container-level summary before exit
    echo
    echo "Test Summary:"
    echo "-------------"
    echo "Tests executed:      $TESTS_TOTAL"
    echo "Build attempts:      $CONTAINER_BUILD_ATTEMPTS"
    echo "Build successes:     $CONTAINER_BUILD_SUCCESSES"
    echo "Run attempts:        $CONTAINER_RUN_ATTEMPTS"
    echo "Run successes:       $CONTAINER_RUN_SUCCESSES"
    echo "Exit code:           $exitcode"

    # Create summary report matching echoed output
    cat > "$RESULTS_DIR/report.json" << EOF
{
    "tests_executed": $TESTS_TOTAL,
    "build_attempts": $CONTAINER_BUILD_ATTEMPTS,
    "build_successes": $CONTAINER_BUILD_SUCCESSES,
    "run_attempts": $CONTAINER_RUN_ATTEMPTS,
    "run_successes": $CONTAINER_RUN_SUCCESSES,
    "exit_code": $exitcode
}
EOF

    return $exitcode
}

echo "Starting BundELF integration tests..."
echo "Results will be stored in: $RESULTS_DIR"
echo "Test pattern: ${TEST_PATTERN:-all tests}"

trap print_summary EXIT # INT QUIT TERM

# Main test execution loop
for build_dist in "${DISTRIBUTIONS[@]}"; do
    for arch in "${ARCHITECTURES[@]}"; do
        for merge_bindirs in "${MERGE_BINDIRS[@]}"; do
            for libpath_type in "${LIBPATH_TYPES[@]}"; do
                run_integration_tests "$build_dist" "$arch" "$merge_bindirs" "$libpath_type"
            done
        done
    done
done
