import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "设置", subtitle: "输出目录、同名文件策略和任务参数", systemImage: "gearshape.fill")

            GlassCard {
                Label("输出", systemImage: "folder")
                    .font(.headline)

                HStack {
                    Text(AppFormatters.shortPath(store.settings.outputDirectory))
                        .lineLimit(1)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        store.chooseOutputDirectory()
                    } label: {
                        Label("选择目录", systemImage: "folder")
                    }
                }

                Picker("同名文件", selection: $store.settings.duplicateStrategy) {
                    ForEach(DuplicateStrategy.allCases) { strategy in
                        Text(strategy.title).tag(strategy)
                    }
                }
                .onChange(of: store.settings.duplicateStrategy) { _, _ in store.saveSettings() }
            }

            GlassCard {
                Label("任务", systemImage: "cpu")
                    .font(.headline)

                Stepper(value: $store.settings.concurrency, in: 1...12) {
                    Text("并发上限 \(store.settings.concurrency)")
                }
                .onChange(of: store.settings.concurrency) { _, _ in store.saveSettings() }

                Toggle("默认压缩", isOn: $store.settings.compressEnabled)
                    .onChange(of: store.settings.compressEnabled) { _, _ in store.saveSettings() }
            }

            GlassCard {
                Label("主题", systemImage: "paintpalette")
                    .font(.headline)

                Picker("颜色主题", selection: $store.settings.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        HStack {
                            ThemeSwatch(theme: theme)
                            Text(theme.title)
                        }
                        .tag(theme)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: store.settings.theme) { _, _ in store.saveSettings() }

                HStack(spacing: 10) {
                    ForEach(AppTheme.allCases) { theme in
                        Button {
                            store.settings.theme = theme
                            store.saveSettings()
                        } label: {
                            ThemeSwatch(theme: theme)
                                .overlay {
                                    if store.settings.theme == theme {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(theme.title)
                    }
                }
            }
        }
    }
}

private struct ThemeSwatch: View {
    var theme: AppTheme

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(LinearGradient(colors: theme.swatchColors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 34, height: 22)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.white.opacity(0.35), lineWidth: 1)
            }
            .accessibilityLabel(theme.title)
    }
}
