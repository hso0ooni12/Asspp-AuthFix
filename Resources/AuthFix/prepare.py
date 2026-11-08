#!/usr/bin/env python3
"""Prepare an isolated, pinned ApplePackage source dependency for this build."""
from pathlib import Path
import hashlib
import os
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
VENDOR = ROOT / "Vendor" / "ApplePackage"
REVISION = "773583a29c6b1f1b0d0783d0a15d3ddafcd85eec"

if not VENDOR.exists():
    VENDOR.parent.mkdir(exist_ok=True)
    subprocess.run(["git", "clone", "--depth", "1", "--branch", "2.0.3", "https://github.com/Lakr233/ApplePackage.git", str(VENDOR)], check=True)
actual = subprocess.check_output(["git", "-C", str(VENDOR), "rev-parse", "HEAD"], text=True).strip()
if actual != REVISION:
    raise SystemExit("Unexpected ApplePackage revision; refusing an unpinned build")

# GitHub's public release-asset URL used by openssl-spm intermittently returns
# HTTP 504 from SwiftPM. Download the *same* upstream binary via GitHub's
# authenticated official release-asset API, verify its published SHA-256, and
# use it as a local SwiftPM binary target. No third-party mirror is involved.
openssl_package = ROOT / "Vendor" / "openssl-spm"
openssl_revision = "eac8fdd510ebbcd410982d209a4b1dc67eb063ce"
if not openssl_package.exists():
    subprocess.run([
        "git", "clone", "--depth", "1", "--branch", "4.0.1",
        "https://github.com/Lakr233/openssl-spm.git", str(openssl_package),
    ], check=True)
actual_openssl_revision = subprocess.check_output(
    ["git", "-C", str(openssl_package), "rev-parse", "HEAD"], text=True
).strip()
if actual_openssl_revision != openssl_revision:
    raise SystemExit("Unexpected openssl-spm revision")

binary_zip = ROOT / ".build-authfix" / "libssl.xcframework.zip"
binary_zip.parent.mkdir(parents=True, exist_ok=True)
expected_sha = "ef747218abfc2449c31f533f717965850c9ed7bc0d8dbdd50286087d572b02c4"
if not binary_zip.exists() or hashlib.sha256(binary_zip.read_bytes()).hexdigest() != expected_sha:
    curl_command = [
        "curl", "--fail", "--location", "--silent", "--show-error",
        "--retry", "8", "--retry-all-errors", "--retry-delay", "6",
        "-H", "Accept: application/octet-stream",
        "-H", "X-GitHub-Api-Version: 2022-11-28",
    ]
    if os.environ.get("GITHUB_TOKEN"):
        curl_command += ["-H", "Authorization: Bearer " + os.environ["GITHUB_TOKEN"]]
    curl_command += [
        "-o", str(binary_zip),
        "https://api.github.com/repos/Lakr233/openssl-spm/releases/assets/443439042",
    ]
    if subprocess.run(curl_command, check=False).returncode:
        raise SystemExit("Could not download the official OpenSSL release asset")
if hashlib.sha256(binary_zip.read_bytes()).hexdigest() != expected_sha:
    raise SystemExit("OpenSSL release ZIP failed SHA-256 verification")

binary_dir = openssl_package / "libssl.xcframework"
if not (binary_dir / "Info.plist").is_file():
    subprocess.run(["/usr/bin/ditto", "-x", "-k", str(binary_zip), str(openssl_package)], check=True)
if not (binary_dir / "Info.plist").is_file():
    # The published archive has not always had the XCFramework at ZIP root.
    # Rehome a single verified XCFramework so SwiftPM can reference it locally.
    candidates = [p for p in openssl_package.rglob("*.xcframework")
                  if (p / "Info.plist").is_file() and p != binary_dir]
    if len(candidates) == 1:
        shutil.move(str(candidates[0]), str(binary_dir))
if not (binary_dir / "Info.plist").is_file():
    import zipfile
    with zipfile.ZipFile(binary_zip) as source:
        print("Official OpenSSL archive entries:", source.namelist()[:22])
    raise SystemExit("OpenSSL release does not contain a recognizable XCFramework")

openssl_manifest = openssl_package / "Package.swift"
openssl_text = openssl_manifest.read_text()
binary_declaration = (
    'url: "https://github.com/Lakr233/openssl-spm/releases/download/storage.4.0.1/libssl.xcframework.zip",\n'
    '            checksum: "ef747218abfc2449c31f533f717965850c9ed7bc0d8dbdd50286087d572b02c4"'
)
if openssl_text.count(binary_declaration) != 1:
    raise SystemExit("OpenSSL binary target manifest changed unexpectedly")
openssl_manifest.write_text(openssl_text.replace(binary_declaration, 'path: "libssl.xcframework"'))

apple_manifest = VENDOR / "Package.swift"
apple_text = apple_manifest.read_text()
remote_openssl = '.package(url: "https://github.com/Lakr233/openssl-spm.git", from: "4.0.1")'
if apple_text.count(remote_openssl) != 1:
    raise SystemExit("ApplePackage OpenSSL dependency changed unexpectedly")
apple_manifest.write_text(apple_text.replace(remote_openssl, '.package(path: "../openssl-spm")'))
print("Verified official OpenSSL xcframework and configured local SwiftPM binary dependency.")

for name in ["Authenticate.swift", "AuthenticationRecovery.swift"]:
    shutil.copy2(ROOT / "Resources" / "AuthFix" / name, VENDOR / "Sources" / "ApplePackage" / "Commands" / name)
for name in ["SAPSetupTransport.swift", "SAPSigner+Connect.swift"]:
    shutil.copy2(ROOT / "Resources" / "AuthFix" / name, VENDOR / "Sources" / "ApplePackage" / "SAP" / name)
shutil.copy2(ROOT / "Resources" / "AuthFix" / "SAPSetupTransportTests.swift", VENDOR / "Tests" / "ApplePackageTests" / "SAPSetupTransportTests.swift")

project = ROOT / "Asspp.xcodeproj" / "project.pbxproj"
text = project.read_text()
identifier = "50ABFB102F48A6D60077DE1A"
pattern = rf'(?ms)^\t\t{identifier} /\* XCRemoteSwiftPackageReference "ApplePackage" \*/ = \{{.*?^\t\t\}};\n'
replacement = (
    '/* Begin XCLocalSwiftPackageReference section */\n'
    f'\t\t{identifier} /* XCLocalSwiftPackageReference "ApplePackage" */ = {{\n'
    '\t\t\tisa = XCLocalSwiftPackageReference;\n'
    '\t\t\trelativePath = Vendor/ApplePackage;\n'
    '\t\t};\n'
    '/* End XCLocalSwiftPackageReference section */\n\n'
)
if 'relativePath = Vendor/ApplePackage;' not in text:
    text, count = re.subn(pattern, '', text)
    if count != 1:
        raise SystemExit("ApplePackage project reference changed unexpectedly")
    text = text.replace('/* Begin XCRemoteSwiftPackageReference section */', replacement + '/* Begin XCRemoteSwiftPackageReference section */', 1)
text = text.replace(f'{identifier} /* XCRemoteSwiftPackageReference "ApplePackage" */', f'{identifier} /* XCLocalSwiftPackageReference "ApplePackage" */')
project.write_text(text)
print("Prepared pinned ApplePackage 2.0.3 with AuthFix R2 native SAP setup transport.")
