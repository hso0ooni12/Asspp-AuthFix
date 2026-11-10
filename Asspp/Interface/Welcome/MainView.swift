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
    private struct LegacyTabMainView: View {
        @State var dvm = Downloads.this
        @State private var decryptor = DecryptionCenter.shared
        @AppStorage("Velo.Appearance") private var appearance = "system"

        var body: some View {
            TabView {
                AccountView()
                    .tabItem { Label("Accounts", systemImage: "person") }
                DownloadView()
                    .tabItem {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                    .badge(dvm.activeOperationCount) // putting badge inside will not work on iOS versions before 18
                SearchView()
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                SettingView()
                    .tabItem { Label("Settings", systemImage: "gear") }
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
        @State var dvm = Downloads.this
        @State private var decryptor = DecryptionCenter.shared
        @AppStorage("Velo.Appearance") private var appearance = "system"

        var body: some View {
            TabView {
                Tab("Accounts", systemImage: "person") { AccountView() }
                Tab("Downloads", systemImage: "arrow.down.circle") { DownloadView() }
                    .badge(dvm.activeOperationCount)
                Tab("Search", systemImage: "magnifyingglass") { SearchView() }
                Tab("Settings", systemImage: "gear") { SettingView() }
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
    static let accent = Color.primary
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? (colorScheme == .dark ? Color.black : .white) : .primary)
            .padding(.horizontal, 16)
            .frame(minWidth: 84, minHeight: 44)
            .background(
                prominent ? (colorScheme == .dark ? Color.white : .black) : AssppTheme.elevated,
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(AssppTheme.separator.opacity(prominent ? 0 : 0.4), lineWidth: 0.5)
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.65 : 1)
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

