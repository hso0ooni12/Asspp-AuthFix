#!/usr/bin/env python3
"""Fail-closed source and distribution checks for R18-based Velo."""
import argparse
import importlib.util
import json
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VERSION = "4.8.3"
BUILD = "2026110825"
IPA_NAME = "Velo-R24-BatchFix-unsigned.ipa"

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
    assert "AccountDownloadGate" in coordinator
    manager = (ROOT / "Asspp/Backend/Downloader/Downloads.swift").read_text()
    assert "activeTransferIDs" in manager and "finalizingIDs" in manager
    quick = (ROOT / "Asspp/Interface/Search/QuickDownloadButton.swift").read_text()
    assert "Free License Required" not in quick
    assert "acquireFreeLicense" not in quick
    assert "request.state.percent" in quick and ".trim(from: 0" in quick
    downloads_view = (ROOT / "Asspp/Interface/Download/DownloadView.swift").read_text()
    assert "selectedIDs" in downloads_view and "prepareBatch" in downloads_view
    decryptor = (ROOT / "Asspp/Interface/Download/PackageView.swift").read_text()
    assert "FairPlayedBatchArchive" in decryptor and "prepareBatch(inputs:" in decryptor
    assert "Velo-Batch-" in decryptor
    assert 'parts.count == 2, parts[1] == "Info.plist"' in decryptor
    assert "verifiedNames == expectedNames" in decryptor
    assert "batchArchiveMismatch" in decryptor
    assert "for input in inputs { statuses.removeValue(forKey: input.id) }" in decryptor
    downloads_view = (ROOT / "Asspp/Interface/Download/DownloadView.swift").read_text()
    assert "deleteImmediately(id: req.id)" in downloads_view
    assert 'confirmationDialog("Delete this download?"' not in downloads_view
    fairplayed_patch = (ROOT / "Resources/FairPlayed/auto-export-and-share.patch").read_text()
    assert "Velo-Decrypted-Batch.zip" in fairplayed_patch
    assert "successfulIPAs.count != expected" in fairplayed_patch
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
    print("PASS R18 core, R20 transport, Velo UI, guarded deletion, two transfers, batch helper ZIP")

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
        assert metadata["CFBundleDisplayName"] == "Velo"
        assert metadata["CFBundleName"] == "Velo", metadata
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
        guardedDeletion=True,
        concurrentDownloads="Two byte transfers, serialized metadata per account",
        progressInSearch=True,
        bulkExport="One unsigned FairPlayed helper for multiple apps; one decrypted ZIP after opening",
        batchVerification="All selected apps must decrypt completely before sharing group ZIP",
        batchPackagingFix="Only count direct embedded app Info.plist, ignore nested frameworks",
        deleteConfirmation=False,
        deviceTesting="Deletion and multiple iPhone downloads require device verification",
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

