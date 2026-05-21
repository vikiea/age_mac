/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import SwiftUI

struct DecryptView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        let strings = store.strings

        PageHeader(
            title: AppSection.decrypt.title(in: store.settings.language),
            subtitle: strings.decryptSubtitle,
            systemImage: "lock.open.fill"
        )

        TaskStatusCard(task: workspace.decryptTask) {
            workspace.removeCurrentTask(kind: .decrypt)
        }

        GlassCard {
            authModePicker

            if workspace.decryptAuthMode == .passphrase {
                SecureField(strings.passphrase, text: $workspace.decryptPassphrase)
                    .textFieldStyle(.roundedBorder)
            } else {
                KeyPicker(title: strings.savedPrivateKeys, keys: store.keys, selection: $workspace.selectedDecryptKeyID, requiresPrivateKey: true)
                if workspace.selectedDecryptKey == nil {
                    TextField(strings.pastePrivateKeyPlaceholder(), text: $workspace.privateKeyInput)
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
                    workspace.chooseDecryptFiles()
                } label: {
                    Label(strings.addEncryptedAge, systemImage: "plus")
                }
                Button {
                    workspace.chooseDecryptFolder()
                } label: {
                    Label(strings.scanFolder, systemImage: "folder.badge.plus")
                }
                Button(strings.clear) {
                    workspace.clearDecryptFiles()
                }
                .disabled(workspace.decryptFiles.isEmpty)
            }

            FileListView(files: workspace.decryptFiles) { file in
                workspace.removeDecryptFile(file)
            }

            PrimaryActionCell(
                title: strings.startDecrypt,
                subtitle: strings.decryptedOutputSubtitle(AppFormatters.shortPath(store.settings.outputDirectory)),
                systemImage: "lock.open.fill",
                disabled: !workspace.canStartDecrypt
            ) {
                workspace.startDecrypt()
            }
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private var authModePicker: some View {
        Picker(store.strings.decryptMethod, selection: $workspace.decryptAuthMode) {
            ForEach(AuthMode.allCases) { mode in
                Text(mode.title(in: store.settings.language)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
    }
}
