# STATUS

Current line: R25 (based on the uploaded Asspp-AuthFix snapshot: source at R2,
R3–R24 present as patches in `Resources/`).

## Version
`Configuration/Version.xcconfig` → 5.7.1 (2026111206). This is now the only
place a version is defined; `Resources/AuthFix/build.sh` and
`Resources/Velo/verify_release.py` both read it. Do not reintroduce `sed`
version rewriting in workflows.

## Changed this round
- `Asspp/Backend/AppStore/VersionLabelStore.swift` — new: cross-account cache
  mapping Apple build identifiers to verified version strings.
- `Asspp/Backend/AppStore/AppPackageArchive.swift` — cached hydration, bounded
  concurrent label resolution, no `"Version unverified"` sentinel, no identifier
  rendered as a version.
- `Asspp/Backend/AppStore/StoreDownloadProtocol.swift` — jittered exponential
  backoff, retry budget 2 → 4, `historyDisplayVersion` never fabricates a label.
- `Asspp/Backend/Downloader/Downloads.swift` — transfer retries use the shared
  backoff policy instead of `retry × 700 ms`.
- `Asspp/Interface/Search/ProductHistoryView.swift` — paints cached labels before
  network work.
- `.github/workflows/build.yml` — new canonical pipeline, three native builds in
  parallel with per-component caches.
- 22 branch workflows archived to `Resources/ArchivedWorkflows/` (inert there).

## Already ruled out (do not re-investigate)
- Version history displayed identifiers: that was the sentinel/`"ID "` path, now
  closed. If identifiers reappear, check `VersionLabelStore.looksLikeBuildIdentifier`
  and `historyDisplayVersion`.
- Pipeline failing after a long build: was a version mismatch between `build.sh`
  and `verify_release.py`. Now single-sourced.

## Open / needs a device
- `authenticationOnDevice` unverified.
- In-app decryption (#6): not implementable in Velo's sandbox — see report.
- UI rewrite (#4): not started.
