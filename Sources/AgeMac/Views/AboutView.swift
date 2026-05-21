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
        let strings = store.strings

        ZStack {
            DetailBackground(
                theme: store.settings.theme,
                gaussianTransparencyEnabled: store.settings.gaussianTransparencyEnabled,
                gaussianTransparencyOpacity: store.effectiveGaussianTransparencyOpacity
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    GlassCard {
                        Label(strings.project, systemImage: "curlybraces")
                            .font(.headline)
                        LinkRow(title: "GitHub", subtitle: "github.com/vikiea/age_mac", systemImage: "chevron.left.forwardslash.chevron.right", url: AppLinks.repository)
                        LinkRow(title: strings.privacyPolicyTitle(), subtitle: strings.privacyPolicySubtitle(), systemImage: "hand.raised", url: AppLinks.privacy)
                        LinkRow(title: strings.licenseTitle(), subtitle: "MIT License", systemImage: "doc.text", url: AppLinks.license)
                        LinkRow(title: strings.releasesTitle(), subtitle: "GitHub Releases", systemImage: "shippingbox", url: AppLinks.releases)
                    }

                    GlassCard {
                        HStack {
                            Label(strings.openSourceComponents, systemImage: "square.stack.3d.up")
                                .font(.headline)
                            Spacer()
                            Button {
                                updateService.checkForUpdates()
                            } label: {
                                Label(strings.updateCheck(), systemImage: "arrow.triangle.2.circlepath")
                            }
                        }

                        ComponentRow(name: "Sparkle", purpose: strings.sparklePurpose(), license: "MIT")
                        ComponentRow(name: "filippo.io/age", purpose: strings.ageLibraryPurpose(), license: "BSD-style")
                        ComponentRow(name: "SwiftUI / AppKit", purpose: strings.appleUIPurpose(), license: "Apple SDK")
                        ComponentRow(name: "Go", purpose: strings.goPurpose(), license: "BSD-style")
                    }
                }
                .padding(.top, 54)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollClipDisabled()
        }
        .frame(width: 580, height: 620)
        .gaussianWindowTranslucency(enabled: store.settings.gaussianTransparencyEnabled)
        .windowAppearance(store.settings.appearance)
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
                Text(store.strings.version(versionText))
                    .foregroundStyle(.secondary)
                Text(store.strings.appDescription())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appIcon: NSImage {
        NSApp.applicationIconImage ?? NSImage(size: NSSize(width: 72, height: 72))
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? store.strings.versionFallback
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
