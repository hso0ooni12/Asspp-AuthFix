#!/usr/bin/env python3
"""Fast, account-free checks for Velo's high-risk regressions."""

import io
import pathlib
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]


def source(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


def test_direct_app_count():
    """A framework Info.plist must not masquerade as a second embedded app."""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        for name in (
            "Payload/FairPlayed.app/EmbeddedPayload/First/Info.plist",
            "Payload/FairPlayed.app/EmbeddedPayload/First/Frameworks/A.framework/Info.plist",
            "Payload/FairPlayed.app/EmbeddedPayload/Second/Info.plist",
            "Payload/FairPlayed.app/EmbeddedPayload/Second/PlugIns/Widget.appex/Info.plist",
        ):
            archive.writestr(name, b"test")
    with zipfile.ZipFile(buffer) as archive:
        names = set()
        for entry in archive.namelist():
            if "/EmbeddedPayload/" not in entry:
                continue
            path = entry.split("/EmbeddedPayload/", 1)[1].split("/")
            if len(path) == 2 and path[1] == "Info.plist":
                names.add(path[0])
        assert names == {"First", "Second"}, names


def test_download_lifecycle():
    downloads = source("Asspp/Backend/Downloader/Downloads.swift")
    assert "registeredCallbacks" in downloads
    assert "finalizingIDs" in downloads
    assert "!finalizingIDs.contains(request.id)" in downloads
    assert "pendingPreparations" in downloads
    assert "activeOperationCount" in downloads
    coordinator = source("Asspp/Backend/Downloader/Downloads+UI.swift")
    assert "AccountDownloadGate" in coordinator
    assert "FreeLicensePolicy.shouldAcquire" in coordinator
    assert "pendingPreparations[key] = nil" in coordinator


def test_batch_retry_preserves_selection():
    downloads = source("Asspp/Interface/Download/DownloadView.swift")
    after_tap = downloads.split("decryptor.prepareBatch(chosen)", 1)[1].split("} label:", 1)[0]
    assert "selectedIDs.removeAll()" not in after_tap
    assert ".onChange(of: decryptor.isPreparingBatch)" in downloads
    helper = source("Asspp/Interface/Download/PackageView.swift")
    assert "verifiedNames == expectedNames" in helper
    assert "estimatedExtraBytes" in helper
    assert "running.isEmpty" in helper


def test_user_data_not_erased_by_preferences():
    settings = source("Asspp/Interface/Setting/SettingView.swift")
    assert "Reset Preferences" in settings
    assert "removeItem(at: documentsDirectory)" not in settings
    storage = source("Asspp/Extension/PublishedPersist.swift")
    assert "synchronizedLegacy" in storage
    assert "completeUntilFirstUserAuthentication" in storage
    assert "try FileManager.default.removeItem(at: file)" in storage


def test_search_and_privacy():
    search = source("Asspp/Interface/Search/SearchView.swift")
    assert "latestSearchID == searchID" in search
    assert "searchTask?.cancel()" in search
    assert "cachedResults" in search
    assert 'searchRegion = "ALL"' in search
    assert "searchMoreStores()" in search
    assert "resultRegions[app.software.bundleID] = country" in search
    assert "region: region(for: item)" in search
    auth = source("Asspp/Backend/AppStore/AuthenticationService.swift")
    assert 'logger.error("authentication failed for user: \\(error.localizedDescription)")' not in auth
    logger = source("Asspp/Backend/LogManager.swift")
    assert "[redacted]" in logger


def test_monochrome_and_helper_export():
    main = source("Asspp/Interface/Welcome/MainView.swift")
    assert ".preferredColorScheme(.dark)" not in main
    assert "RadialGradient" not in main
    assert "Color.primary" in main
    assert 'VeloAppearance.scheme(for: appearance)' in main
    settings = source("Asspp/Interface/Setting/SettingView.swift")
    assert 'Text("Automatic").tag("system")' in settings
    icon = source("Resources/Velo/make_icon.swift")
    assert "NSColor.black.setFill()" in icon and "NSColor.white.setStroke()" in icon
    patch = source("Resources/FairPlayed/monochrome-export-picker.patch")
    assert "FPExportPickerController" in patch
    assert "Export All as ZIP" in patch and "Select Individual IPAs" in patch
    assert "gLatestExportedIPAs = [successfulIPAs copy]" in patch
    assert "UIColor.systemBackgroundColor" in patch


if __name__ == "__main__":
    for test in (
        test_direct_app_count,
        test_download_lifecycle,
        test_batch_retry_preserves_selection,
        test_user_data_not_erased_by_preferences,
        test_search_and_privacy,
        test_monochrome_and_helper_export,
    ):
        test()
        print("PASS", test.__name__)
