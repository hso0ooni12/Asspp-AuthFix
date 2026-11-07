# Asspp R12: local IPA signing

The iOS app bundles a native, statically linked signing adapter built in CI.
The adapter uses the MIT-licensed [zsign](https://github.com/zhlynn/zsign)
implementation at pinned commit `9299685bab7ef99827e06e5dfda93af747386590`.
For device-compatible OpenSSL static libraries, CI pins the reference at
[`ForgeSign-iOS`](https://github.com/Mesutcydev/ForgeSign-iOS) commit
`b4ac4d853115cb216904ba9a8df26062f11abb46`.
The original repositories retain their respective licenses; these dependencies
are not modified or redistributed as source in the Asspp repository.

## Security and behavior

- Apple Account credentials continue to serve App Store downloads only.
- The user imports a PKCS#12 file, its password, and a provisioning profile once.
- All three are persisted in device-bound Keychain items with
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` protection.
- When the user requests Decrypt, Asspp prepares the embedded FairPlayed IPA.
- If signing assets exist, it writes a transient certificate/profile into a
  random temporary directory, signs via the linked zsign API, then removes the
  temporary directory immediately. No password, key, or app is sent to CI.
- The signed helper is saved to `Documents/FairPlayed/Signed`. The existing
  local OTA installer presents a user-facing installation prompt; iOS retains
  control of final installation and trust.
- If signing cannot complete, the unsigned helper remains shareable for
  recovery with an external signing tool. No half-signed package is offered.

An App Store login is **not** a private code-signing key. The provisioning
profile must authorize the app's bundle ID and the user's device and be valid.

This feature is experimental until verified with a real, valid signer identity
on the target iOS version. The GitHub Actions build never contains user
credentials or certificates.
