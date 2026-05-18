/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import SwiftUI

struct DecryptView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        PageHeader(title: "解密", subtitle: "解密 .age 文件并自动展开 tar 或 tar.gz 内容", systemImage: "lock.open.fill")

        TaskStatusCard(task: store.decryptTask) {
            store.removeCurrentTask(kind: .decrypt)
        }

        GlassCard {
            authModePicker

            if store.decryptAuthMode == .passphrase {
                SecureField("密码", text: $store.decryptPassphrase)
                    .textFieldStyle(.roundedBorder)
            } else {
                KeyPicker(title: "已保存私钥", keys: store.keys, selection: $store.selectedDecryptKeyID, requiresPrivateKey: true)
                if store.selectedDecryptKeyID == nil {
                    TextField("或粘贴 age 私钥", text: $store.privateKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .textSelection(.enabled)
                }
            }
        }

        GlassCard {
            HStack {
                Label("输入文件", systemImage: "tray.and.arrow.down")
                    .font(.headline)
                Spacer()
                Button {
                    store.chooseDecryptFiles()
                } label: {
                    Label("添加 .age", systemImage: "plus")
                }
                Button {
                    store.chooseDecryptFolder()
                } label: {
                    Label("扫描文件夹", systemImage: "folder.badge.plus")
                }
                Button("清空") {
                    store.clearDecryptFiles()
                }
                .disabled(store.decryptFiles.isEmpty)
            }

            FileListView(files: store.decryptFiles) { file in
                store.removeDecryptFile(file)
            }

            PrimaryActionCell(
                title: "开始解密",
                subtitle: "输出到 \(AppFormatters.shortPath(store.settings.outputDirectory))/decrypted",
                systemImage: "lock.open.fill",
                disabled: !store.canStartDecrypt
            ) {
                store.startDecrypt()
            }
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private var authModePicker: some View {
        Picker("解密方式", selection: $store.decryptAuthMode) {
            ForEach(AuthMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
    }
}
