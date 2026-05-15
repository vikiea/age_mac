import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $store.selectedSection)
        } detail: {
            ZStack {
                DetailBackground(theme: store.settings.theme)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch store.selectedSection ?? .encrypt {
                        case .encrypt:
                            EncryptView()
                        case .decrypt:
                            DecryptView()
                        case .keys:
                            KeysView()
                        case .history:
                            HistoryView()
                        case .settings:
                            SettingsView()
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 980, alignment: .leading)
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索历史和密钥")
        .alert("Age Mac", isPresented: Binding(
            get: { store.alertMessage != nil },
            set: { if !$0 { store.alertMessage = nil } }
        )) {
            Button("好") { store.alertMessage = nil }
        } message: {
            Text(store.alertMessage ?? "")
        }
    }
}

struct DetailBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var theme: AppTheme

    var body: some View {
        if #available(macOS 26.0, *) {
            background
                .backgroundExtensionEffect()
        } else {
            background
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                stableWindowBackground,
                theme.accentColor.opacity(themeOpacity),
                theme.secondaryColor.opacity(themeOpacity)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var stableWindowBackground: Color {
        switch colorScheme {
        case .dark:
            Color(red: 0.075, green: 0.078, blue: 0.086)
        default:
            Color(red: 0.965, green: 0.968, blue: 0.974)
        }
    }

    private var themeOpacity: Double {
        colorScheme == .dark ? 0.12 : 0.08
    }
}

struct SidebarView: View {
    @Binding var selection: AppSection?

    var body: some View {
        List(AppSection.allCases, selection: $selection) { section in
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                    Text(section.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .tag(section)
        }
        .listStyle(.sidebar)
        .navigationTitle("Age Mac")
    }
}
