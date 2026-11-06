#!/usr/bin/env python3
"""Prepare an isolated, pinned ApplePackage source dependency for this build."""
from pathlib import Path
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
