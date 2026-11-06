# Asspp AuthFix R2

Experimental iOS build based on Asspp 4.2.2 and pinned ApplePackage 2.0.3. Version 4.2.4 (2026110702), bundle wiki.qaq.Asspp.AuthFix.

R2 addresses connection failures during SAP initialization, before any Apple account sign-in request. It uses ephemeral URLSession for the two public Apple setup endpoints, with a single NIO fallback only for connection/DNS/time-out failures. TLS certificate checks remain enabled. Automatic redirects, shared cookies and shared credential storage are disabled for setup; streamed bodies are capped at 2 MiB.

Each setup stage logs its name, HTTP status and byte count. Transport failures display the actual NIO POSIX/TLS or URL error code, without logging URLs, credentials, cookies, signatures or SAP request/reply contents. The UI resets failed setup sessions. The R1 bounded authentication-route recovery is retained.

CI runs focused offline transport tests and a separate public SAP setup probe without using an Apple account, then builds and verifies an unsigned arm64 IPA. The probe is an observation from the CI network; its result is recorded separately and is not an authentication-success test. Physical iPhone sign-in still requires testing.

Build on macOS with Xcode and xcbeautify using `bash Resources/AuthFix/build.sh`.
