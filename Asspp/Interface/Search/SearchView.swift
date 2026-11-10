//
//  SearchView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import Kingfisher
import SwiftUI

/// Lets menu commands ask the search field to take focus. SearchView consumes
/// the request on its next appearance, or immediately if already visible, and
/// clears it — so the one-shot survives the view being recreated when the user
/// switches sidebar sections.
@MainActor
@Observable
final class SearchFieldFocus {
    static let shared = SearchFieldFocus()
    var pending = false
    func requestFocus() {
        pending = true
    }
}

struct SearchView: View {
    @AppStorage("searchKey") var searchKey = ""
    @AppStorage("searchRegion") var searchRegion = "US"
    @FocusState var searchKeyFocused
    @State private var searchFocus = SearchFieldFocus.shared
    @State private var searchType = EntityType.iPhone

    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var latestSearchID = UUID()
    @State private var cachedResults: [String: (date: Date, items: [AppStore.AppPackage])] = [:]
    @State private var resultRegions: [String: String] = [:]
    @State private var remainingRegions: [String] = []
    let regionKeys = Array(ApplePackage.Configuration.storeFrontValues.keys.sorted())

    @State private var searchError: String?
    #if DEBUG
        @AppStorage("searchResults") // reduce API calls
        var searchResult: [AppStore.AppPackage] = []
    #else
        @State private var searchResult: [AppStore.AppPackage] = []
    #endif

    @State private var navigationPath = NavigationPath()
    @State private var vm = AppStore.this
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    var possibleRegion: Set<String> {
        vm.possibleRegions
    }

    var body: some View {
        #if os(iOS)
            NavigationStack(path: $navigationPath) {
                if #available(iOS 26.0, *) {
                    modernContent
                } else {
                    legacyContent
                }
            }
        #else
            NavigationStack(path: $navigationPath) {
                legacyContent
            }
        #endif
    }

    var searchTypePicker: some View {
        Picker(selection: $searchType) {
            ForEach(EntityType.allCases) { type in
                Text(type.rawValue).tag(type)
            }
        } label: {
            Label("Type", systemImage: searchType.iconName)
        }
        .onChange(of: searchType) { _, _ in
            searchTask?.cancel()
            searching = false
            searchResult = []
            remainingRegions = []
        }
    }

    var possibleRegionKeys: [String] {
        regionKeys.filter { possibleRegion.contains($0) }
    }

    func searchRegionView() -> some View {
        Menu {
            Button {
                searchRegion = "ALL"
            } label: {
                Label("All Stores", systemImage: "globe")
            }
            Divider()
            if !possibleRegionKeys.isEmpty {
                buildPickView(
                    for: possibleRegionKeys,
                ) {
                    Label("Available Regions", systemImage: "checkmark.seal")
                }
                .pickerStyle(.inline)

                buildPickView(
                    for: regionKeys,
                ) {
                    Label("All Regions", systemImage: "globe")
                }
                .pickerStyle(.menu)
            } else {
                buildPickView(
                    for: regionKeys,
                ) {}
                    .pickerStyle(.inline)
            }
        } label: {
            Label(searchRegion == "ALL" ? "All Stores" : searchRegion, systemImage: "globe")
        }
        .onChange(of: searchRegion) { _, _ in
            searchTask?.cancel()
            searching = false
            searchResult = []
            remainingRegions = []
        }
    }

    @ToolbarContentBuilder
    var tools: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Menu {
                searchTypePicker
                    .labelsHidden()
                    .pickerStyle(.inline)
            } label: {
                Label("Type", systemImage: searchType.iconName)
            }
            .menuIndicator(.hidden)
        }

        ToolbarItem(placement: .automatic) {
            searchRegionView()
                .menuIndicator(.hidden)
        }
    }

    var content: some View {
        Form {
            if let searchError {
                Section {
                    Text(searchError)
                        .foregroundStyle(.red)
                }
            }
            if searching || !searchResult.isEmpty {
                Section(searching ? "Searching..." : "\(searchResult.count) Results") {
                    ForEach(searchResult) { item in
                        HStack(spacing: 12) {
                            NavigationLink(value: ProductDestination(archive: item, region: region(for: item))) {
                                ArchivePreviewView(
                                    archive: item, preferredIconSize: 60,
                                    showsVersion: false, showsRating: true,
                                    storefront: searchRegion == "ALL" ? region(for: item) : nil
                                )
                            }
                            .buttonStyle(.plain)
                            QuickDownloadButton(package: item, region: region(for: item))
                        }
                    }
                    .transition(.opacity)
                }
                .transition(.opacity)
            }
            if searchRegion == "ALL", !remainingRegions.isEmpty {
                Button("Search More Stores (\(remainingRegions.count) remaining)") {
                    searchMoreStores()
                }
                .disabled(searching)
            }
        }
        .formStyle(.grouped)
        .animation(.spring, value: searchError)
        .navigationDestination(for: ProductDestination.self) { dest in
            ProductView(archive: dest.archive, region: dest.region, navigationPath: $navigationPath)
        }
        .navigationDestination(for: PackageManifest.self) { manifest in
            PackageView(pkg: manifest)
        }
        .animation(.spring, value: searchResult)
        .onAppear { consumePendingFocus() }
        .task(id: searchRegion + vm.accounts.map(\.id).joined(separator: "|")) {
            if searchRegion == "ALL" { vm.prepareDownloads() }
            else { vm.prepareDownloads(region: searchRegion) }
        }
        .onChange(of: searchFocus.pending) { _, isPending in
            if isPending {
                consumePendingFocus()
            }
        }
    }

    /// Focuses the search field if a focus request is pending (e.g. after the
    /// ⌘F menu command on macOS), then clears the request.
    private func consumePendingFocus() {
        guard searchFocus.pending else { return }
        searchFocus.pending = false
        // Defer so the search field exists when focus is assigned, whether the
        // view was already visible or is appearing for the first time.
        DispatchQueue.main.async { searchKeyFocused = true }
    }

    func buildPickView(for keys: [String], @ViewBuilder label: () -> some View) -> some View {
        Picker(selection: $searchRegion) {
            ForEach(keys, id: \.self) { key in
                Text("\(key) - \(ApplePackage.Configuration.storeFrontValues[key] ?? String(localized: "Unknown"))")
                    .tag(key)
            }
        } label: {
            label()
        }
    }

    func search() {
        searchKeyFocused = false
        let query = searchKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        searchTask?.cancel()
        let searchID = UUID()
        latestSearchID = searchID
        let region = searchRegion
        let entityType = searchType
        resultRegions = [:]
        remainingRegions = []
        searchResult = []
        if region == "ALL" {
            // Search account storefronts first, then common storefronts.
            // Remaining countries can be searched progressively, without
            // launching hundreds of simultaneous Apple Search requests.
            let priority = Array(possibleRegion).sorted() +
                ["SA", "US", "GB", "AE", "BH", "KW", "EG", "IN", "JP", "CN"]
            var seen = Set<String>()
            let countries = (priority + regionKeys).filter {
                regionKeys.contains($0) && seen.insert($0).inserted
            }
            remainingRegions = Array(countries.dropFirst(8))
            searching = true
            searchError = nil
            let initial = Array(countries.prefix(8))
            searchTask = Task { await searchCountries(initial, query: query, type: entityType, id: searchID) }
            return
        }
        let cacheKey = "\(region)|\(entityType.rawValue)|\(query.lowercased())"
        if let cached = cachedResults[cacheKey], Date().timeIntervalSince(cached.date) < 180 {
            searching = false
            searchError = nil
            searchResult = cached.items
            resultRegions = cached.items.reduce(into: [:]) { $0[$1.software.bundleID] = region }
            return
        }
        searching = true
        searchError = nil
        logger.info("search: region=\(region) type=\(entityType.rawValue)")
        searchTask = Task {
            do {
                var result = try await ApplePackage.Searcher.search(
                    term: query,
                    countryCode: region,
                    limit: 32,
                    entityType: entityType,
                )
                try Task.checkCancellation()
                // Bundle-ID lookup is only useful for names with dot segments.
                // Skipping it for ordinary text saves an unnecessary network call.
                if query.contains("."), !query.contains(" "),
                   let app = try? await ApplePackage.Lookup.lookup(
                       bundleID: query,
                       countryCode: region,
                       entityType: entityType
                   ), !result.contains(where: { $0.bundleID == app.bundleID }) {
                    result.insert(app, at: 0)
                }
                try Task.checkCancellation()
                let items = result.map { AppStore.AppPackage(software: $0, entityType: entityType) }
                await MainActor.run {
                    guard latestSearchID == searchID else { return }
                    searching = false
                    searchResult = items
                    resultRegions = items.reduce(into: [:]) { $0[$1.software.bundleID] = region }
                    searchError = nil
                    if cachedResults.count >= 20 {
                        cachedResults.removeAll(keepingCapacity: true)
                    }
                    cachedResults[cacheKey] = (Date(), items)
                }
            } catch is CancellationError {
                // A newer search owns the UI. Ignore stale cancellations.
            } catch {
                logger.error("search failed: \(type(of: error))")
                await MainActor.run {
                    guard latestSearchID == searchID else { return }
                    searching = false
                    searchResult = []
                    searchError = error.localizedDescription
                }
            }
        }
    }

    private func region(for item: AppStore.AppPackage) -> String {
        resultRegions[item.software.bundleID] ?? (searchRegion == "ALL" ? "US" : searchRegion)
    }

    private func searchMoreStores() {
        guard !searching, !remainingRegions.isEmpty else { return }
        let countries = Array(remainingRegions.prefix(8))
        remainingRegions.removeFirst(countries.count)
        searching = true
        searchError = nil
        let id = latestSearchID
        let query = searchKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = searchType
        searchTask = Task { await searchCountries(countries, query: query, type: type, id: id) }
    }

    @MainActor
    private func searchCountries(_ countries: [String], query: String,
                                 type: EntityType, id: UUID) async {
        var failures = 0
        for country in countries {
            guard !Task.isCancelled, latestSearchID == id else { return }
            do {
                let key = "\(country)|\(type.rawValue)|\(query.lowercased())"
                let apps: [AppStore.AppPackage]
                if let cached = cachedResults[key], Date().timeIntervalSince(cached.date) < 180 {
                    apps = cached.items
                } else {
                    var results = try await ApplePackage.Searcher.search(
                        term: query, countryCode: country, limit: 24, entityType: type
                    )
                    if query.contains("."), !query.contains(" "),
                       let direct = try? await ApplePackage.Lookup.lookup(
                           bundleID: query, countryCode: country, entityType: type
                       ), !results.contains(where: { $0.bundleID == direct.bundleID }) {
                        results.insert(direct, at: 0)
                    }
                    apps = results.map { AppStore.AppPackage(software: $0, entityType: type) }
                    if cachedResults.count >= 40 { cachedResults.removeAll(keepingCapacity: true) }
                    cachedResults[key] = (Date(), apps)
                }
                guard !Task.isCancelled, latestSearchID == id else { return }
                for app in apps {
                    // One row per app. Prefer the first storefront where it was
                    // found, usually an account's own region.
                    guard !searchResult.contains(where: { $0.software.bundleID == app.software.bundleID }) else { continue }
                    searchResult.append(app)
                    resultRegions[app.software.bundleID] = country
                }
            } catch is CancellationError {
                return
            } catch {
                failures += 1
                logger.warning("Search storefront request failed for \(country)")
            }
        }
        guard latestSearchID == id else { return }
        searching = false
        if failures == countries.count, searchResult.isEmpty {
            searchError = "Could not search these stores. Try again or choose a region."
        }
    }
}

struct ProductDestination: Hashable {
    let archive: AppStore.AppPackage
    let region: String
}

extension SearchView {
    var legacyContent: some View {
        content
            .searchable(text: $searchKey, prompt: "Keyword") {}
        #if os(macOS)
            .searchFocused($searchKeyFocused)
        #endif
            .onSubmit(of: .search) { search() }
            .navigationTitle("Search - \(searchRegion.uppercased())")
            .toolbar { tools }
    }
}

// MARK: - Liquid Glass

#if os(iOS)
    @available(iOS 26.0, *)
    extension SearchView {
        var modernContent: some View {
            List {
                if let searchError {
                    Label(searchError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                }
                if searchResult.isEmpty && !searching {
                    ContentUnavailableView.search(text: searchKey)
                        .listRowBackground(Color.clear)
                }
                if !searchResult.isEmpty {
                    Section("\(searchResult.count) Results") {
                        ForEach(searchResult) { item in
                            HStack(spacing: 10) {
                                NavigationLink(value: ProductDestination(archive: item, region: region(for: item))) {
                                    ArchivePreviewView(
                                        archive: item, preferredIconSize: 60,
                                        showsVersion: false, showsRating: true,
                                        storefront: searchRegion == "ALL" ? region(for: item) : nil
                                    )
                                }
                                .buttonStyle(.plain)
                                QuickDownloadButton(package: item, region: region(for: item))
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                if searching {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Searching...")
                            .foregroundStyle(.secondary)
                    }
                }
                if searchRegion == "ALL", !remainingRegions.isEmpty {
                    Button("Search More Stores (\(remainingRegions.count) remaining)") {
                        searchMoreStores()
                    }
                    .disabled(searching)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchKey, prompt: "App or Bundle ID")
            .searchFocused($searchKeyFocused)
            .onSubmit(of: .search, search)
            .background(AssppTheme.background)
            .navigationTitle("Search")
            .toolbar { tools }
            .navigationDestination(for: ProductDestination.self) { dest in
                ProductView(archive: dest.archive, region: dest.region, navigationPath: $navigationPath)
            }
            .navigationDestination(for: PackageManifest.self) { manifest in
                PackageView(pkg: manifest)
            }
            .onAppear { consumePendingFocus() }
            .task(id: searchRegion + vm.accounts.map(\.id).joined(separator: "|")) {
                if searchRegion == "ALL" { vm.prepareDownloads() }
                else { vm.prepareDownloads(region: searchRegion) }
            }
            .onChange(of: searchFocus.pending) { _, isPending in
                if isPending { consumePendingFocus() }
            }
        }

        var navigationBarVisibility: Visibility {
            switch horizontalSizeClass {
            case .compact:
                .hidden
            default:
                .automatic
            }
        }

        var searchablePlacement: SearchFieldPlacement {
            switch horizontalSizeClass {
            case .compact:
                .automatic
            default:
                .toolbar
            }
        }
    }
#endif

#if DEBUG
    private typealias AppPackages = [AppStore.AppPackage]
    extension AppPackages: @retroactive RawRepresentable {
        public init?(rawValue: String) {
            guard
                let data = rawValue.data(using: .utf8),
                let decoded = try? JSONDecoder().decode([AppStore.AppPackage].self, from: data)
            else { return nil }

            self = decoded
        }

        public var rawValue: String {
            guard let data = try? JSONEncoder().encode(self),
                  let rawValue = String(data: data, encoding: .utf8)
            else { return "" }

            return rawValue
        }
    }
#endif

extension ApplePackage.EntityType {
    var iconName: String {
        switch self {
        case .iPhone:
            "iphone"
        case .iPad:
            "ipad"
        case .appleTV:
            "appletv"
        }
    }
}
