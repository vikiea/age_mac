import SwiftUI

struct EncryptView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        PageHeader(title: "加密", subtitle: "打包、压缩并用 age 流式加密本地文件", systemImage: "lock.fill")

        TaskStatusCard(task: store.encryptTask) {
            store.removeCurrentTask(kind: .encrypt)
        }

        GlassCard {
            HStack(spacing: 12) {
                modePicker

                Toggle("压缩", isOn: $store.settings.compressEnabled)
                    .onChange(of: store.settings.compressEnabled) { _, _ in store.saveSettings() }
                    .fixedSize()

                Text(store.encryptMode.detail)
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
                SecureField("密码", text: $store.encryptPassphrase)
                    .textFieldStyle(.roundedBorder)
            } else {
                KeyPicker(title: "已保存公钥", keys: store.keys, selection: $store.selectedEncryptKeyID, requiresPrivateKey: false)
                if store.selectedEncryptKeyID == nil {
                    TextField("或粘贴 age 公钥", text: $store.publicKeyInput)
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
                    store.chooseEncryptFiles()
                } label: {
                    Label("添加文件", systemImage: "plus")
                }
                Button {
                    store.chooseEncryptFolder()
                } label: {
                    Label("添加文件夹", systemImage: "folder.badge.plus")
                }
                Button("清空") {
                    store.clearEncryptFiles()
                }
                .disabled(store.encryptFiles.isEmpty)
            }

            FileListView(files: store.encryptFiles) { file in
                store.removeEncryptFile(file)
            }

            PrimaryActionCell(
                title: "开始加密",
                subtitle: "输出到 \(AppFormatters.shortPath(store.settings.outputDirectory))/encrypted",
                systemImage: "lock.fill",
                disabled: !store.canStartEncrypt
            ) {
                store.startEncrypt()
            }
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private var modePicker: some View {
        Picker("模式", selection: $store.encryptMode) {
            ForEach(EncryptionMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
    }

    private var archiveNameRow: some View {
        HStack(spacing: 10) {
            TextField("输出文件名", text: $store.archiveBaseName)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120)
            Text(store.settings.compressEnabled ? ".tar.gz.age" : ".tar.age")
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    private var authModePicker: some View {
        Picker("加密方式", selection: $store.encryptAuthMode) {
            ForEach(AuthMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
    }
}
