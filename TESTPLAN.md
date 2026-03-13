# BundELF Test Plan

## Test Structure

### 1. Test Matrix Parameters
1. Distributions: Alpine, Debian
   - Use docker + qemu-user-static for non-native architecture testing:
     Note: docker + qemu-user-static is not used to test cross-architecture compatibility (bundelf doesn't create cross-platform bundles, although there's no reason why they shouldn't work), but rather to:
     1. Create bundles of non-native architecture packages in their native environment
     2. Test-run those bundles in their native environment
     3. Verify the bundle creation and execution process works correctly across architecturestions: Alpine, Debian
2. Architectures: amd64, arm64 
3. BUNDELF_MERGE_BINDIRS: "", "1"
4. BUNDELF_LIBPATH_TYPE: "relative", "absolute"

Total combinations: 2 × 2 × 2 × 2 = 16 test configurations

### 2. Directory Structure
```
tests/
├── common/
│   ├── test-utils.sh       # Common test functions and utilities
│   └── test-cases/         # Shared test case definitions
├── fixtures/               # Test binaries and expected outputs
├── integration/            # Integration test scripts
│   ├── alpine/            # Alpine-specific tests
│   └── debian/            # Debian-specific tests
└── run-tests.sh           # Main test runner

tests/integration/
├── 01-simple-busybox.sh        # Single binary, minimal dependencies
├── 02-nodejs-native.sh         # More complex case with native modules
└── 03-cross-bundle.sh          # Create in Alpine, run in Debian (and vice versa)
```

### 3. Package Complexity Levels

a) Simple (minimal dependencies):
   1. busybox
   2. coreutils individual commands (ls, cp, etc)
   3. simple C utilities (htop, tree)

b) Moderate:
   1. bash (with readline/ncurses)
   2. curl (with SSL libraries)
   3. git (core commands)

c) Complex:
   1. nodejs (with native modules)
   2. python (with pip packages)
   3. git (full installation including all commands)

## Verification Points

### Core Verification (in make-bundelf-bundle.sh)

1. Current --verify checks:
   1.1. All dynamic library dependencies resolve to bundled versions
   1.2. No external library dependencies

2. Additional core verifications to consider adding:
   2.1. Verify interpreter path is correctly set in all ELF binaries
   2.2. Verify RPATH settings match expected patterns for relative/absolute mode
   2.3. Check for broken symlinks within the bundle

### Test-specific Verification (in test harness)

1. Build-time Verification:
   1.1. Bundle creation succeeds (exit code)
   1.2. No unexpected warnings/errors in build logs
   1.3. Temporary files are cleaned up

2. Structure Verification:
   2.1. When BUNDELF_MERGE_BINDIRS=1, binaries are in bin/
   2.2. When BUNDELF_MERGE_BINDIRS="", original paths preserved
   2.3. Expected files/directories exist
   2.4. Hard/symbolic link handling matches BUNDELF_LIBPATH_TYPE setting:
        Note: While "Verify RPATH settings" checks the RPATH values themselves, this verification point ensures the physical file structure matches the expected pattern:
        2.4.1. For relative mode: no hard links or symlinks should remain (all replaced with copies)
        2.4.2. For absolute mode: hard links and symlinks should be preserved

3. Cross-distribution Testing:
   3.1. Bundle from Alpine runs in Debian (and vice versa)
   3.2. Bundle works when moved to different paths
   3.3. Bundle works with different BUNDELF_EXEC_PATH values

4. Runtime Verification:
   4.1. Each bundled binary executes successfully
   4.2. Basic functionality tests (e.g., busybox ls works)
   4.3. Complex functionality tests (e.g., nodejs loads native modules)
   4.4. No unexpected file access outside bundle, verified by:
        4.4.1. Using strace to monitor file system calls related to library opens only
        4.4.2. Running in a confined container with minimal mounts
        4.4.3. Using filesystem auditing (e.g., auditd) to track file accesses related to library opens only (if this adds value over strace)
        4.4.4. Checking file access patterns match intended absolute and relative path modes (if there's indeed something that can be seen from strace/auditd here)

5. Edge Cases:
   5.1. Bundle works with spaces in paths
   5.2. Bundle works with non-ASCII characters
   5.3. Bundle works with minimal permissions
   5.4. Bundle works with read-only filesystem (when appropriate)
   5.5. Network isolation doesn't break functionality

## Test Implementation

### Matrix Runner Configuration
```bash
# distributions.conf
DISTRIBUTIONS=("alpine:latest" "debian:stable-slim")
ARCHITECTURES=("amd64" "arm64")
MERGE_BINDIRS=("" "1")
LIBPATH_TYPES=("relative" "absolute")

# Package groups for testing
PACKAGE_GROUPS=(
    "simple:busybox"
    "simple:coreutils"
    "moderate:bash,curl"
    "complex:nodejs,git"
)
```

### Test Results Organization
```
test-results/
├── $DATE/
│   ├── logs/
│   │   ├── $TEST_COMBINATION.log
│   │   └── ...
│   ├── bundles/
│   │   ├── $TEST_COMBINATION/
│   │   └── ...
│   └── report.json
```

## Notes

1. Regular users rely on built-in verification (make-bundelf-bundle.sh --verify)
2. Test suite provides additional comprehensive verification
3. Core functionality remains focused and efficient
4. Edge cases are properly tested but don't slow down normal use
5. Test suite can run in CI/CD environments