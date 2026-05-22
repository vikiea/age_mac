/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true

        let iconURL = Bundle.main.url(forResource: "AgeMacIcon", withExtension: "icns")
            ?? Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        if let iconURL,
           let icon = NSImage(contentsOf: iconURL) {
            icon.size = NSSize(width: 1024, height: 1024)
            NSApp.applicationIconImage = icon
            NSApp.dockTile.contentView = nil
            NSApp.dockTile.display()
        }
        NSApp.setActivationPolicy(.regular)
    }
}

@main
struct AgeMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()
    @StateObject private var updateService = UpdateService()
    @StateObject private var windowRegistry = WindowWorkspaceRegistry()
    @Environment(\.openWindow) private var openWindow
    @FocusedObject private var focusedWorkspace: WorkspaceStore?

    var body: some Scene {
        let strings = store.strings
        let commandWorkspace = focusedWorkspace ?? windowRegistry.focusedWorkspace

        WindowGroup("Age Mac", id: "main") {
            MainWindowContent(appStore: store, updateService: updateService, windowRegistry: windowRegistry)
                .frame(minWidth: 1060, minHeight: 720)
                .tint(store.settings.theme.accentColor)
                .background(FocusClearingOverlay())
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            SidebarCommands()

            CommandGroup(replacing: .appInfo) {
                Button(strings.aboutAgeMac) {
                    openWindow(id: "about")
                }
            }

            CommandGroup(after: .sidebar) {
                Button(strings.showAllAgeTabs) {
                    showAllAgeTabs()
                }
                .disabled(!canShowAllAgeTabs)
                .keyboardShortcut("\\", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .newItem) {
                Button(strings.newAgeMacWindow) {
                    openWindow(id: "main")
                }
                .keyboardShortcut("n", modifiers: .command)

                Button(strings.newAgeMacTab) {
                    openMainWindowAsTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Divider()

                Button(strings.addEncryptFile) {
                    commandWorkspace?.selectedSection = .encrypt
                    commandWorkspace?.chooseEncryptFiles()
                }
                .disabled(commandWorkspace == nil)
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button(strings.addDecryptFile) {
                    commandWorkspace?.selectedSection = .decrypt
                    commandWorkspace?.chooseDecryptFiles()
                }
                .disabled(commandWorkspace == nil)
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }

            CommandMenu("Age") {
                Button(strings.generateKey) {
                    commandWorkspace?.selectedSection = .keys
                    commandWorkspace?.generateKeyPair()
                }
                .disabled(commandWorkspace == nil)
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button(strings.chooseOutputDirectory) {
                    commandWorkspace?.selectedSection = .settings
                    store.chooseOutputDirectory()
                }

                Divider()

                Button(strings.updateCheck()) {
                    updateService.checkForUpdates()
                }

                Divider()

                Button(strings.cancelCurrentTask) {
                    commandWorkspace?.cancelCurrentTask()
                }
                .disabled(commandWorkspace?.currentTask?.status != .running)
            }
        }

        Settings {
            SettingsWindowContent()
                .environmentObject(store)
        }

        Window(strings.aboutAgeMac, id: "about") {
            AboutView()
                .environmentObject(store)
                .environmentObject(updateService)
        }
        .windowResizability(.contentSize)
    }

    private var canShowAllAgeTabs: Bool {
        guard let window = NSApp.keyWindow else { return false }
        return window.tabbingIdentifier == Self.mainWindowTabbingIdentifier
    }

    private func showAllAgeTabs() {
        guard let window = NSApp.keyWindow,
              window.tabbingIdentifier == Self.mainWindowTabbingIdentifier else {
            return
        }
        window.toggleTabOverview(nil)
    }

    private func openMainWindowAsTab() {
        let sourceWindow = NSApp.keyWindow
        guard sourceWindow?.tabbingIdentifier == Self.mainWindowTabbingIdentifier,
              let sourceWindow else {
            openWindow(id: "main")
            return
        }

        let content = MainWindowContent(appStore: store, updateService: updateService, windowRegistry: windowRegistry)
            .frame(minWidth: 1060, minHeight: 720)
            .tint(store.settings.theme.accentColor)
            .background(FocusClearingOverlay())
        let controller = NSHostingController(rootView: content)
        let window = NSWindow(
            contentRect: sourceWindow.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.title = "Age Mac"
        window.minSize = NSSize(width: 1060, height: 720)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = Self.mainWindowTabbingIdentifier
        window.contentViewController = controller
        windowRegistry.retainManualTab(window: window, controller: controller)

        if let tabGroup = sourceWindow.tabGroup {
            tabGroup.addWindow(window)
            tabGroup.selectedWindow = window
        } else {
            sourceWindow.addTabbedWindow(window, ordered: .above)
        }
        window.makeKeyAndOrderFront(nil)
    }

    fileprivate static let mainWindowTabbingIdentifier = "AgeMacMainWindow"
}

@MainActor
private final class WindowWorkspaceRegistry: ObservableObject {
    @Published var focusedWorkspace: WorkspaceStore?
    private var manualTabs: [ObjectIdentifier: OwnedTabWindow] = [:]

    func retainManualTab(window: NSWindow, controller: NSViewController) {
        let key = ObjectIdentifier(window)
        manualTabs[key] = OwnedTabWindow(window: window, controller: controller) { [weak self] in
            self?.releaseManualTab(key)
        }
    }

    private func releaseManualTab(_ key: ObjectIdentifier) {
        guard manualTabs[key] != nil else { return }
        manualTabs[key] = nil
    }
}

@MainActor
private final class OwnedTabWindow {
    let window: NSWindow
    let controller: NSViewController
    private let closeDelegate: ManualTabCloseDelegate

    init(window: NSWindow, controller: NSViewController, onClose: @escaping () -> Void) {
        self.window = window
        self.controller = controller
        closeDelegate = ManualTabCloseDelegate(onClose: onClose)
        window.delegate = closeDelegate
    }
}

@MainActor
private final class ManualTabCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    private var didScheduleClose = false

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        guard !didScheduleClose else { return }
        didScheduleClose = true
        DispatchQueue.main.async { [onClose] in
            onClose()
        }
    }
}

private struct MainWindowContent: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject var updateService: UpdateService
    @ObservedObject var windowRegistry: WindowWorkspaceRegistry
    @StateObject private var workspace: WorkspaceStore

    init(appStore: AppStore, updateService: UpdateService, windowRegistry: WindowWorkspaceRegistry) {
        self.appStore = appStore
        self.updateService = updateService
        self.windowRegistry = windowRegistry
        _workspace = StateObject(wrappedValue: WorkspaceStore(appStore: appStore))
    }

    var body: some View {
        ContentView()
            .environmentObject(appStore)
            .environmentObject(updateService)
            .environmentObject(workspace)
            .focusedSceneObject(workspace)
            .background(MainWindowTabbingConfigurator(
                identifier: AgeMacApp.mainWindowTabbingIdentifier,
                workspace: workspace,
                windowRegistry: windowRegistry
            ))
    }
}

private struct MainWindowTabbingConfigurator: NSViewRepresentable {
    var identifier: String
    var workspace: WorkspaceStore
    @ObservedObject var windowRegistry: WindowWorkspaceRegistry

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configure(from: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(from: nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func configure(from view: NSView, coordinator: Coordinator) {
        let workspace = workspace
        let windowRegistry = windowRegistry
        DispatchQueue.main.async { [weak view, coordinator] in
            guard let window = view?.window else { return }
            window.tabbingMode = .preferred
            window.tabbingIdentifier = identifier
            coordinator.observe(window: window, workspace: workspace, windowRegistry: windowRegistry)
        }
    }

    final class Coordinator {
        private weak var observedWindow: NSWindow?
        private var observer: NSObjectProtocol?

        @MainActor
        func observe(window: NSWindow, workspace: WorkspaceStore, windowRegistry: WindowWorkspaceRegistry) {
            guard observedWindow !== window else {
                if window.isKeyWindow {
                    windowRegistry.focusedWorkspace = workspace
                }
                return
            }

            stopObserving()
            observedWindow = window
            if window.isKeyWindow {
                windowRegistry.focusedWorkspace = workspace
            }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak windowRegistry, weak workspace] _ in
                Task { @MainActor in
                    guard let workspace else { return }
                    windowRegistry?.focusedWorkspace = workspace
                }
            }
        }

        func stopObserving() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
            observedWindow = nil
        }
    }
}
