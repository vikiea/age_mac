/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import SwiftUI

struct EncryptView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let strings = store.strings

        PageHeader(
            title: AppSection.encrypt.title(in: store.settings.language),
            subtitle: strings.encryptSubtitle,
            systemImage: "lock.fill"
        )

        TaskStatusCard(task: store.encryptTask) {
            store.removeCurrentTask(kind: .encrypt)
        }

        GlassCard {
            HStack(spacing: 12) {
                modePicker

                Toggle(strings.defaultCompress, isOn: $store.settings.compressEnabled)
                    .onChange(of: store.settings.compressEnabled) { _, _ in store.saveSettings() }
                    .fixedSize()

                Text(store.encryptMode.detail(in: store.settings.language))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if store.encryptMode == .batchPack {
                archiveNameRow
            }
        }

        GlassCard {
            authModePicker

            if store.encryptAuthMode == .passphrase {
                SecureField(strings.passphrase, text: $store.encryptPassphrase)
                    .textFieldStyle(.roundedBorder)
            } else {
                KeyPicker(title: strings.savedPublicKeys, keys: store.keys, selection: $store.selectedEncryptKeyID, requiresPrivateKey: false)
                if store.selectedEncryptKeyID == nil {
                    TextField(strings.pastePublicKeyPlaceholder(), text: $store.publicKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .textSelection(.enabled)
                }
            }
        }

        GlassCard {
            HStack {
                Label(strings.inputFiles, systemImage: "tray.and.arrow.down")
                    .font(.headline)
                Spacer()
                Button {
                    store.chooseEncryptFiles()
                } label: {
                    Label(strings.addFiles, systemImage: "plus")
                }
                Button {
                    store.chooseEncryptFolder()
                } label: {
                    Label(strings.addFolder, systemImage: "folder.badge.plus")
                }
                Button(strings.clear) {
                    store.clearEncryptFiles()
                }
                .disabled(store.encryptFiles.isEmpty)
            }

            FileListView(files: store.encryptFiles) { file in
                store.removeEncryptFile(file)
            }

            PrimaryActionCell(
                title: strings.startEncrypt,
                subtitle: strings.encryptedOutputSubtitle(AppFormatters.shortPath(store.settings.outputDirectory)),
                systemImage: "lock.fill",
                disabled: !store.canStartEncrypt
            ) {
                store.startEncrypt()
            }
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private var modePicker: some View {
        Picker(store.strings.encryptMode, selection: $store.encryptMode) {
            ForEach(EncryptionMode.allCases) { mode in
                Text(mode.title(in: store.settings.language)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
    }

    private var archiveNameRow: some View {
        HStack(spacing: 10) {
            TextField(store.strings.archiveNamePlaceholder, text: $store.archiveBaseName)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120)
            Text(store.settings.compressEnabled ? ".tar.gz.age" : ".tar.age")
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    private var authModePicker: some View {
        Picker(store.strings.encryptMethod, selection: $store.encryptAuthMode) {
            ForEach(AuthMode.allCases) { mode in
                Text(mode.title(in: store.settings.language)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
    }
}
