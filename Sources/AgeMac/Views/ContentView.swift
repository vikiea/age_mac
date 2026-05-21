/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        ZStack {
            DetailBackground(
                theme: store.settings.theme,
                gaussianTransparencyEnabled: store.settings.gaussianTransparencyEnabled,
                gaussianTransparencyOpacity: store.effectiveGaussianTransparencyOpacity
            )

            NavigationSplitView {
                SidebarView(selection: $workspace.selectedSection)
                    .navigationSplitViewColumnWidth(min: 330, ideal: 360, max: 430)
            } detail: {
                DetailScrollContainer {
                    switch workspace.selectedSection ?? .encrypt {
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
            .navigationSplitViewStyle(.balanced)
            .background(Color.clear)
        }
        .gaussianWindowTranslucency(enabled: store.settings.gaussianTransparencyEnabled)
        .windowAppearance(store.settings.appearance)
        .alert("Age Mac", isPresented: Binding(
            get: { store.alertMessage != nil || workspace.alertMessage != nil },
            set: {
                if !$0 {
                    store.alertMessage = nil
                    workspace.alertMessage = nil
                }
            }
        )) {
            Button(store.strings.ok) {
                store.alertMessage = nil
                workspace.alertMessage = nil
            }
        } message: {
            Text(store.alertMessage ?? workspace.alertMessage ?? "")
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
    var gaussianTransparencyEnabled: Bool = false
    var gaussianTransparencyOpacity: Int = AppSettings.defaults().gaussianTransparencyOpacity

    var body: some View {
        if #available(macOS 26.0, *), !gaussianTransparencyEnabled {
            background
                .backgroundExtensionEffect()
        } else {
            background
        }
    }

    private var background: some View {
        ZStack {
            if gaussianTransparencyEnabled {
                GaussianWindowBackdrop()
                stableWindowBackground.opacity(stableBackgroundOpacity)
            } else {
                stableWindowBackground
            }
            themeTint
        }
        .ignoresSafeArea()
    }

    private var themeTint: LinearGradient {
        LinearGradient(
            colors: [
                gaussianTransparencyEnabled ? Color.white.opacity(gaussianOverlayOpacity(base: colorScheme == .dark ? 0.08 : 0.18)) : .clear,
                theme.accentColor.opacity(gaussianTransparencyEnabled ? gaussianOverlayOpacity(base: colorScheme == .dark ? 0.16 : 0.13) : themeOpacity),
                theme.secondaryColor.opacity(gaussianTransparencyEnabled ? gaussianOverlayOpacity(base: colorScheme == .dark ? 0.14 : 0.11) : themeOpacity)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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

    private var gaussianTransparencyFraction: Double {
        Double(AppSettings.clampGaussianTransparencyOpacity(gaussianTransparencyOpacity)) / 100
    }

    private var stableBackgroundOpacity: Double {
        1 - gaussianTransparencyFraction
    }

    private func gaussianOverlayOpacity(base: Double) -> Double {
        base * stableBackgroundOpacity
    }
}

extension View {
    func gaussianWindowTranslucency(enabled: Bool) -> some View {
        background(WindowTranslucencyConfigurator(isEnabled: enabled))
    }
}

private struct GaussianWindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .hudWindow
        nsView.blendingMode = .behindWindow
        nsView.state = .active
        nsView.isEmphasized = true
    }
}

private struct WindowTranslucencyConfigurator: NSViewRepresentable {
    var isEnabled: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        updateWindow(from: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        updateWindow(from: nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detachWindow()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func updateWindow(from view: NSView, coordinator: Coordinator) {
        let isEnabled = isEnabled
        DispatchQueue.main.async { [weak view, coordinator] in
            coordinator.update(window: view?.window, isEnabled: isEnabled)
        }
    }

    final class Coordinator {
        private weak var configuredWindow: NSWindow?
        private static var appliedWindows: Set<ObjectIdentifier> = []
        private static var originalAppearances: [ObjectIdentifier: WindowAppearance] = [:]

        func update(window: NSWindow?, isEnabled: Bool) {
            guard let window else { return }

            configuredWindow = window
            if isEnabled {
                applyTranslucency(to: window)
            } else {
                restoreWindow(window)
            }
        }

        func restoreWindow() {
            guard let window = configuredWindow else { return }
            restoreWindow(window)
        }

        func detachWindow() {
            configuredWindow = nil
        }

        private func restoreWindow(_ window: NSWindow) {
            let key = ObjectIdentifier(window)
            guard let originalAppearance = Self.originalAppearances[key] else {
                Self.appliedWindows.remove(key)
                return
            }

            updateWindowAppearance(for: window) {
                window.isOpaque = originalAppearance.isOpaque
                window.backgroundColor = originalAppearance.backgroundColor
                window.titlebarAppearsTransparent = originalAppearance.titlebarAppearsTransparent
            }
            Self.originalAppearances[key] = nil
            Self.appliedWindows.remove(key)
        }

        private func applyTranslucency(to window: NSWindow) {
            let key = ObjectIdentifier(window)
            if Self.originalAppearances[key] == nil {
                Self.originalAppearances[key] = WindowAppearance(window: window)
            }
            guard !Self.appliedWindows.contains(key) else { return }

            updateWindowAppearance(for: window) {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titlebarAppearsTransparent = true
            }
            Self.appliedWindows.insert(key)
        }

        private func updateWindowAppearance(for window: NSWindow, _ updates: () -> Void) {
            window.disableScreenUpdatesUntilFlush()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                updates()
            }
        }
    }

    private struct WindowAppearance {
        var isOpaque: Bool
        var backgroundColor: NSColor
        var titlebarAppearsTransparent: Bool

        init(window: NSWindow) {
            isOpaque = window.isOpaque
            backgroundColor = window.backgroundColor
            titlebarAppearsTransparent = window.titlebarAppearsTransparent
        }
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
                        Text(section.title(in: store.settings.language))
                            .foregroundStyle(titleColor(for: section))
                            .fontWeight(selection == section ? .semibold : .regular)
                        Text(section.subtitle(in: store.settings.language))
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
        .scrollContentBackground(.hidden)
        .background(Color.clear)
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
