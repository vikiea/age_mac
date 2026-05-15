import SwiftUI

struct KeysView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        PageHeader(title: "密钥", subtitle: "生成、导入并管理本地 X25519 age 密钥", systemImage: "key.fill")

        GlassCard {
            HStack {
                Label("已保存密钥", systemImage: "key.horizontal")
                    .font(.headline)
                Spacer()
                Button {
                    store.importKeyFromFile()
                } label: {
                    Label("从文件导入", systemImage: "square.and.arrow.down")
                }
                Button {
                    store.generateKeyPair()
                } label: {
                    Label("生成密钥", systemImage: "sparkles")
                }
            }

            if store.keys.isEmpty {
                ContentUnavailableView("没有密钥", systemImage: "key", description: Text("生成或导入一个 age 密钥"))
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                ForEach(store.keys) { key in
                    KeyRowView(key: key)
                    Divider()
                }
            }
        }

        GlassCard {
            Label("手动导入", systemImage: "keyboard")
                .font(.headline)
            TextField("名称", text: $store.importKeyName)
                .textFieldStyle(.roundedBorder)
            TextField("公钥", text: $store.importPublicKey, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            TextField("私钥（可选）", text: $store.importPrivateKey, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            HStack {
                Spacer()
                Button {
                    store.importKey()
                } label: {
                    Label("导入", systemImage: "plus.circle")
                }
            }
        }
    }
}

private struct KeyRowView: View {
    @EnvironmentObject private var store: AppStore
    var key: KeyEntry
    @State private var draftName: String
    @FocusState private var nameFocused: Bool

    init(key: KeyEntry) {
        self.key = key
        _draftName = State(initialValue: key.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    TextField("密钥名称", text: $draftName)
                        .font(.headline)
                        .textFieldStyle(.plain)
                        .focused($nameFocused)
                        .onSubmit { saveName() }
                        .onChange(of: nameFocused) { _, focused in
                            if !focused {
                                saveName()
                            }
                        }
                    Text(AppFormatters.dateTime.string(from: key.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if key.hasPrivateKey {
                    Label("含私钥", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                actionButtons
            }

            Text(key.publicKey)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
        }
        .padding(.vertical, 8)
        .onChange(of: key.name) { _, newValue in
            draftName = newValue
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                store.exportKey(key)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .disabled(!key.hasPrivateKey)
            .help("验证后导出密钥")

            Button {
                store.revealPrivateKey(key)
            } label: {
                Image(systemName: "eye")
            }
            .buttonStyle(.borderless)
            .disabled(!key.hasPrivateKey)
            .help("验证后查看私钥")

            Button {
                store.deleteKey(key)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除")
        }
    }

    private func saveName() {
        guard draftName != key.name else { return }
        store.renameKey(key, to: draftName)
    }
}
