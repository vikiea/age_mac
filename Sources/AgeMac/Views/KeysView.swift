/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import SwiftUI

struct KeysView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let strings = store.strings

        PageHeader(
            title: AppSection.keys.title(in: store.settings.language),
            subtitle: strings.keysSubtitle,
            systemImage: "key.fill"
        )

        GlassCard {
            HStack {
                Label(strings.keysTitle, systemImage: "key.horizontal")
                    .font(.headline)
                Spacer()
                Button {
                    store.importKeyFromFile()
                } label: {
                    Label(strings.importFromFile, systemImage: "square.and.arrow.down")
                }
                Button {
                    store.generateKeyPair()
                } label: {
                    Label(strings.generateKey, systemImage: "sparkles")
                }
            }

            if store.keys.isEmpty {
                ContentUnavailableView(strings.noKeysTitle, systemImage: "key", description: Text(strings.noKeysDescription))
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                ForEach(store.keys) { key in
                    KeyRowView(key: key)
                    Divider()
                }
            }
        }

        GlassCard {
            Label(strings.manualImport, systemImage: "keyboard")
                .font(.headline)
            TextField(strings.keyName, text: $store.importKeyName)
                .textFieldStyle(.roundedBorder)
            TextField(strings.publicKey, text: $store.importPublicKey, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            TextField(strings.privateKeyOptional, text: $store.importPrivateKey, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            HStack {
                Spacer()
                Button {
                    store.importKey()
                } label: {
                    Label(strings.importKey, systemImage: "plus.circle")
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
                    TextField(store.strings.keyName, text: $draftName)
                        .font(.headline)
                        .textFieldStyle(.plain)
                        .focused($nameFocused)
                        .onSubmit { saveName() }
                        .onChange(of: nameFocused) { _, focused in
                            if !focused {
                                saveName()
                            }
                        }
                    Text(AppFormatters.dateTime(key.createdAt, language: store.settings.language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if key.hasPrivateKey {
                    Label(store.strings.hasPrivateKey, systemImage: "checkmark.seal.fill")
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
            .help(store.strings.exportKeyHelp)

            Button {
                store.revealPrivateKey(key)
            } label: {
                Image(systemName: "eye")
            }
            .buttonStyle(.borderless)
            .disabled(!key.hasPrivateKey)
            .help(store.strings.revealPrivateKeyHelp)

            Button {
                store.deleteKey(key)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(store.strings.delete)
        }
    }

    private func saveName() {
        guard draftName != key.name else { return }
        store.renameKey(key, to: draftName)
    }
}
