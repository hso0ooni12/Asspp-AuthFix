#!/usr/bin/env bash
# Run inside your private GitHub Codespace. Credentials are entered into ipatool
# interactively, never passed to this script or recorded in the Git repository.
set -euo pipefail

scripts_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_dir="$(cd -- "${scripts_dir}/../.." && pwd)"
ipatool="${HOME}/.local/bin/ipatool"
output_dir="${repository_dir}/cloud-downloads"
output_file="${output_dir}/Tahakom-5.0.2-encrypted.ipa"

if [[ ! -x "${ipatool}" ]]; then
    bash "${scripts_dir}/cloud-ipa-setup.sh"
fi

echo
echo "This downloads an encrypted, account-licensed App Store IPA."
echo "Your Apple Account password and 2FA code must only be entered"
echo "into ipatool's interactive prompt, never into GitHub issues or chat."
echo

if ! "${ipatool}" auth info >/dev/null 2>&1; then
    echo "Sign in with your Saudi Apple Account when prompted."
    "${ipatool}" auth login
fi

mkdir -p "${output_dir}"
echo
echo "Requesting Tahakom 5.0.2 (App ID 1538934970; iPhone release 894501944)..."
if ! "${ipatool}" download \
    --app-id 1538934970 \
    --platform iphone \
    --external-version-id 894501944 \
    --purchase \
    --output "${output_file}"; then
    echo "Download failed; review the ipatool error above. No credentials are needed in chat." >&2
    exit 1
fi

if [[ ! -s "${output_file}" ]]; then
    echo "Download reported success but the IPA is missing or empty." >&2
    exit 1
fi

python3 - "${output_file}" <<'PY'
import plistlib
import sys
import zipfile

path = sys.argv[1]
with zipfile.ZipFile(path) as archive:
    matches = [
        name for name in archive.namelist()
        if name.startswith("Payload/")
        and name.count("/") == 2
        and name.endswith(".app/Info.plist")
    ]
    if len(matches) != 1:
        raise SystemExit("IPA verification failed: expected one main Info.plist.")
    info = plistlib.loads(archive.read(matches[0]))
    actual_bundle = info.get("CFBundleIdentifier")
    actual_version = info.get("CFBundleShortVersionString")
    if actual_bundle != "com.tahakom.mytahakom" or actual_version != "5.0.2":
        raise SystemExit(
            f"IPA verification failed: unexpected bundle/version: "
            f"{actual_bundle} / {actual_version}"
        )
    bad_member = archive.testzip()
    if bad_member:
        raise SystemExit("IPA ZIP integrity check failed.")
    print(f"Verified app: {actual_bundle} version {actual_version}")
PY

echo
echo "Download complete: cloud-downloads/Tahakom-5.0.2-encrypted.ipa"
echo "In Codespaces Explorer, open cloud-downloads, right-click the IPA, and Download."
echo "Important: the IPA is still FairPlay-encrypted; no decryption was performed."
