#!/usr/bin/env python3
"""Fail-closed source and distribution checks for R18-based Velo."""
import argparse
import importlib.util
import json
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VERSION = "4.8.0"
BUILD = "2026110822"
IPA_NAME = "Velo-R18-Streamlined-unsigned.ipa"

def validate_sources():
    store = (ROOT / "Asspp/Backend/AppStore/AppStore.swift").read_text()
    assert 'KeychainStorage(service: "wiki.qaq.Asspp.Accounts")' in store
    assert 'KeychainStorage(service: "wiki.qaq.Asspp.DeviceIdentifier")' in store
    assert "No-op retained for existing view call sites." in store
    script = (ROOT / "Resources/AuthFix/build.sh").read_text()
    assert "PRODUCT_BUNDLE_IDENTIFIER=wiki.qaq.Asspp.AuthFix" in script
    assert "INFOPLIST_KEY_CFBundleDisplayName='Velo'" in script
    policy = (ROOT / "Asspp/Backend/Downloader/FreeLicensePolicy.swift").read_text()
    assert "price == 0" in policy
    coordinator = (ROOT / "Asspp/Backend/Downloader/Downloads+UI.swift").read_text()
    assert "catch ApplePackageError.licenseRequired" in coordinator
    assert "FreeLicensePolicy.shouldAcquire" in coordinator
    assert "ApplePackage.Purchase.purchase" in coordinator
    assert "rotatePasswordToken" in coordinator
    quick = (ROOT / "Asspp/Interface/Search/QuickDownloadButton.swift").read_text()
    assert "Free License Required" not in quick
    assert "acquireFreeLicense" not in quick
    auth = (ROOT / "Asspp/Interface/Account/AddAccountView.swift").read_text()
    assert "prepareSecureConnection" in auth and "setupTask.value" in auth
    service = (ROOT / "Asspp/Backend/AppStore/StoreDownloadService.swift").read_text()
    assert "defer { session.invalidateAndCancel() }" in service
    assert "private static let metadataSession" not in service
    assert "DownloadPreparation.shared.generation" not in service
    protocol = (ROOT / "Asspp/Backend/AppStore/StoreDownloadProtocol.swift").read_text()
    assert 'onFallback("volumeStore-timeout")' in protocol
    for name in ["Account/AccountView", "Download/DownloadView", "Search/SearchView", "Setting/SettingView", "Welcome/MainView"]:
        code = (ROOT / ("Asspp/Interface/" + name + ".swift")).read_text()
        assert "ASS•PP" not in code, name
    assert not (ROOT / "Asspp/Backend/Decryption/DirectFairPlayed.swift").exists()
    print("PASS R18 core, stable R20 transport, Velo identity, login preconnect, free license policy")

def validate_archive():
    spec = importlib.util.spec_from_file_location("r17_checks", ROOT / "Resources/R17/verify_release.py")
    checks = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checks)
    checks.VERSION = VERSION
    checks.BUILD = BUILD
    checks.IPA_NAME = IPA_NAME
    checks.validate_sources()
    checks.validate_archive()
    import zipfile
    with zipfile.ZipFile(ROOT / "artifacts" / IPA_NAME) as archive:
        metadata = plistlib.loads(archive.read("Payload/Asspp.app/Info.plist"))
        assert metadata["CFBundleDisplayName"] == "Velo", metadata
        assert metadata["CFBundleIdentifier"] == "wiki.qaq.Asspp.AuthFix"
        assert any(p.endswith("Assets.car") for p in archive.namelist())
    path = ROOT / "artifacts/build-info.json"
    report = json.loads(path.read_text())
    report.update(
        release="Velo on R18 core",
        displayName="Velo",
        preservesBundleIdentifier=True,
        quickDownloadFromSearch=True,
        autoFreeLicenseOnDownload=True,
        autoPaidPurchase=False,
        loginSAPPreconnect=True,
        downloadTransport="Known-working R20 per-request URLSession",
        directDecryptionOfNewDownloads=False,
        deviceValidation="Physical iPhone testing required for sign-in and free license requests",
        measuredSpeedImprovement="not benchmarked in CI",
    )
    path.write_text(json.dumps(report, indent=2) + "\n")
    print("PASS signed-helper template, IPA metadata, icon catalog and archive integrity")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    validate_sources()
    if not args.source_only:
        validate_archive()
