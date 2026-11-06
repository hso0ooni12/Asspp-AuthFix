#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 Resources/AuthFix/prepare.py

mkdir -p artifacts .build-authfix
swiftc -swift-version 6 \
  Vendor/ApplePackage/Sources/ApplePackage/Commands/AuthenticationRecovery.swift \
  Resources/AuthFix/AuthenticationRecoveryCheck.swift \
  -o .build-authfix/auth-recovery-check
.build-authfix/auth-recovery-check

cat > Configuration/Developer.xcconfig <<'CONFIG'
DEVELOPMENT_TEAM =
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY =
CODE_SIGNING_REQUIRED = NO
CODE_SIGNING_ALLOWED = NO
CONFIG

xcodebuild -workspace Asspp.xcworkspace -scheme Asspp -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .build-authfix/DerivedData \
  -clonedSourcePackagesDirPath .build-authfix/SourcePackages \
  DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_ENTITLEMENTS= MARKETING_VERSION=4.2.3 CURRENT_PROJECT_VERSION=2026110701 \
  PRODUCT_BUNDLE_IDENTIFIER=wiki.qaq.Asspp.AuthFix \
  INFOPLIST_KEY_CFBundleDisplayName='Asspp AuthFix' \
  build 2>&1 | tee artifacts/build.log | xcbeautify

python3 - <<'PY'
from pathlib import Path
import hashlib, json, plistlib, shutil, zipfile
root = Path.cwd()
app = root / '.build-authfix/DerivedData/Build/Products/Release-iphoneos/Asspp.app'
if not app.is_dir():
    raise SystemExit('Expected iPhoneOS app was not built')
info = plistlib.loads((app / 'Info.plist').read_bytes())
expected = {'CFBundleShortVersionString': '4.2.3', 'CFBundleVersion': '2026110701', 'CFBundleIdentifier': 'wiki.qaq.Asspp.AuthFix'}
for key, value in expected.items():
    if info.get(key) != value:
        raise SystemExit(f'Incorrect build metadata: {key}')
executable = app / info['CFBundleExecutable']
if b'AuthFix R1' not in executable.read_bytes():
    raise SystemExit('Recovery implementation marker absent from executable')
payload = root / '.build-authfix/Package/Payload'
payload.mkdir(parents=True, exist_ok=True)
target = payload / 'Asspp.app'
if target.exists():
    shutil.rmtree(target)
shutil.copytree(app, target, symlinks=True)
ipa = root / 'artifacts/Asspp-AuthFix-R1-unsigned.ipa'
# ditto preserves the app bundle's symlinks and filesystem metadata.
import subprocess
subprocess.run(['/usr/bin/ditto', '-c', '-k', '--keepParent', str(payload), str(ipa)], check=True)
with zipfile.ZipFile(ipa) as archive:
    if archive.testzip():
        raise SystemExit('IPA ZIP integrity failed')
digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
(root / 'artifacts/Asspp-AuthFix-R1-unsigned.ipa.sha256').write_text(digest + '  ' + ipa.name + '\n')
report = dict(expected, sourceRevision='773583a29c6b1f1b0d0783d0a15d3ddafcd85eec', sha256=digest, bytes=ipa.stat().st_size, authenticationOnDevice='not tested')
(root / 'artifacts/build-info.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
PY
