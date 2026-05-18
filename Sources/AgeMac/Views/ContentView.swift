import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $store.selectedSection)
        } detail: {
            ZStack {
                DetailBackground(theme: store.settings.theme)
                DetailScrollContainer {
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
                .navigationTitle("Age Mac")
            }
        }
        .navigationSplitViewStyle(.balanced)
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

private struct DetailScrollContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let edgePadding = edgePadding(for: width)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .padding(.top, edgePadding.top)
                .padding(.horizontal, edgePadding.horizontal)
                .padding(.bottom, edgePadding.bottom)
                .frame(width: width, alignment: .topLeading)
                .frame(minHeight: height, alignment: .topLeading)
                .geometryGroup()
            }
            .scrollClipDisabled()
        }
    }

    private func edgePadding(for width: CGFloat) -> (horizontal: CGFloat, top: CGFloat, bottom: CGFloat) {
        let horizontal = min(max(width * 0.024, 20), 36)
        let top = min(max(width * 0.018, 22), 30)
        let bottom = min(max(width * 0.028, 30), 44)
        return (horizontal, top, bottom)
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
    }
}
