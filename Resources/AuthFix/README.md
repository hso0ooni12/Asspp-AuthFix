# Asspp AuthFix R1

Experimental iOS build based on Asspp 4.2.2 and pinned ApplePackage 2.0.3.

This build handles empty/HTML HTTP 204 and 404 authentication replies with bounded retries. If Apple's bag route consistently returns no business response, it tries the alternate slash form and the Apple native authentication route. SAP signatures, HTTPS certificate verification and the existing verification-code session remain required. HTTP 403, rate limits and actual App Store business errors do not trigger fallback retries.

The app logs route indices, numeric HTTP statuses, response sizes and whether an Apple responder header was present. It does not add credentials, verification codes, cookies, GUIDs or response bodies to logs. No Apple account is used by CI. The IPA needs signing on the iPhone. Login and download success must be tested on the physical device; a successful build does not prove authentication compatibility.

Version: 4.2.3 (2026110701). Display name: Asspp AuthFix. Bundle identifier: wiki.qaq.Asspp.AuthFix.

Build with `bash Resources/AuthFix/build.sh` on a Mac with Xcode and xcbeautify. CI prepares the pinned dependency and runs offline recovery checks before building the unsigned IPA.
