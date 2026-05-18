/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import AppKit
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
        ZStack {
            stableWindowBackground
            if theme == .gaussian {
                Rectangle()
                    .fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.24),
                        theme.accentColor.opacity(colorScheme == .dark ? 0.14 : 0.11),
                        theme.secondaryColor.opacity(colorScheme == .dark ? 0.12 : 0.09)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [
                        .clear,
                        theme.accentColor.opacity(themeOpacity),
                        theme.secondaryColor.opacity(themeOpacity)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
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
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: AppStore
    @Binding var selection: AppSection?

    var body: some View {
        List(AppSection.allCases, selection: $selection) { section in
            ZStack {
                if selection == section {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selectionBackground)
                }

                HStack(spacing: 10) {
                    Image(systemName: section.systemImage)
                        .foregroundStyle(iconColor(for: section))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title)
                            .foregroundStyle(titleColor(for: section))
                            .fontWeight(selection == section ? .semibold : .regular)
                        Text(section.subtitle)
                            .font(.caption)
                            .foregroundStyle(subtitleColor(for: section))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(selection == section ? .isSelected : [])
            .tag(section)
        }
        .listStyle(.sidebar)
        .background(SidebarSelectionHighlightDisabler())
    }

    private func iconColor(for section: AppSection) -> Color {
        selection == section ? selectedForeground : store.settings.theme.accentColor.opacity(0.72)
    }

    private func titleColor(for section: AppSection) -> Color {
        selection == section ? selectedForeground : .primary
    }

    private func subtitleColor(for section: AppSection) -> Color {
        selection == section ? selectedForeground.opacity(0.82) : .secondary
    }

    private var selectionBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                store.settings.theme.accentColor.opacity(selectionOpacity),
                store.settings.theme.secondaryColor.opacity(selectionOpacity * 0.86)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var selectedForeground: Color {
        colorScheme == .dark ? .white : .primary
    }

    private var selectionOpacity: Double {
        colorScheme == .dark ? 0.38 : 0.24
    }
}

private struct SidebarSelectionHighlightDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            view.disableEnclosingTableSelectionHighlight()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.disableEnclosingTableSelectionHighlight()
        }
    }
}

private extension NSView {
    func disableEnclosingTableSelectionHighlight() {
        var candidate: NSView? = self
        while let view = candidate {
            if let tableView = view as? NSTableView {
                tableView.selectionHighlightStyle = .none
                return
            }
            if let tableView = view.firstDescendant(of: NSTableView.self) {
                tableView.selectionHighlightStyle = .none
                return
            }
            candidate = view.superview
        }
    }

    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T {
                return match
            }
            if let match = subview.firstDescendant(of: type) {
                return match
            }
        }
        return nil
    }
}
