# Velo — R25 changes

Base: the `Asspp-AuthFix` snapshot you uploaded (source at R2, plus R3–R24 as
patches embedded in `.github` and `Resources/`).

## What actually changed

### 1. Version identifiers can no longer be shown as version numbers

Root cause: Apple's version-history endpoint returns only opaque build
identifiers (`863927451`). The only trustworthy label is
`CFBundleShortVersionString` inside the signed IPA's `Info.plist`, which costs
a few HTTP Range requests per build. When that lookup had not finished, two
things leaked:

- `StoreDownloadProtocol.historyDisplayVersion` returned the literal string
  `"ID 863927451"`.
- `AppPackageArchive.package(for:)` wrote the sentinel `"Version unverified"`
  into `package.software.version`, which is also the on-disk package directory
  name and the exported file name.

So a row could claim, or a file could be named, something that is not a version.

Now:

- New `VersionLabelStore` actor: an account-independent, on-disk cache of
  `appID + platform + externalVersionID → displayVersion`. A build resolved once
  is displayed instantly forever after, offline included, across accounts and
  storefronts. Platform is part of the key so a tvOS identifier can never paint
  an iOS row.
- `historyDisplayVersion` returns an empty string when it cannot verify a label,
  which the history view already renders as "Version unavailable". It never
  fabricates one.
- `package(for:)` keeps the identifier as an internal handle only.
- A label that is a long all-digits string is rejected even if Apple ever
  supplies it inside `bundleShortVersionString`, because that is an identifier,
  not a version.

### 2. Version history is no longer resolved one build at a time

Each historical build needed two different network costs, and both were paid
strictly in sequence per row:

- signed-asset lookup — cheap, but shares the mutable Apple account cookie jar,
  so it must stay serialized;
- `Info.plist` read — several HTTP Range requests, and completely independent of
  the account.

The second cost now runs concurrently with a bounded window of four, while the
first stays serialized under the existing `AccountDownloadGate`. Already-verified
labels are painted before any request is made (`hydrateCachedLabels()`), so the
list is readable immediately instead of showing "Verifying…" on every row.

### 3. Retries use exponential backoff with jitter, and the budget is larger

- Preparation retries: 2 → 4, delay `min(cap, base·2^n)` with full jitter.
- Byte-transfer retries: 2 → 4, same policy (transfer resumes from the bytes
  already on disk, so a larger budget is safe).
- The previous fixed `retry × 700 ms` meant every client that failed at the same
  moment retried at the same moment — the fastest way to turn a brief Apple
  hiccup into a sustained rejection.
- Cancellation and HTTP 403 / authorization failures are still never retried.

### 4. The build pipeline could not pass its own verification

Root cause: `Resources/AuthFix/build.sh` hardcoded `4.2.7 / 2026110705`, while
`Resources/Velo/verify_release.py` expected `5.7.1 / 2026111206`. Every workflow
papered over this with `sed -i 's/4.2.7/5.7.1/g' build.sh`, and each of the
twenty-four workflows substituted a different number. A run therefore spent the
full build time and then failed at the last metadata check — and any run whose
`sed` did not match (already substituted, or re-run) failed differently.

Now:

- `Configuration/Version.xcconfig` is the only place a version is defined.
  `build.sh` reads it; `verify_release.py` reads it. No workflow rewrites the
  build script.
- The twenty-four near-identical branch workflows are archived under
  `Resources/ArchivedWorkflows/` (GitHub does not execute that path). They only
  ever triggered on their own branch names, so archiving them loses nothing.
- One canonical `.github/workflows/build.yml` builds the three pinned native
  components (FairPlayed helper, KBSync bridge, Unicorn TCI) in **parallel jobs
  on separate runners**, each cached against its own pinned revision, then
  assembles the app. Previously all three ran inline, in series, in one job, so
  wall clock was their sum and any single failure discarded the whole run.

## Verification performed here

Linux has no Xcode, so nothing below is an app build. What was run:

| Check | Result |
|---|---|
| `swiftc -parse` over all 73 Swift files (Swift 6.2) | pass |
| `Resources/Scripts/check.downloads.sh` logic (compiled + executed) | pass |
| `verify_release.py --source-only` | pass |
| `build.yml` YAML parse + job graph | pass |

The two shims used to compile on Linux (`String(localized:)`) exist only in the
verification sandbox and are not part of this project.

Not verified, and cannot be from here: an actual `xcodebuild` run, code
signing, and anything that requires a physical device — login, downloads,
decryption, state restoration.

## Deliberately not done

- **Decryption moved inside the app (#6).** It cannot be done, and not for a
  reason that more engineering would fix. FairPlay ciphertext is decrypted with
  keys derived on-device; obtaining them requires either a jailbroken kernel or
  running the target app under a debugger. Velo's sandbox forbids reading
  another app's memory, and the helper is a *separate signed app* precisely
  because that is the only supported way to host the debugger session. Moving it
  inside Velo would mean either shipping a jailbreak dependency or shipping
  something that labels still-encrypted output as decrypted — the exact thing
  the brief forbids. The current split (Velo downloads → helper decrypts →
  auto-export back to Velo) is the closest supported workflow, and it is
  already automated with one embedded helper.
- **A rewritten UI (#4).** I did not touch the interface beyond the version-row
  state, because I cannot run SwiftUI here and a wide visual rewrite I cannot
  see is a regression risk, not an improvement. Say the word and I will do it in
  a focused pass with a render check.
- **Build-time measurements (#8).** I restructured the pipeline but I have not
  measured it, and inventing "7 minutes" would be worthless to you. Run the
  workflow once; `artifacts/build-timings.txt` records the `xcodebuild` seconds,
  and each job reports its own duration in the Actions UI.

## How to get the IPA

The one thing I cannot do here is produce a signed or even unsigned `.ipa`:
that requires Xcode on macOS. Both paths are ready:

1. **GitHub Actions** — push this project to a repo, then Actions → *Velo build
   (unsigned IPA)* → Run workflow. It uploads `Velo-5.7.1-unsigned.ipa` plus its
   SHA-256 and `build-info.json`. That is an unsigned IPA: sign it with lcsign
   using your own certificate before installing.
2. **Your own Mac** — `bash Resources/AuthFix/build.sh` after exporting
   `R3_KBSYNC_ARCHIVE` and `R6_TCI_ARCHIVE` (the workflow shows exactly how both
   are produced).

## Remaining limitations

- `authenticationOnDevice` is still untested. R2's README says the same thing;
  I have no device and no Apple account, so I am not going to claim otherwise.
- The concurrency and retry changes are covered by the checks in
  `Resources/Tests/DownloadProtocolChecks.swift`, but their behaviour against a
  real flaky network can only be observed on hardware.
