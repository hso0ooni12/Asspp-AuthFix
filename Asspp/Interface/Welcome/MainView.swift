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
                Button("Asspp Help", systemImage: "") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/Lakr233/Asspp")!)
                }
            }
        }
    }
#else
    private struct LegacyTabMainView: View {
        @State var dvm = Downloads.this
        @State private var decryptor = DecryptionCenter.shared

        var body: some View {
            TabView {
                AccountView()
                    .tabItem { Label("Accounts", systemImage: "person") }
                DownloadView()
                    .tabItem {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                    .badge(dvm.runningTaskCount) // putting badge inside will not work on iOS versions before 18
                SearchView()
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                SettingView()
                    .tabItem { Label("Settings", systemImage: "gear") }
            }
            .sheet(item: $decryptor.sharePackage) { item in
                AssppActivityShare(items: [item.url])
            }
            .sheet(item: $decryptor.installer) { installer in
                InstallerView(installer: installer)
            }
            .tint(AssppTheme.accent)
            .preferredColorScheme(.dark)
        }
    }

    @available(iOS 18.0, *)
    struct NewMainView: View {
        @State var dvm = Downloads.this
        @State private var decryptor = DecryptionCenter.shared

        var body: some View {
            TabView {
                Tab("Accounts", systemImage: "person") { AccountView() }
                Tab("Downloads", systemImage: "arrow.down.circle") { DownloadView() }
                    .badge(dvm.runningTaskCount)
                Tab("Search", systemImage: "magnifyingglass") { SearchView() }
                Tab("Settings", systemImage: "gear") { SettingView() }
            }
            .neverMinimizeTab()
            .sidebarAdaptableTabView()
            .sheet(item: $decryptor.sharePackage) { item in
                AssppActivityShare(items: [item.url])
            }
            .sheet(item: $decryptor.installer) { installer in
                InstallerView(installer: installer)
            }
            .tint(AssppTheme.accent)
            .preferredColorScheme(.dark)
        }
    }
#endif

// One visual language shared by the four primary screens and the detail flows.
// Colors intentionally keep readable contrast behind the native iOS 26 glass UI.
enum AssppTheme {
    static let accent = Color(red: 0.34, green: 0.87, blue: 0.98)
    static let violet = Color(red: 0.51, green: 0.46, blue: 0.98)
    static let canvas = Color(red: 0.035, green: 0.055, blue: 0.115)
    static let surface = Color(red: 0.085, green: 0.115, blue: 0.19)
    static let elevated = Color(red: 0.12, green: 0.16, blue: 0.25)
    static let separator = Color.white.opacity(0.095)

    static var background: some View {
        ZStack {
            canvas
            RadialGradient(
                colors: [violet.opacity(0.23), accent.opacity(0.045), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 620
            )
        }
        .ignoresSafeArea()
    }
}

struct AssppScreenHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(2.4)
                    .foregroundStyle(AssppTheme.accent)
                Text(title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(-1.2)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.61))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(AssppTheme.accent)
                .frame(width: 58, height: 58)
                .background(AssppTheme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(AssppTheme.accent.opacity(0.24)))
        }
        .padding(.vertical, 6)
    }
}

struct AssppCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AssppTheme.surface, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .stroke(AssppTheme.separator, lineWidth: 1)
            }
    }
}
