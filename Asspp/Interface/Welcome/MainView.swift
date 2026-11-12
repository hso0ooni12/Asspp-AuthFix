//
//  MainView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct MainView: View {
    var body: some View {
        #if os(macOS)
            MacSidebarMainView()
        #else
            if #available(iOS 26.0, *) {
                NewMainView()
            } else {
                LegacyTabMainView()
            }
        #endif
    }
}

#if os(macOS)
    private struct MacSidebarMainView: View {
        @State private var selection: SidebarSection? = .home
        @State private var downloads = Downloads.this

        var body: some View {
            NavigationSplitView {
                List(SidebarSection.allCases, selection: $selection) { section in
                    SidebarRow(section: section, downloads: downloads.runningTaskCount)
                        .tag(section)
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 150, ideal: 150, max: 200)
            } detail: {
                Group {
                    if let selection {
                        detailView(for: selection)
                    } else {
                        detailView(for: .home)
                    }
                }
                .frame(minHeight: 250)
                .navigationSplitViewColumnWidth(min: 480, ideal: 500)
            }
            // Expose the selection so menu commands (⌘F, ⌘,) can drive it.
            .focusedSceneValue(\.sidebarSelection, $selection)
        }

        @ViewBuilder
        private func detailView(for section: SidebarSection) -> some View {
            switch section {
            case .home:
                WelcomeView()
            case .accounts:
                AccountView()
            case .search:
                SearchView()
            case .downloads:
                DownloadView()
            case .installed:
                InstalledListView()
            case .settings:
                SettingView()
            }
        }
    }

    enum SidebarSection: Hashable, CaseIterable, Identifiable {
        case home
        case accounts
        case search
        case downloads
        case installed
        case settings

        var id: Self {
            self
        }

        var title: LocalizedStringKey {
            switch self {
            case .home:
                "Home"
            case .accounts:
                "Accounts"
            case .search:
                "Search"
            case .downloads:
                "Downloads"
            case .installed:
                "Installed"
            case .settings:
                "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .home:
                "house"
            case .accounts:
                "person"
            case .search:
                "magnifyingglass"
            case .downloads:
                "arrow.down.circle"
            case .installed:
                "square.stack.3d.up.badge.automatic.fill"
            case .settings:
                "gear"
            }
        }
    }

    private struct SidebarRow: View {
        let section: SidebarSection
        let downloads: Int

        var body: some View {
            HStack {
                Label(section.title, systemImage: section.systemImage)
                if section == .downloads, downloads > 0 {
                    Spacer()
                    Text("\(downloads)")
                        .font(.caption2.bold())
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private struct SidebarSelectionKey: FocusedValueKey {
        typealias Value = Binding<SidebarSection?>
    }

    extension FocusedValues {
        var sidebarSelection: Binding<SidebarSection?>? {
            get { self[SidebarSelectionKey.self] }
            set { self[SidebarSelectionKey.self] = newValue }
        }
    }

    /// Menu commands that jump to sidebar sections by keyboard shortcut.
    struct SidebarMenuCommands: Commands {
        @FocusedValue(\.sidebarSelection) private var selection

        var body: some Commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { selection?.wrappedValue = .settings }
                    .keyboardShortcut(",", modifiers: .command)
                    .disabled(selection == nil)
            }
            CommandGroup(after: .sidebar) {
                Button("Search") {
                    selection?.wrappedValue = .search
                    SearchFieldFocus.shared.requestFocus()
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(selection == nil)
            }
            CommandGroup(replacing: .help) {
                Button("Velo Help", systemImage: "") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/hso0ooni12/Asspp-AuthFix")!)
                }
            }
        }
    }
#else

    private enum VeloTab: Hashable {
        case home, search, downloads, settings
    }

    private struct LegacyTabMainView: View {
        @State private var selection: VeloTab = .home
        @State private var dvm = Downloads.this
        @State private var decryptor = DecryptionCenter.shared
        @AppStorage("Velo.Appearance") private var appearance = "system"
        @AppStorage("searchKey") private var searchKey = ""

        var body: some View {
            TabView(selection: $selection) {
                VeloHomeView(onSearch: { term in
                    searchKey = term
                    selection = .search
                }, onDownloads: { selection = .downloads })
                    .tabItem { Label("Home", systemImage: "house.fill") }
                    .tag(VeloTab.home)

                SearchView()
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    .tag(VeloTab.search)

                DownloadView()
                    .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                    .badge(dvm.activeOperationCount)
                    .tag(VeloTab.downloads)

                SettingView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(VeloTab.settings)
            }
            .sheet(item: $decryptor.sharePackage) { item in
                AssppActivityShare(items: [item.url])
            }
            .tint(AssppTheme.accent)
            .preferredColorScheme(VeloAppearance.scheme(for: appearance))
        }
    }

    @available(iOS 18.0, *)
    struct NewMainView: View {
        @State private var selection: VeloTab = .home
        @State private var dvm = Downloads.this
        @State private var decryptor = DecryptionCenter.shared
        @AppStorage("Velo.Appearance") private var appearance = "system"
        @AppStorage("searchKey") private var searchKey = ""

        var body: some View {
            TabView(selection: $selection) {
                Tab("Home", systemImage: "house.fill", value: VeloTab.home) {
                    VeloHomeView(onSearch: { term in
                        searchKey = term
                        selection = .search
                    }, onDownloads: { selection = .downloads })
                }
                Tab("Search", systemImage: "magnifyingglass", value: VeloTab.search) {
                    SearchView()
                }
                Tab("Downloads", systemImage: "arrow.down.circle", value: VeloTab.downloads) {
                    DownloadView()
                }
                .badge(dvm.activeOperationCount)
                Tab("Settings", systemImage: "gearshape", value: VeloTab.settings) {
                    SettingView()
                }
            }
            .neverMinimizeTab()
            .sidebarAdaptableTabView()
            .sheet(item: $decryptor.sharePackage) { item in
                AssppActivityShare(items: [item.url])
            }
            .tint(AssppTheme.accent)
            .preferredColorScheme(VeloAppearance.scheme(for: appearance))
        }
    }

    /// App Store-inspired landing page using only the user's real library.
    /// No speculative ratings, screenshot assets, or fake featured apps.
    private struct VeloHomeView: View {
        let onSearch: (String) -> Void
        let onDownloads: () -> Void
        @State private var query = ""
        @State private var showAccounts = false
        @State private var downloads = Downloads.this

        private let categories: [(String, String, String)] = [
            ("Utilities", "wrench.and.screwdriver", "utilities"),
            ("Entertainment", "play.rectangle", "entertainment"),
            ("Games", "gamecontroller", "games"),
            ("Social", "bubble.left.and.bubble.right", "social")
        ]

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        HStack {
                            Text("Velo")
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                                .tracking(-1.3)
                            Spacer()
                            Button { showAccounts = true } label: {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 30, weight: .light))
                                    .frame(width: 44, height: 44)
                                    .background(AssppTheme.elevated, in: Circle())
                            }
                            .accessibilityLabel("Apple Accounts")
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search apps and games", text: $query)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .submitLabel(.search)
                                .onSubmit { onSearch(query) }
                            Button { onSearch(query) } label: {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.title2)
                            }
                            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityLabel("Search")
                        }
                        .padding(14)
                        .background(AssppTheme.elevated, in: RoundedRectangle(cornerRadius: 15))

                        VStack(alignment: .leading, spacing: 12) {
                            Text("DISCOVER")
                                .font(.caption.weight(.semibold))
                                .tracking(1.2)
                                .foregroundStyle(.secondary)
                            Button { onSearch("") } label: {
                                ZStack(alignment: .bottomLeading) {
                                    RoundedRectangle(cornerRadius: 22)
                                        .fill(LinearGradient(
                                            colors: [Color(red: 0.03, green: 0.08, blue: 0.19),
                                                     Color(red: 0.09, green: 0.28, blue: 0.62),
                                                     Color(red: 0.30, green: 0.14, blue: 0.47)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
                                    Image(systemName: "square.stack.3d.up.fill")
                                        .font(.system(size: 122, weight: .ultraLight))
                                        .foregroundStyle(.white.opacity(0.16))
                                        .offset(x: 155, y: -40)
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Explore the App Store")
                                            .font(.title2.bold())
                                        Text("Find apps, discover versions and download IPA files.")
                                            .font(.subheadline)
                                            .foregroundStyle(.white.opacity(0.82))
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text("Explore Apps")
                                            .font(.subheadline.weight(.semibold))
                                            .padding(.horizontal, 17)
                                            .padding(.vertical, 9)
                                            .background(.white, in: Capsule())
                                            .foregroundStyle(Color.black)
                                            .padding(.top, 8)
                                    }
                                    .foregroundStyle(.white)
                                    .padding(22)
                                }
                                .frame(height: 205)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Discover apps in Search")
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Categories").font(.title3.bold())
                                Spacer()
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 4),
                                      spacing: 9) {
                                ForEach(0..<categories.count, id: \.self) { index in
                                    Button { onSearch(categories[index].2) } label: {
                                        VStack(spacing: 9) {
                                            Image(systemName: categories[index].1)
                                                .font(.system(size: 23))
                                                .frame(height: 30)
                                            Text(categories[index].0)
                                                .font(.caption2.weight(.medium))
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.75)
                                        }
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(AssppTheme.elevated, in: RoundedRectangle(cornerRadius: 16))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Your Apps").font(.title3.bold())
                                Spacer()
                                Button("View All") { onDownloads() }
                                    .font(.subheadline)
                            }
                            if downloads.manifests.isEmpty {
                                HStack(spacing: 12) {
                                    Image(systemName: "arrow.down.app")
                                        .font(.title2)
                                        .foregroundStyle(AssppTheme.accent)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Start your library").font(.subheadline.weight(.semibold))
                                        Text("Search for an app to begin downloading.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(15)
                                .background(AssppTheme.elevated, in: RoundedRectangle(cornerRadius: 16))
                            } else {
                                ForEach(Array(downloads.manifests.suffix(4).reversed()), id: \.id) { manifest in
                                    NavigationLink(value: manifest) {
                                        HStack(spacing: 12) {
                                            ArchivePreviewView(archive: manifest.package,
                                                               preferredIconSize: 58, showsVersion: true)
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.plain)
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
                .background(AssppTheme.background)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: PackageManifest.self) { manifest in
                    PackageView(pkg: manifest)
                }
            }
            .sheet(isPresented: $showAccounts) {
                AccountView()
            }
        }
    }


#endif

enum VeloAppearance {
    static func scheme(for value: String) -> ColorScheme? {
        switch value {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

// Semantic monochrome surfaces follow the system's Light/Dark appearance.
// Branding never changes the meaning of system controls or error states.
enum AssppTheme {
    static let accent = Color(red: 0.04, green: 0.53, blue: 0.98)
    static let contrast = Color.primary
    static let violet = Color.secondary
    #if canImport(UIKit)
        static let canvas = Color(uiColor: .systemBackground)
        static let surface = Color(uiColor: .secondarySystemGroupedBackground)
        static let elevated = Color(uiColor: .secondarySystemBackground)
        static let separator = Color(uiColor: .separator)
    #else
        static let canvas = Color(nsColor: .windowBackgroundColor)
        static let surface = Color(nsColor: .controlBackgroundColor)
        static let elevated = Color(nsColor: .textBackgroundColor)
        static let separator = Color(nsColor: .separatorColor)
    #endif

    static var background: some View {
        canvas.ignoresSafeArea()
    }
}

/// Compact, 44pt-tall App Store-style actions. Explicit adaptive contrast avoids
/// white-on-white / black-on-black labels when the app appearance is overridden.
struct VeloPillButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : (colorScheme == .dark ? Color.white : .primary))
            .padding(.horizontal, 16)
            .frame(minWidth: 84, minHeight: 44)
            .background(
                prominent ? AssppTheme.accent : AssppTheme.elevated,
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(AssppTheme.separator.opacity(prominent ? 0 : 0.4), lineWidth: 0.5)
            }
            .contentShape(Capsule())
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.65 : 1)
    }
}

struct AssppScreenHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        Text(title)
            .font(.largeTitle.bold())
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .padding(.vertical, 4)
    }
}

struct AssppCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AssppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

