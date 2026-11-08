# R18 — faster download preparation and search-row downloads

Includes R17's removal of internal signing. It does not introduce direct
decryption of newly downloaded IPAs inside the installed Asspp bundle.

## Download preparation

- Prepares the first eligible account in memory while Accounts/Search is visible.
- Changing the account on the product page prepares that account too.
- Coalesces warm-up and real download preparation for the same account/hardware.
- Runs catalog metadata lookup and KBSync preparation concurrently.
- Reuses a credential-free ephemeral URLSession for TLS connection reuse. Apple
  tokens and cookies are explicitly scoped per request; redirects stay blocked.
- Serializes cold native emulator generations across accounts, with a cache
  recheck after acquiring the engine lock, to avoid duplicate heavy work.
- Coalesces identical download requests from separate entry points.
- Logs elapsed metadata time without credentials, blobs or signed asset URLs.

The interpreter still has a cold-start cost. Warm-up shifts that cost earlier;
this is not a promise of a particular speedup. Apple/CDN/network speeds are
outside this change. No background task entitlement or JIT capability is added.

## Search-row button

Each search result keeps its details link and gains a separate **Get** control.
One eligible account starts the request immediately. Multiple accounts show a
compact chooser; no eligible account shows an actionable explanation. Once
queued, the control opens the download. Missing licenses for free apps require
explicit confirmation; the button never purchases a paid app automatically.

## Validation

The workflow compiles/runs standalone Swift concurrency checks for coalescing,
account isolation and retry after failure, then builds the actual iOS app and
verifies the IPA, retained download engine, helper template and absent signer.
Actual delay reduction must be measured on the user's iPhone.
