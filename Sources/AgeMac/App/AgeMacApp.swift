/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("Age Mac") {
            ContentView()
                .environmentObject(store)
                .environmentObject(updateService)
                .frame(minWidth: 1060, minHeight: 720)
                .tint(store.settings.theme.accentColor)
                .background(FocusClearingOverlay())
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 Age Mac") {
                    openWindow(id: "about")
                }
            }

            CommandGroup(after: .newItem) {
                Button("添加加密文件") {
                    store.selectedSection = .encrypt
                    store.chooseEncryptFiles()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("添加解密文件") {
                    store.selectedSection = .decrypt
                    store.chooseDecryptFiles()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }

            CommandMenu("Age") {
                Button("生成密钥") {
                    store.selectedSection = .keys
                    store.generateKeyPair()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("选择输出目录") {
                    store.selectedSection = .settings
                    store.chooseOutputDirectory()
                }

                Divider()

                Button("检测更新") {
                    updateService.checkForUpdates()
                }

                Divider()

                Button("取消当前任务") {
                    store.cancelCurrentTask()
                }
                .disabled(store.currentTask?.status != .running)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .padding()
                .frame(width: 620)
        }

        Window("关于 Age Mac", id: "about") {
            AboutView()
                .environmentObject(store)
                .environmentObject(updateService)
        }
        .windowResizability(.contentSize)
    }
}
