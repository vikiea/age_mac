/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import AppKit
import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var updateService: UpdateService

    var body: some View {
        ZStack {
            DetailBackground(theme: store.settings.theme)

            VStack(alignment: .leading, spacing: 18) {
                header

                GlassCard {
                    Label("作者", systemImage: "person.crop.circle")
                        .font(.headline)
                    Text("vikiea <vikiea@users.noreply.github.com>")
                        .textSelection(.enabled)
                }

                GlassCard {
                    Label("项目", systemImage: "curlybraces")
                        .font(.headline)
                    LinkRow(title: "GitHub", subtitle: "github.com/vikiea/age_mac", systemImage: "chevron.left.forwardslash.chevron.right", url: AppLinks.repository)
                    LinkRow(title: "隐私协议", subtitle: "本地优先的数据处理说明", systemImage: "hand.raised", url: AppLinks.privacy)
                    LinkRow(title: "开源协议", subtitle: "MIT License", systemImage: "doc.text", url: AppLinks.license)
                    LinkRow(title: "版本发布", subtitle: "GitHub Releases", systemImage: "shippingbox", url: AppLinks.releases)
                }

                GlassCard {
                    HStack {
                        Label("开源组件", systemImage: "square.stack.3d.up")
                            .font(.headline)
                        Spacer()
                        Button {
                            updateService.checkForUpdates()
                        } label: {
                            Label("检测更新", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }

                    ComponentRow(name: "Sparkle", purpose: "macOS 在线更新", license: "MIT")
                    ComponentRow(name: "filippo.io/age", purpose: "age 加密格式与 X25519 支持", license: "BSD-style")
                    ComponentRow(name: "SwiftUI / AppKit", purpose: "macOS 原生界面", license: "Apple SDK")
                    ComponentRow(name: "Go", purpose: "流式加解密引擎", license: "BSD-style")
                }
            }
            .padding(24)
        }
        .frame(width: 560, height: 620)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 5) {
                Text("Age Mac")
                    .font(.largeTitle.weight(.semibold))
                Text("版本 \(versionText)")
                    .foregroundStyle(.secondary)
                Text("本地优先的 age 文件加解密工具")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appIcon: NSImage {
        NSApp.applicationIconImage ?? NSImage(size: NSSize(width: 72, height: 72))
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "开发版"
        let build = info?["CFBundleVersion"] as? String
        guard let build, build != shortVersion else { return shortVersion }
        return "\(shortVersion) (\(build))"
    }
}

private struct LinkRow: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ComponentRow: View {
    var name: String
    var purpose: String
    var license: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Text(purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(license)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
