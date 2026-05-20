/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let strings = store.strings

        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                title: AppSection.settings.title(in: store.settings.language),
                subtitle: strings.outputAndTaskSubtitle,
                systemImage: "gearshape.fill"
            )

            GlassCard {
                Label(strings.output, systemImage: "folder")
                    .font(.headline)

                HStack {
                    Text(AppFormatters.shortPath(store.settings.outputDirectory))
                        .lineLimit(1)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        store.chooseOutputDirectory()
                    } label: {
                        Label(strings.chooseDirectory, systemImage: "folder")
                    }
                }

                Picker(strings.duplicateFiles, selection: $store.settings.duplicateStrategy) {
                    ForEach(DuplicateStrategy.allCases) { strategy in
                        Text(strategy.title(in: store.settings.language)).tag(strategy)
                    }
                }
                .onChange(of: store.settings.duplicateStrategy) { _, _ in store.saveSettings() }
            }

            GlassCard {
                Label(strings.task, systemImage: "cpu")
                    .font(.headline)

                Stepper(value: $store.settings.concurrency, in: 1...12) {
                    Text(strings.concurrencyLimit(store.settings.concurrency))
                }
                .onChange(of: store.settings.concurrency) { _, _ in store.saveSettings() }

                Toggle(strings.defaultCompress, isOn: $store.settings.compressEnabled)
                    .onChange(of: store.settings.compressEnabled) { _, _ in store.saveSettings() }
            }

            GlassCard {
                Label(strings.languageLabel, systemImage: "globe")
                    .font(.headline)

                Picker(strings.settingsLanguageSubtitle, selection: $store.settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: store.settings.language) { _, _ in store.saveSettings() }
            }

            GlassCard {
                Label(strings.theme, systemImage: "paintpalette")
                    .font(.headline)

                Picker(strings.colorTheme, selection: $store.settings.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        HStack {
                            ThemeSwatch(theme: theme)
                            Text(theme.title(in: store.settings.language))
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
                        .help(theme.title(in: store.settings.language))
                    }
                }

                Divider()

                Toggle(strings.gaussianTransparency, isOn: $store.settings.gaussianTransparencyEnabled)
                    .onChange(of: store.settings.gaussianTransparencyEnabled) { _, _ in store.saveSettings() }

                if store.settings.gaussianTransparencyEnabled {
                    GaussianTransparencyControl()
                }
            }
        }
    }
}

private struct GaussianTransparencyControl: View {
    @EnvironmentObject private var store: AppStore
    @State private var draftOpacity = Double(AppSettings.defaults().gaussianTransparencyOpacity)
    @State private var isEditing = false
    @State private var pendingSaveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(store.strings.gaussianOpacity)
                Spacer()
                Text("\(displayedOpacity)%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { draftOpacity },
                    set: { newValue in
                        let opacity = Int(newValue.rounded())
                        draftOpacity = Double(opacity)
                        store.previewGaussianTransparencyOpacity(opacity)
                    }
                ),
                in: 0...100,
                step: 1,
                onEditingChanged: { editing in
                    isEditing = editing
                    if editing {
                        pendingSaveTask?.cancel()
                        draftOpacity = Double(store.settings.gaussianTransparencyOpacity)
                    } else {
                        commitSettledOpacity()
                    }
                }
            )
        }
        .onAppear {
            draftOpacity = Double(store.settings.gaussianTransparencyOpacity)
        }
        .onChange(of: store.settings.gaussianTransparencyOpacity) { _, newValue in
            if !isEditing {
                draftOpacity = Double(newValue)
            }
        }
        .onDisappear {
            pendingSaveTask?.cancel()
            store.cancelGaussianTransparencyOpacityPreview()
        }
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
    }

    private var displayedOpacity: Int {
        Int(draftOpacity.rounded())
    }

    private func commitSettledOpacity() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            let opacity = Int(draftOpacity.rounded())
            store.commitGaussianTransparencyOpacity(opacity)
            draftOpacity = Double(store.settings.gaussianTransparencyOpacity)
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
    }
}
