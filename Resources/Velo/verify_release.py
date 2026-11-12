#!/usr/bin/env python3
"""Fail-closed source and distribution checks for R18-based Velo."""
import argparse
import importlib.util
import json
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VERSION = "5.7.1"
BUILD = "2026111206"
IPA_NAME = "Velo-5.7.1-HistoryFix-unsigned.ipa"

def validate_sources():
    store = (ROOT / "Asspp/Backend/AppStore/AppStore.swift").read_text()
    assert 'KeychainStorage(service: "wiki.qaq.Asspp.Accounts")' in store
    assert 'KeychainStorage(service: "wiki.qaq.Asspp.DeviceIdentifier", synchronizable: false)' in store
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
    assert "pendingPreparations" in manager and "activeOperationCount" in manager
    assert "!finalizingIDs.contains(request.id)" in manager
    quick = (ROOT / "Asspp/Interface/Search/QuickDownloadButton.swift").read_text()
    assert "Free License Required" not in quick
    assert "acquireFreeLicense" not in quick
    assert "request.state.percent" in quick and ".trim(from: 0" in quick
    assert "preferredAccountKey" in quick and "pendingPreparation" in quick
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
    assert "decryptor.isPreparingBatch" in downloads_view and "selectedIDs.removeAll()" in downloads_view
    assert "vm.pendingPreparations" in downloads_view
    assert "estimatedExtraBytes" in decryptor
    assert "running.isEmpty" in decryptor
    search = (ROOT / "Asspp/Interface/Search/SearchView.swift").read_text()
    assert "searchTask?.cancel()" in search and "latestSearchID == searchID" in search
    assert "cachedResults" in search
    storage = (ROOT / "Asspp/Extension/PublishedPersist.swift").read_text()
    assert "synchronizedLegacy" in storage and "isExcludedFromBackup" in storage
    assert "completeUntilFirstUserAuthentication" in storage
    settings = (ROOT / "Asspp/Interface/Setting/SettingView.swift").read_text()
    assert "Reset Preferences" in settings and "removeItem(at: documentsDirectory)" not in settings
    fairplayed_patch = (ROOT / "Resources/FairPlayed/auto-export-and-share.patch").read_text()
    assert "Velo-Decrypted-Batch.zip" in fairplayed_patch
    export_picker = (ROOT / "Resources/FairPlayed/monochrome-export-picker.patch").read_text()
    assert "FPExportPickerController" in export_picker
    assert "Select Individual IPAs" in export_picker
    assert "successfulIPAs.count != expected" in fairplayed_patch
    auth = (ROOT / "Asspp/Interface/Account/AddAccountView.swift").read_text()
    assert "prepareSecureConnection" in auth and "setupTask.value" in auth
    service = (ROOT / "Asspp/Backend/AppStore/StoreDownloadService.swift").read_text()
    assert "defer { session.invalidateAndCancel() }" in service
    assert "private static let metadataSession" not in service
    assert "DownloadPreparation.shared.generation" not in service
    assert "DownloadRouteAdvisor.shared.shouldTryPreferred" in service
    assert "DownloadRouteAdvisor.shared.fallbackSucceededAfterPreferredFailure" in service
    assert "isPreferredTransportFailure" in service
    protocol = (ROOT / "Asspp/Backend/AppStore/StoreDownloadProtocol.swift").read_text()
    assert '"volumeStore-transient"' in protocol and '"volumeStore-access-denied"' in protocol
    assert "DownloadTransferRetryPolicy" in protocol and "historyIdentifiers" in protocol
    assert "dataWithRetry(session: session, request: request" in service
    archive = (ROOT / "Asspp/Backend/AppStore/AppPackageArchive.swift").read_text()
    assert "first(where:" in archive and "unavailableVersionIDs" in archive
    assert "withLockedAccount" in archive
    assert "automaticTransferRetries" in manager and "transferAttemptTokens" in manager
    for name in ["Account/AccountView", "Download/DownloadView", "Search/SearchView", "Setting/SettingView", "Welcome/MainView"]:
        code = (ROOT / ("Asspp/Interface/" + name + ".swift")).read_text()
        assert "ASS•PP" not in code, name
    assert not (ROOT / "Asspp/Backend/Decryption/DirectFairPlayed.swift").exists()
    assert "private enum RemoteIPAInfoPlist" in service
    assert "readRange(session, url" in service
    assert "versionMetadataFromAsset" in service
    assert "ipaVerifiedVersionsV2" in archive
    assert "Version ID" not in (ROOT / "Asspp/Interface/Search/ProductHistoryView.swift").read_text()
    print("PASS Velo 5.7.1 bounded transient retries, historical versions, route cooldown and stable core")

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
    ipa_path = ROOT / "artifacts" / IPA_NAME
    with zipfile.ZipFile(ipa_path) as archive:
        metadata = plistlib.loads(archive.read("Payload/Asspp.app/Info.plist"))
        assert metadata["CFBundleDisplayName"] == "Velo"
        assert metadata["CFBundleName"] == "Velo", metadata
        assert metadata["CFBundleIdentifier"] == "wiki.qaq.Asspp.AuthFix"
        assert any(p.endswith("Assets.car") for p in archive.namelist())
        executable_size = archive.getinfo("Payload/Asspp.app/Asspp").file_size
        asset_catalog_size = archive.getinfo("Payload/Asspp.app/Assets.car").file_size
    path = ROOT / "artifacts/build-info.json"
    report = json.loads(path.read_text())
    report.update(
        release="Velo 5.7.1 Verified History Fix on stable R18/R20 core",
        displayName="Velo",
        preservesBundleIdentifier=True,
        quickDownloadFromSearch=True,
        autoFreeLicenseOnDownload=True,
        autoPaidPurchase=False,
        loginSAPPreconnect=True,
        downloadTransport="R20 per-request URLSession with temporary R3 cooldown and bounded transient retries",
        directDecryptionOfNewDownloads=False,
        deviceValidation="Public beta: physical iPhone testing required for Apple login, old versions and imported IPA decryption",
        measuredSpeedImprovement="unverified; compare cached rebuild timing separately",
        guardedDeletion=True,
        concurrentDownloads="Two byte transfers, serialized metadata per account",
        progressInSearch=True,
        bulkExport="One unsigned FairPlayed helper; ZIP or selected individual decrypted IPAs",
        batchVerification="All selected apps must decrypt completely before sharing group ZIP",
        batchPackagingFix="Only count direct embedded app Info.plist, ignore nested frameworks",
        deleteConfirmation=False,
        deviceTesting="Deletion and multiple iPhone downloads require device verification",
        searchCache="180-second in-memory result cache, stale searches cancelled",
        globalSearch="All Storefronts in progressive 8-country batches, 3 concurrent workers and region-aware Get",
        appearance="App Store-inspired native interface, restrained blue accent, Automatic/Light/Dark",
        appStoreSearchRows="Native 60pt icon results, pinned search and accent GET buttons",
        releaseOptimization="Swift -Osize, no unused avatar image, non-global Mach-O symbol stripping",
        progressPerformance="Speed samples throttled to 2 Hz; progress updates throttled to 5 Hz",
        priorIPABytes=20337534,
        priorVelo52IPABytes=16302302,
        bytesChangedVsVelo52=16302302 - ipa_path.stat().st_size,
        ipaBytes=ipa_path.stat().st_size,
        bytesSavedVsVelo51=20337534 - ipa_path.stat().st_size,
        mainExecutableBytes=executable_size,
        assetCatalogBytes=asset_catalog_size,
        helperExportPicker=True,
        nativeBuildCache="Pinned native outputs and compiled Xcode modules cached across repeated branch builds",
        appStorePreparation="Per-stage status and bounded retries for transient safe Apple requests",
        keychainMigration="Device GUID migrated to non-synchronizable local keychain storage",
        preflightStorage="Batch helper estimates temporary disk space before extraction",
        settingsReset="Preferences only; downloaded IPAs and Apple accounts preserved",
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

