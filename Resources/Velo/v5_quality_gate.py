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
    assert "resultRegions[bundleID] = country" in search
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


def test_native_polish_and_size_controls():
    main = source("Asspp/Interface/Welcome/MainView.swift")
    assert "struct VeloPillButtonStyle: ButtonStyle" in main
    assert "minHeight: 44" in main and "colorScheme == .dark" in main
    search = source("Asspp/Interface/Search/SearchView.swift")
    assert "preferredIconSize: 60" in search and "showsRating: true" in search
    quick = source("Asspp/Interface/Search/QuickDownloadButton.swift")
    assert "VeloPillButtonStyle()" in quick and 'Text("GET")' in quick
    assert ".buttonStyle(.bordered)" not in quick
    downloads = source("Asspp/Interface/Download/DownloadView.swift")
    assert "VeloPillButtonStyle()" in downloads
    artwork = source("Asspp/Interface/Search/ArchivePreviewView.swift")
    assert ".cacheOriginalImage()" not in artwork
    detail = source("Asspp/Interface/Search/PackageDisplayView.swift")
    assert "gradient: Gradient(colors: [.clear, .white])" not in detail
    manager = source("Asspp/Backend/Downloader/Downloads.swift")
    assert "lastSpeedUpdates" in manager and "(now - previous) >= 0.5" in manager
    assert not (ROOT / "Asspp/App/Assets.xcassets/Avatar.imageset").exists()
    assert (ROOT / "Resources/Velo/ArchivedAssets/Avatar.imageset/Avatar.png").exists()
    welcome = source("Asspp/Interface/Welcome/WelcomeView.swift")
    assert "Image(.avatar)" not in welcome and "ColorfulView" not in welcome
    assert "ColorfulX" not in source("Asspp.xcodeproj/project.pbxproj")
    logs = source("Asspp/Interface/Setting/LogView.swift")
    assert ".foregroundStyle(.yellow)" not in logs
    assert "VeloPillButtonStyle(prominent: true)" in logs
    assert "\\.isEnabled" in main
    release = source("Configuration/Release.xcconfig")
    assert "SWIFT_OPTIMIZATION_LEVEL = -Osize" in release
    build = source("Resources/AuthFix/build.sh")
    assert "xcrun strip -x -S" in build and "_R3GenerateKBSync" in build


def test_smart_route_and_fast_search():
    route = source("Asspp/Backend/AppStore/DownloadRouteAdvisor.swift")
    assert "actor DownloadRouteAdvisor" in route
    assert "failureThreshold = 2" in route and "10 * 60" in route
    assert "observations: [String: Observation]" in route
    service = source("Asspp/Backend/AppStore/StoreDownloadService.swift")
    assert "shouldTryPreferred(scope: routeScope)" in service
    assert "fallbackSucceededAfterPreferredFailure(scope: routeScope)" in service
    assert "preferredSucceeded(scope: routeScope)" in service
    assert "if operation == \"download\"" in service
    search = source("Asspp/Interface/Search/SearchView.swift")
    assert "withTaskGroup(of: StorefrontSearchOutcome.self)" in search
    assert "min(3, pending.count)" in search
    assert "group.cancelAll()" in search
    assert "mergeStorefront(apps" in search
    assert "resultRegions[bundleID] = country" in search
    assert "searchResult.contains(where:" not in search
    downloads = source("Asspp/Interface/Download/DownloadView.swift")
    assert 'Section("Active")' in downloads and 'Section("Ready")' in downloads


def test_app_store_native_54():
    main = source("Asspp/Interface/Welcome/MainView.swift")
    assert "VeloHomeView" in main
    assert 'Tab("Home"' in main and 'Tab("Search"' in main
    assert 'Tab("Downloads"' in main and 'Tab("Settings"' in main
    assert 'static let accent = Color(red:' in main
    assert "onSearch" in main and "showAccounts" in main
    product = source("Asspp/Interface/Search/ProductView.swift")
    assert "software.screenshotUrls" in product and 'sectionTitle("Preview")' in product
    assert 'sectionTitle("Information")' in product and 'sectionTitle("Version History")' in product
    assert "AppPackageArchive(" in product and "Download Requested" in product
    downloads = source("Asspp/Interface/Download/DownloadView.swift")
    assert "DownloadFilter" in downloads and "ProgressView(value: manifest.state.percent)" in downloads
    assert "decryptor.prepare(manifest)" in downloads
    details = source("Asspp/Interface/Download/PackageView.swift")
    assert 'sectionTitle("Ready to Decrypt")' in details
    assert 'sectionTitle("Information")' in details
    assert "AssppScreenHeader(" not in details
    search = source("Asspp/Interface/Search/SearchView.swift")
    assert "pinnedSearchField" in search and "storefrontFilters" in search
    assert "searchKeyFocused" in search
    history = source("Asspp/Interface/Search/ProductHistoryView.swift")
    assert 'Section("Previous Versions")' in history
    assert "VeloPillButtonStyle(prominent: true)" in history


if __name__ == "__main__":
    for test in (
        test_direct_app_count,
        test_download_lifecycle,
        test_batch_retry_preserves_selection,
        test_user_data_not_erased_by_preferences,
        test_search_and_privacy,
        test_monochrome_and_helper_export,
        test_native_polish_and_size_controls,
        test_smart_route_and_fast_search,
        test_app_store_native_54,
    ):
        test()
        print("PASS", test.__name__)
