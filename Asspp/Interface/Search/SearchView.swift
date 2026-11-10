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

/// A Sendable payload boundary keeps the network workers off the MainActor
/// without transferring ApplePackage model objects across actor boundaries.
private struct StorefrontSearchOutcome: Sendable {
    let position: Int
    let country: String
    let encodedApps: Data?
}

private func fetchStorefront(position: Int, country: String,
                             query: String, type: EntityType) async -> StorefrontSearchOutcome {
    do {
        var results = try await ApplePackage.Searcher.search(
            term: query, countryCode: country, limit: 24, entityType: type
        )
        try Task.checkCancellation()
        if query.contains("."), !query.contains(" "),
           let direct = try? await ApplePackage.Lookup.lookup(
               bundleID: query, countryCode: country, entityType: type
           ), !results.contains(where: { $0.bundleID == direct.bundleID }) {
            results.insert(direct, at: 0)
        }
        try Task.checkCancellation()
        let data = try JSONEncoder().encode(results)
        return StorefrontSearchOutcome(position: position, country: country, encodedApps: data)
    } catch {
        return StorefrontSearchOutcome(position: position, country: country, encodedApps: nil)
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
        var pending: [(position: Int, country: String)] = []
        var known: [String: (index: Int, priority: Int)] = [:]
        for (index, app) in searchResult.enumerated() {
            // Results from earlier "Search More" batches always keep priority.
            known[app.software.bundleID] = (index, -1)
        }

        for (position, country) in countries.enumerated() {
            guard !Task.isCancelled, latestSearchID == id else { return }
            let key = "\(country)|\(type.rawValue)|\(query.lowercased())"
            if let cached = cachedResults[key], Date().timeIntervalSince(cached.date) < 180 {
                mergeStorefront(cached.items, country: country, priority: position, known: &known)
            } else {
                pending.append((position: position, country: country))
            }
        }

        // Three outstanding storefronts at a time avoids slow serial searches
        // without flooding Apple's API or overwhelming a cellular connection.
        await withTaskGroup(of: StorefrontSearchOutcome.self) { group in
            let concurrency = min(3, pending.count)
            for index in 0..<concurrency {
                let job = pending[index]
                group.addTask {
                    await fetchStorefront(position: job.position, country: job.country,
                                          query: query, type: type)
                }
            }
            var next = concurrency
            for await outcome in group {
                guard !Task.isCancelled, latestSearchID == id else {
                    group.cancelAll()
                    break
                }
                if let data = outcome.encodedApps,
                   let software = try? JSONDecoder().decode([ApplePackage.Software].self, from: data) {
                    let apps = software.map { AppStore.AppPackage(software: $0, entityType: type) }
                    let key = "\(outcome.country)|\(type.rawValue)|\(query.lowercased())"
                    if cachedResults.count >= 40,
                       let oldest = cachedResults.min(by: { $0.value.date < $1.value.date })?.key {
                        cachedResults.removeValue(forKey: oldest)
                    }
                    cachedResults[key] = (Date(), apps)
                    mergeStorefront(apps, country: outcome.country,
                                    priority: outcome.position, known: &known)
                } else {
                    failures += 1
                    logger.warning("Search storefront request failed for \(outcome.country)")
                }
                if next < pending.count {
                    let job = pending[next]
                    group.addTask {
                        await fetchStorefront(position: job.position, country: job.country,
                                              query: query, type: type)
                    }
                    next += 1
                }
            }
        }
        guard latestSearchID == id else { return }
        searching = false
        if failures == countries.count, searchResult.isEmpty {
            searchError = "Could not search these stores. Try again or choose a region."
        }
    }

    @MainActor
    private func mergeStorefront(_ apps: [AppStore.AppPackage], country: String, priority: Int,
                                 known: inout [String: (index: Int, priority: Int)]) {
        var updated = searchResult
        var changed = false
        for app in apps {
            let bundleID = app.software.bundleID
            if let existing = known[bundleID] {
                // An account's storefront outranks a later common-region hit,
                // even if the slower network response arrives afterwards.
                if priority < existing.priority {
                    updated[existing.index] = app
                    known[bundleID] = (existing.index, priority)
                    resultRegions[bundleID] = country
                    changed = true
                }
            } else {
                known[bundleID] = (updated.count, priority)
                updated.append(app)
                resultRegions[bundleID] = country
                changed = true
            }
        }
        if changed { searchResult = updated } // One SwiftUI update per storefront.
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
