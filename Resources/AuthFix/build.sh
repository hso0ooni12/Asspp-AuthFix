#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 Resources/AuthFix/prepare.py

mkdir -p artifacts .build-authfix
# SwiftPM also resolves GitHub-hosted binary dependencies during this test.
# A transient 504 here must be retried before the Xcode build is reached.
transport_tests_ok=0
for test_attempt in 1 2 3 4 5 6; do
  echo "Compiling and running transport tests (attempt ${test_attempt}/6)"
  if swift test --package-path Vendor/ApplePackage --scratch-path .build-authfix/PackageTests \
    --filter SAPSetupTransportTests 2>&1 | tee artifacts/transport-tests.log; then
    transport_tests_ok=1
    break
  fi
  if ! grep -Eq 'badResponseStatusCode\(50[234]\)|failed downloading|Connection reset by peer|Could not resolve package' artifacts/transport-tests.log; then
    echo '::error::Transport tests failed for a reason other than transient package downloads.'
    break
  fi
  if [[ "$test_attempt" -lt 6 ]]; then sleep "$((test_attempt * 8))"; fi
done
if [[ "$transport_tests_ok" -ne 1 ]]; then
  echo '::error::Transport tests or dependency resolution failed.'
  exit 1
fi
if ASSPP_AUTHFIX_SETUP_PROBE=1 swift test --package-path Vendor/ApplePackage \
  --scratch-path .build-authfix/PackageTests --skip-build \
  --filter SAPSetupTransportTests.testLiveSetupWithoutAppleAccount 2>&1 | tee artifacts/sap-setup-probe.log; then
  printf 'passed\n' > artifacts/sap-setup-probe-result.txt
else
  printf 'failed\n' > artifacts/sap-setup-probe-result.txt
  echo '::warning::Public SAP setup probe failed on the CI network. See sap-setup-probe.log; no Apple account was used.'
fi

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

extra_xcodebuild_flags=()
if [[ -n "${R3_KBSYNC_ARCHIVE:-}" ]]; then
  [[ -s "${R3_KBSYNC_ARCHIVE}" ]] || { echo "Missing KBSync archive"; exit 1; }
  native_link_flags="-force_load ${R3_KBSYNC_ARCHIVE}"
  if [[ -n "${R6_TCI_ARCHIVE:-}" ]]; then
    [[ -s "${R6_TCI_ARCHIVE}" ]] || { echo "Missing iOS Unicorn archive"; exit 1; }
    # purego uses dlsym(RTLD_DEFAULT, "uc_version") on iOS. Force-load the
    # no-JIT static interpreter library and export its public API from the app binary.
    native_link_flags+=" -force_load ${R6_TCI_ARCHIVE} -Wl,-export_dynamic"
  fi
  extra_xcodebuild_flags=(OTHER_LDFLAGS="${native_link_flags}")
fi

# Some upstream SPM binary artifacts are hosted on GitHub Releases and can
# intermittently return HTTP 504. Keep the same checked-out source package
# directory across attempts so already downloaded dependencies are reused.
# Resolve before compiling so network errors cannot be mistaken for Swift
# compilation failures.
package_resolution_ok=0
for package_attempt in 1 2 3 4 5 6; do
  echo "Resolving Xcode packages (attempt ${package_attempt}/6)"
  if xcodebuild -resolvePackageDependencies \
    -workspace Asspp.xcworkspace -scheme Asspp \
    -clonedSourcePackagesDirPath .build-authfix/SourcePackages \
    > artifacts/package-resolution.log 2>&1; then
    package_resolution_ok=1
    break
  fi
  tail -12 artifacts/package-resolution.log
  if [[ "$package_attempt" -lt 6 ]]; then
    sleep "$((package_attempt * 8))"
  fi
done
if [[ "$package_resolution_ok" -ne 1 ]]; then
  echo '::error::Package dependencies could not be resolved after six attempts.'
  exit 1
fi

xcodebuild -workspace Asspp.xcworkspace -scheme Asspp -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .build-authfix/DerivedData \
  -clonedSourcePackagesDirPath .build-authfix/SourcePackages \
  DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_ENTITLEMENTS= MARKETING_VERSION=4.2.7 CURRENT_PROJECT_VERSION=2026110705 \
  PRODUCT_BUNDLE_IDENTIFIER=wiki.qaq.Asspp.AuthFix \
  INFOPLIST_KEY_CFBundleDisplayName='Velo' INFOPLIST_KEY_CFBundleName='Velo' \
  "${extra_xcodebuild_flags[@]}" build 2>&1 | tee artifacts/build.log | xcbeautify

python3 - <<'PY'
from pathlib import Path
import hashlib, json, plistlib, shutil, zipfile
root = Path.cwd()
app = root / '.build-authfix/DerivedData/Build/Products/Release-iphoneos/Asspp.app'
if not app.is_dir():
    raise SystemExit('Expected iPhoneOS app was not built')
info = plistlib.loads((app / 'Info.plist').read_bytes())
expected = {'CFBundleShortVersionString': '4.2.7', 'CFBundleVersion': '2026110705', 'CFBundleIdentifier': 'wiki.qaq.Asspp.AuthFix'}
for key, value in expected.items():
    if info.get(key) != value:
        raise SystemExit(f'Incorrect build metadata: {key}')
executable = app / info['CFBundleExecutable']
if b'AuthFix R2' not in executable.read_bytes():
    raise SystemExit('Recovery implementation marker absent from executable')
payload = root / '.build-authfix/Package/Payload'
payload.mkdir(parents=True, exist_ok=True)
target = payload / 'Asspp.app'
if target.exists():
    shutil.rmtree(target)
shutil.copytree(app, target, symlinks=True)
ipa = root / 'artifacts/Asspp-AuthFix-R2-unsigned.ipa'
# ditto preserves the app bundle's symlinks and filesystem metadata.
import subprocess
subprocess.run(['/usr/bin/ditto', '-c', '-k', '--keepParent', str(payload), str(ipa)], check=True)
with zipfile.ZipFile(ipa) as archive:
    if archive.testzip():
        raise SystemExit('IPA ZIP integrity failed')
digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
(root / 'artifacts/Asspp-AuthFix-R2-unsigned.ipa.sha256').write_text(digest + '  ' + ipa.name + '\n')
report = dict(expected, sourceRevision='773583a29c6b1f1b0d0783d0a15d3ddafcd85eec', appRevision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(), sha256=digest, bytes=ipa.stat().st_size, authenticationOnDevice='not tested', publicSAPSetupProbe=(root / 'artifacts/sap-setup-probe-result.txt').read_text().strip())
(root / 'artifacts/build-info.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
PY
