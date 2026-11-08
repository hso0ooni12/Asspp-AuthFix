#!/usr/bin/env python3
"""Check R17's removed signing surface and, after CI build, its packaged app."""

import argparse
import io
import json
import plistlib
from pathlib import Path
import zipfile


ROOT = Path(__file__).resolve().parents[2]
VERSION = "4.7.0"
BUILD = "2026110817"
IPA_NAME = "Asspp-R17-NoInternalSigning-unsigned.ipa"


def validate_sources():
    forbidden = (
        "SigningCenter", "AssppSigner", "assppNativeSign", "AssppSignIPA",
        "SigningDocumentPicker", "Install Signed FairPlayed", "pendingInstall",
        "decryptor.installer", "case .signed:",
    )
    for path in (ROOT / "Asspp").rglob("*.swift"):
        source = path.read_text()
        for marker in forbidden:
            if marker in source:
                raise SystemExit(f"Retired signing API {marker!r} remains in {path}")
    build_script = (ROOT / "Resources/AuthFix/build.sh").read_text()
    if "R12_SIGNER_ARCHIVE" in build_script or "R12_OPENSSL_DIR" in build_script:
        raise SystemExit("Build script still links the retired native signer")
    print("R17 runtime signing APIs and certificate-import UI are absent")


def validate_archive():
    ipa = ROOT / "artifacts" / IPA_NAME
    expected = {
        "CFBundleShortVersionString": VERSION,
        "CFBundleVersion": BUILD,
        "CFBundleIdentifier": "wiki.qaq.Asspp.AuthFix",
    }
    with zipfile.ZipFile(ipa) as archive:
        if archive.testzip() is not None:
            raise SystemExit("IPA ZIP integrity failed")
        info = plistlib.loads(archive.read("Payload/Asspp.app/Info.plist"))
        for key, value in expected.items():
            if info.get(key) != value:
                raise SystemExit(f"Incorrect R17 metadata: {key}={info.get(key)!r}")
        template = archive.read("Payload/Asspp.app/FairPlayed-shell.zip")
    with zipfile.ZipFile(io.BytesIO(template)) as archive:
        if archive.testzip() is not None:
            raise SystemExit("FairPlayed template ZIP integrity failed")
        binary = archive.read("FairPlayed.app/FairPlayed")
        if b"Auto export started" not in binary:
            raise SystemExit("Automatic export implementation is missing")
        if not archive.read("FairPlayed.app/FairPlayedIcon.png"):
            raise SystemExit("FairPlayed helper icon is missing")
    report_path = ROOT / "artifacts/build-info.json"
    report = json.loads(report_path.read_text())
    report.update(
        release="R17",
        internalSigning=False,
        directDecryptionOfNewDownloads=False,
        preparedHelperRequiresExternalSigning=True,
        deviceValidation="not run in CI",
    )
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    print("R17 IPA metadata, ZIP integrity and automatic-export template verified")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    validate_sources()
    if not args.source_only:
        validate_archive()
