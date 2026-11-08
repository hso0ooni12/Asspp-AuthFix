# Asspp R17 — internal signing removed

This release removes certificate/profile import, certificate passwords,
on-device IPA signing and installation of internally signed FairPlayed helpers.
The modern four-tab UI, App Store download engine and automatic FairPlayed
export/share behavior are retained.

## Important limitation

R17 **does not add direct decryption of new downloads inside Asspp**. A development
signature authorizes the installed Asspp bundle; it does not make later downloads
part of that installed bundle. FairPlayed documents that `fairplayd` can read
installed bundles but cannot read application data containers. It requires the
target payload to be embedded before signing and installing the helper.

Source: <https://github.com/morzelowski/FairPlayed#how-it-works>

The retained helper-preparation feature exports an **unsigned** FairPlayed IPA
containing the selected download. It still requires external signing and
installation. Opening that installed helper automatically decrypts and shares
the result as in the previously working R11 flow.

## Upgrade behavior

- Uses the same Asspp bundle identifier to support an in-place upgrade.
- Leaves App Store accounts and original downloaded IPAs intact.
- Removes only the retired signer's three generic-password Keychain records in
  service `wiki.qaq.Asspp.AuthFix.R12Signer` (`p12`, `mobileprovision`,
  `p12-password`). Source certificate files outside Asspp are untouched.
- Clears stale signed-helper cache pointers. Existing IPA files are retained.
- Never changes or removes the installed Asspp app's own code signature.

## Validation

`verify_release.py` checks that runtime Swift sources no longer refer to the
retired signing or helper-installation APIs. After an iOS build, it validates
release metadata, the IPA archive and the bundled FairPlayed template, including
its automatic-export marker and icon. The workflow also verifies that KBSync and
Unicorn TCI remain linked and `AssppSignIPA` is absent.

Device validation remains necessary for App Store login/download and helper
preparation; CI cannot operate the user's iPhone or license.
