# R4 download diagnostics (iOS)

R4 is an experimental follow-up to R3. It preserves R3 on the
`r3-kbsync-experiment` branch and adds **safe, fixed-stage** logging for
the preferred Apple Store `ent/download` transport.

## Important distinction

The **Request Download** action and **Version History** use different APIs.
In the initial R4 build, the preferred KBSync transport is attempted only
for **Request Download**. The legacy Version History endpoint may still
return HTTP 403; a 403 from that screen does not by itself test KBSync.

## How to test

1. Sign the unsigned R4 IPA yourself and install it on the test iPhone.
2. Use a dedicated Apple Account already signed in within Asspp.
3. Select an owned/free app in the correct App Store region, tap
   **Request Download**, and wait for the request to finish.
4. Open **Settings > Logs** and find the latest
   `Store download [XXXXXXXX]: kbsync status=...` line.
5. Share only the stage code, the `ent/download HTTP` status if present,
   and whether an IPA was generated. Do **not** share credentials, cookies,
   generated KBSync blobs, or signed CDN URLs.

## Status codes

| Code | Meaning |
| --- | --- |
| `ready` | KBSync generated; inspect subsequent `ent/download HTTP` |
| `invalid-guid` | Local device GUID is not 12 hexadecimal characters |
| `invalid-dsid` | Stored account DSID is empty or nonnumeric |
| `assets` | SAP support assets failed to load or download |
| `assets-timeout` | SAP support assets did not load before the deadline |
| `storeagent` | StoreAgent asset / runtime failed |
| `guest` | KBSync emulator failed |
| `guest-timeout` | KBSync emulator exceeded a time limit |
| `empty` | Generator returned no KBSync data |
| `invalid-blob` | Native bridge returned invalid Base64 |
| `bridge-unavailable` | Native bridge returned no pointer |
| `bridge-error`, `input` | Other native bridge/input error |

Stage codes are designed not to disclose sensitive information.

## Current limitations

- Successful GitHub compilation does **not** establish that SAP emulation
  can execute in a stock, signed iOS app; on-device validation is required.
- Apple may reject the preferred request even when KBSync is generated.
- R4 does not decrypt app-store FairPlay protection or bypass app licensing.
- This experimental workflow does not accept or store Apple credentials.
