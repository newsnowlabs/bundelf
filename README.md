# BundELF - all the benefits of statically-compiled binaries, without the faff

## What is BundELF?

BundELF (pron. 'Bundle-f') is a Linux ELF dynamically-linked binary executable patcher and bundler. It creates distribution-independent executable package bundles, for any tool, utility, or application. Its bundled packages, consisting of patched binaries and dynamic libraries, provide much the same benefits as statically-compiled binaries but without the recompilation faff.

Compared to statically-compiled binaries, BundELF-generated binaries make a much simpler and more generalised alternative, because statically-compiled binaries:
1. are not always (or even often) readily available;
2. can be hard and costly to compile manually;
3. cannot be generated for certain applications and tools which inherently rely on being able to load dynamic libaries.

By contrast, BundELF can patch and bundle _any_ pre-existing ELF binary -- tool, utility or application -- along with its dynamic (shared or non-shared) library dependencies, for relocation to (and execution from) any chosen filesystem location, making them completely portable and independent of the sourde distribution, much like statically-compiled binaries.

## Why use BundELF?

BundELF use cases:
- Bundling Alpine binaries for running within, but completely independently of, any arbitrary distribution (including GLIBC-based distributions)
- Bundling GLIBC-based applications for running within Alpine (or indeed any other distribution)

BundELF is a core technology component of:
- https://github.com/newsnowlabs/dockside -- to allow running complex Node-based IDE applications and container-setup processes inside containers running an unknown arbitrary Linux distribution
- https://github.com/newsnowlabs/runcvm -- to allow running QEMU, virtiofsd, dnsmasq and other tools inside a container (and indeed a VM) running an unknown arbitrary Linux distribution

## Types of BundELF bundle

BundELF can create bundles with either relative or absolute dynamic library paths:
- absolute library paths require the execution filesystem path to be predefined, but support hard-linked binaries and libraries;
- relative library paths allow the bundle to be copied or mounted to any desired filesystem path, and binaries may still be executed by prefacing the call with the source distribution's dynamic linker/interpreter (which BundELF helpfully packages in).

Relative library paths are the most flexible, so this is the default.

## How does BundELF work?

In short, BundELF works by modifying the interpreter RPATH records inside the ELF headers of your needed binaries and their dynamic library dependendies. This avoid the need to set the `LD_LIBRARY_PATH` to override the linker's search path as well as issues that can arise when using that approach.

In practice, the process is a little more involved. Here's what BundELF does:

1. Copy your needed binary executables to the bundle location. If fully-qualified filepaths are given, they will be used, otherwise the binary will be located on the `PATH` using `which`.
2. Copy any specifically needed application folders (e.g. Node apps) to the bundle location, and scan them for any contained executable binaries or dynamic libraries.
3. Detect the dynamic library dependencies of each binary.
4. Scan any specifically-needed extra dynamic library folders for additional libraries to bundle.
5. Copy all needed dynamic libraries (dependencies plus extras specified) to the bundle location.
6. Generate a comprehensive set of 'system' library paths for the bundle, adding any specifically-needed extra extra library paths.
7. Detect the dynamic linker (e.g. `/lib/ld-musl-x86_64.so.1` or `/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2`), copy it to the bundle and patch all bundled binaries to use it.
8. Generate a suitable absolute or relative library path (`RPATH`) and patch (using [`patchelf`](https://github.com/droidian/patchelf)) all bundled binaries and dynamic libraries to use it.
9. Test every bundled binary and dynamic library to check that the linker's resolution of dynamic library dependencies will _only_ use files from inside the bundle, and not inadvertently (due to bug or misconfiguration) attempt to load any libraries from the source system.

N.B. `BUNDELF_CODE_PATH` can be different to `BUNDELF_EXEC_PATH`, to allow for
     mounting the former at `BUNDELF_EXEC_PATH`.

### Inputs

BundELF is controlled through the following environment variables:

- `BUNDELF_CODE_PATH` - [mandatory] the bundle location, a path where binaries and libraries will be copied to e.g. `/opt/bundle/mybundle`.
- `BUNDELF_EXEC_PATH` - [optional] the path where binaries and libraries will be _executed from_ (defaults to `BUNDELF_CODE_PATH`) - useful where you are building the bundle at a one location and intend to copy or mount it at another location ()`BUNDELF_EXEC_PATH`) before executing.
- `BUNDELF_BINARIES` - [optional] list of specific binaries to be scanned and copied e.g. `"busybox ip bash /path/to/myapp"`
- `BUNDELF_DYNAMIC_PATHS` - [optional] list optional additional paths (e.g. Node application trees) to be scanned and copied e.g. `/usr/src/myapp`
- `BUNDELF_EXTRA_LIBS` - [optional] list extra library paths to be scanned and copied (e.g. `/usr/lib/xtables /usr/libexec/coreutils /usr/lib/qemu/*.so`)
= `BUNDELF_MERGE_BINDIRS` - [optional] set to non-empty, makes specified binaries be copied to `$BUNDELF_CODE_PATH/bin`
- `BUNDELF_LIBPATH_TYPE` - [optional] set to `absolute` or `relative` (the default) to determine how ELF RPATHs are calculated
- `BUNDELF_NODE_PATH` - [optional] path to the node binary, if required to ensure ldd can resolve all library paths in `.node` files
- `BUNDELF_EXTRA_SYSTEM_LIB_PATHS` - [optional] list of extra system library paths to be added to the RPATH

N.B. At least one of `BUNDELF_BINARIES` or `BUNDELF_DYNAMIC_PATHS` must be provided.

## Examples

```
BUNDELF_BINARIES="node busybox curl bash git /usr/libexec/git-core/git /usr/libexec/git-core/" \
BUNDELF_CODE_PATH="/opt/bundelf/myappbundle" \
make-bundelf-bundle.sh --bundle
```

## See also

- [Linux dynamic linker](https://en.wikipedia.org/wiki/Dynamic_linker)
- [ld.so(8) — Linux manual page](https://man7.org/linux/man-pages/man8/ld.so.8.html)
- [Shared Library (Wikipedia)](https://en.wikipedia.org/wiki/Shared_library)
- [Dynamic Libraries (IBM)](https://developer.ibm.com/tutorials/l-dynamic-libraries/)
