# R19: FairPlayed inside Asspp — experimental

The user requested analysis of the working FairPlayed implementation and an
actual in-process attempt. This branch preserves R18 and the proven externally
signed helper; it does not claim that moving the engine removes iOS policy.

## Source findings

Pinned upstream: `morzelowski/FairPlayed` at
`bad7df138839b5e0ac8b9f20cc4689140b8436fb`.

1. `fpcore.c:fp_attempt` maps the original encrypted file read-only and invokes
   `mremap_encrypted(..., cryptid=2, cputype, cpusubtype)`. It reads remapped pages
   through `vm_read_overwrite`, so a failed page-in is a kernel error instead of
   an unsafe direct access. It does not need to launch the downloaded app.
2. The core checks syscall success, all pages, changed bytes, entropy and arm64
   instruction evidence. We retain the R9 tightly scoped one-page stub exception
   already used in the working helper. Merely changing `cryptid` is not decryption.
3. `main.m:resolveBundleID:` already attempts an installed-bundle source. This
   branch resolves only the selected bundle ID and never enumerates installed apps.
4. The upstream README documents that fairplayd reads installed bundles but is
   blocked from app data containers; SINF lookup depends on the original path.
   This means a normal downloaded IPA is expected to fail even with the core linked.
5. Apple's XNU `osfmk/vm/vm_map.c:vm_map_apple_protected` confirms that cryptid=2
   skips the executable-map check. It does not establish that file/license access
   from a data container is permitted. Reusing Asspp's signing certificate does
   not change the origin or permissions of downloaded files.

Sources:
- https://github.com/morzelowski/FairPlayed/tree/bad7df138839b5e0ac8b9f20cc4689140b8436fb
- https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/vm/vm_map.c

## Experiment

`Try Direct Decrypt` runs off the UI thread and serializes native operations.
It extracts a disposable copy, verifies every Mach-O, and tries:

- The selected installed bundle, only if its app ID, version/build and complete
  original binary SHA-256 match the download and the sandbox permits reading.
- The staged downloaded file, retaining the working helper's SINF replication.

Only READ/cryptid=2 attempts are enabled. There is no executable mapping, JIT,
entitlement workaround, mutation of a signed installed bundle or automatic signing.
The original download is never written. Watch companions are excluded, matching
the working iPhone helper. Unsupported/32-bit binaries and encrypted slices over
64 MiB are rejected rather than silently skipped. Linked archive paths/symlinks,
overlapping/malformed slices and oversized archives are rejected.

An IPA is shared only after every encrypted slice passes the retained core checks,
the whole output payload has cryptid=0, and the generated ZIP passes CRC checks.
Failure deletes the disposable output; there is no PARTIAL IPA. A local diagnostic
report records source categories, errno, remap and page results, without private
absolute paths, account identifiers, SINF contents or credentials.

## Validation and limits

CI runs native tests with ASan/UBSan: plaintext copy, source/destination protection,
missing-license fail-closed behavior, malformed command/FAT/range cases, 1200
deterministic input mutations, symlink rejection and the executable-mode guard.
It compiles/links the real arm64 core and checks its exports in the final Asspp.
It preserves the R18 download improvements and working helper template.

**CI cannot validate successful FairPlay decryption on a physical iPhone.**
This build is explicitly experimental. The device must allow the original source
and license access and satisfy the app's existing App Store license requirements.
If iOS denies both source paths, this engine integration alone does not solve it;
the working helper remains the fallback. Decrypted output is unsigned.
