/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import SwiftUI

struct DecryptView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let strings = store.strings

        PageHeader(
            title: AppSection.decrypt.title(in: store.settings.language),
            subtitle: strings.decryptSubtitle,
            systemImage: "lock.open.fill"
        )

        TaskStatusCard(task: store.decryptTask) {
            store.removeCurrentTask(kind: .decrypt)
        }

        GlassCard {
            authModePicker

            if store.decryptAuthMode == .passphrase {
                SecureField(strings.passphrase, text: $store.decryptPassphrase)
                    .textFieldStyle(.roundedBorder)
            } else {
                KeyPicker(title: strings.savedPrivateKeys, keys: store.keys, selection: $store.selectedDecryptKeyID, requiresPrivateKey: true)
                if store.selectedDecryptKeyID == nil {
                    TextField(strings.pastePrivateKeyPlaceholder(), text: $store.privateKeyInput)
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
                    store.chooseDecryptFiles()
                } label: {
                    Label(strings.addEncryptedAge, systemImage: "plus")
                }
                Button {
                    store.chooseDecryptFolder()
                } label: {
                    Label(strings.scanFolder, systemImage: "folder.badge.plus")
                }
                Button(strings.clear) {
                    store.clearDecryptFiles()
                }
                .disabled(store.decryptFiles.isEmpty)
            }

            FileListView(files: store.decryptFiles) { file in
                store.removeDecryptFile(file)
            }

            PrimaryActionCell(
                title: strings.startDecrypt,
                subtitle: strings.decryptedOutputSubtitle(AppFormatters.shortPath(store.settings.outputDirectory)),
                systemImage: "lock.open.fill",
                disabled: !store.canStartDecrypt
            ) {
                store.startDecrypt()
            }
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private var authModePicker: some View {
        Picker(store.strings.decryptMethod, selection: $store.decryptAuthMode) {
            ForEach(AuthMode.allCases) { mode in
                Text(mode.title(in: store.settings.language)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
    }
}
