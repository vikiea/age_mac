/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import AppKit
import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var keys: [KeyEntry] = []
    @Published var operations: [OperationRecord] = []
    @Published var settings: AppSettings = .defaults()
    @Published private(set) var renderedGaussianTransparencyOpacity = AppSettings.defaults().gaussianTransparencyOpacity
    @Published var alertMessage: String?

    private let persistence: AppPersistence
    private let keychain = KeychainSecretStore()

    var strings: AppStrings {
        AppStrings(language: settings.language)
    }

    init(persistence: AppPersistence = AppPersistence()) {
        self.persistence = persistence
        loadState()
        importAgeConfigKeysIfNeeded()
    }

    var effectiveGaussianTransparencyOpacity: Int {
        renderedGaussianTransparencyOpacity
    }

    func chooseOutputDirectory() {
        guard let folder = FilePanelService.chooseFolder() else { return }
        settings.outputDirectory = folder.path
        saveSettings()
    }

    func generateKeyPairForWorkspace() async -> KeyEntry? {
        let language = settings.language
        do {
            let key = try await Task.detached {
                try AgeEngineClient().generateKeyPair(language: language)
            }.value
            let storedKey = storePrivateKeyIfNeeded(for: key)
            keys.insert(storedKey, at: 0)
            saveKeys()
            return storedKey
        } catch {
            alertMessage = localizedErrorDescription(error)
            return nil
        }
    }

    func importKey(name draftName: String, publicKey draftPublicKey: String, privateKey draftPrivateKey: String) -> KeyEntry? {
        let publicKey = draftPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let privateKey = draftPrivateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !publicKey.isEmpty else {
            alertMessage = strings.requirePublicKey()
            return nil
        }
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        var key = KeyEntry(
            id: UUID(),
            name: name.isEmpty ? "Imported key" : name,
            publicKey: publicKey,
            privateKey: privateKey.isEmpty ? nil : privateKey,
            createdAt: Date()
        )
        if !privateKey.isEmpty {
            key = storePrivateKeyIfNeeded(for: key)
        }
        keys.insert(key, at: 0)
        saveKeys()
        return key
    }

    func importKeyFromFile() {
        guard let url = FilePanelService.chooseFile() else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let imported = importKeys(from: text, fallbackName: url.deletingPathExtension().lastPathComponent)
            alertMessage = imported == 0 ? strings.autoImportNoNewKeys : strings.importedKeys(imported)
        } catch {
            alertMessage = strings.importKeyFileFailed(error.localizedDescription)
        }
    }

    func renameKey(_ key: KeyEntry, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alertMessage = strings.requireKeyName()
            return
        }
        guard let index = keys.firstIndex(where: { $0.id == key.id }) else { return }
        keys[index].name = trimmed
        saveKeys()
    }

    func revealPrivateKey(_ key: KeyEntry) {
        guard key.hasPrivateKey else {
            alertMessage = strings.missingPrivateKey()
            return
        }

        Task {
            do {
                let allowed = try await LocalAuthenticationService.authenticate(reason: strings.revealPrivateKeyHelp)
                guard allowed else { return }
                guard let privateKey = privateKey(for: key), !privateKey.isEmpty else {
                    alertMessage = strings.missingPrivateKey()
                    return
                }
                alertMessage = privateKey
            } catch {
                alertMessage = strings.authFailed(error.localizedDescription)
            }
        }
    }

    func exportKey(_ key: KeyEntry) {
        guard key.hasPrivateKey else {
            alertMessage = strings.missingPrivateKey()
            return
        }

        Task {
            do {
                let allowed = try await LocalAuthenticationService.authenticate(reason: strings.exportKeyHelp)
                guard allowed else { return }
                guard let privateKey = privateKey(for: key), !privateKey.isEmpty else {
                    alertMessage = strings.missingPrivateKey()
                    return
                }
                saveKeyFile(key.withPrivateKey(privateKey))
            } catch {
                alertMessage = strings.authFailed(error.localizedDescription)
            }
        }
    }

    func deleteKey(_ key: KeyEntry) {
        keychain.deletePrivateKey(for: key.id)
        keys.removeAll { $0.id == key.id }
        saveKeys()
    }

    func reveal(path: String) {
        FilePanelService.reveal(path: path)
    }

    func clearHistory() {
        operations.removeAll()
        saveHistory()
    }

    func removeOperation(id: UUID) {
        operations.removeAll { $0.id == id }
        saveHistory()
    }

    func addOperation(_ record: OperationRecord) {
        operations.insert(record, at: 0)
        saveHistory()
    }

    func updateOperation(id: UUID, mutate: (inout OperationRecord) -> Void) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        mutate(&operations[index])
        saveHistory()
    }

    func saveSettings() {
        let clampedConcurrency = min(max(settings.concurrency, 1), 12)
        if settings.concurrency != clampedConcurrency {
            settings.concurrency = clampedConcurrency
        }

        let clampedOpacity = AppSettings.clampGaussianTransparencyOpacity(settings.gaussianTransparencyOpacity)
        if settings.gaussianTransparencyOpacity != clampedOpacity {
            settings.gaussianTransparencyOpacity = clampedOpacity
        }
        if renderedGaussianTransparencyOpacity != settings.gaussianTransparencyOpacity {
            renderedGaussianTransparencyOpacity = settings.gaussianTransparencyOpacity
        }

        NSApp.appearance = settings.appearance.nsAppearance
        persistSettings()
    }

    func previewGaussianTransparencyOpacity(_ opacity: Int) {
        updateGaussianTransparencyOpacity(opacity)
    }

    func cancelGaussianTransparencyOpacityPreview() {
        let clampedOpacity = AppSettings.clampGaussianTransparencyOpacity(settings.gaussianTransparencyOpacity)
        guard renderedGaussianTransparencyOpacity != clampedOpacity else { return }
        renderedGaussianTransparencyOpacity = clampedOpacity
    }

    func commitGaussianTransparencyOpacity(_ opacity: Int) {
        updateGaussianTransparencyOpacity(opacity)
        saveSettings()
    }

    func localizedErrorDescription(_ error: Error) -> String {
        if let engineError = error as? EngineClientError {
            return engineError.errorDescription(in: settings.language)
        }
        return error.localizedDescription
    }

    func privateKey(for key: KeyEntry) -> String? {
        if let inlinePrivateKey = key.privateKey, !inlinePrivateKey.isEmpty {
            return inlinePrivateKey
        }
        return try? keychain.readPrivateKey(for: key.id)
    }

    private func updateGaussianTransparencyOpacity(_ opacity: Int) {
        let clampedOpacity = AppSettings.clampGaussianTransparencyOpacity(opacity)
        if renderedGaussianTransparencyOpacity != clampedOpacity {
            renderedGaussianTransparencyOpacity = clampedOpacity
        }
        if settings.gaussianTransparencyOpacity != clampedOpacity {
            settings.gaussianTransparencyOpacity = clampedOpacity
        }
    }

    private func saveKeyFile(_ key: KeyEntry) {
        let defaultName = sanitizedFileName(key.name)
        guard let url = FilePanelService.saveFile(defaultName: defaultName) else { return }
        do {
            let text = KeyFileCodec.exportText(for: key)
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            alertMessage = strings.saveKeyFailed(error.localizedDescription)
        }
    }

    private func sanitizedFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let parts = name.components(separatedBy: invalid).filter { !$0.isEmpty }
        let value = parts.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "age-key" : value
    }

    private func loadState() {
        let state = persistence.load()
        keys = state.keys
        migrateInlinePrivateKeysToKeychain()
        operations = state.operations
        settings = state.settings
        renderedGaussianTransparencyOpacity = settings.gaussianTransparencyOpacity
    }

    @discardableResult
    private func importKeys(from text: String, fallbackName: String) -> Int {
        let parsed = KeyFileCodec.parseMany(text, fallbackName: fallbackName)
        var existingPublicKeys = Set(keys.map(\.publicKey).filter { !$0.isEmpty })
        var existingPrivateKeys = Set(keys.compactMap { privateKey(for: $0) }.filter { !$0.isEmpty })
        var additions: [KeyEntry] = []
        for key in parsed {
            let publicExists = !key.publicKey.isEmpty && existingPublicKeys.contains(key.publicKey)
            let privateExists = key.privateKey.map { existingPrivateKeys.contains($0) } ?? false
            guard !publicExists && !privateExists else { continue }
            let storedKey = storePrivateKeyIfNeeded(for: key)
            additions.append(storedKey)
            existingPublicKeys.insert(key.publicKey)
            if let privateKey = key.privateKey, !privateKey.isEmpty {
                existingPrivateKeys.insert(privateKey)
            }
        }
        guard !additions.isEmpty else { return 0 }
        keys.insert(contentsOf: additions, at: 0)
        saveKeys()
        return additions.count
    }

    private func importAgeConfigKeysIfNeeded() {
        let ageDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/age", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: ageDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return
        }

        var imported = 0
        for item in enumerator {
            guard let url = item as? URL else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true,
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            imported += importKeys(from: text, fallbackName: url.deletingPathExtension().lastPathComponent)
        }
        if imported > 0 {
            alertMessage = strings.importedAgeConfigKeys(imported)
        }
    }

    private func saveKeys() {
        do {
            try persistence.saveKeys(keys)
        } catch {
            alertMessage = strings.savedStateFailed(error.localizedDescription)
        }
    }

    private func storePrivateKeyIfNeeded(for key: KeyEntry) -> KeyEntry {
        guard let privateKey = key.privateKey, !privateKey.isEmpty else { return key }
        do {
            try keychain.savePrivateKey(privateKey, for: key.id)
            return key.withPrivateKey(nil, privateKeyStored: true)
        } catch {
            alertMessage = strings.savedStateFailed(error.localizedDescription)
            return key
        }
    }

    private func migrateInlinePrivateKeysToKeychain() {
        var changed = false
        for index in keys.indices {
            guard let privateKey = keys[index].privateKey, !privateKey.isEmpty else { continue }
            do {
                try keychain.savePrivateKey(privateKey, for: keys[index].id)
                keys[index] = keys[index].withPrivateKey(nil, privateKeyStored: true)
                changed = true
            } catch {
                alertMessage = strings.savedStateFailed(error.localizedDescription)
            }
        }
        if changed {
            saveKeys()
        }
    }

    private func persistSettings() {
        do {
            try persistence.saveSettings(settings)
        } catch {
            alertMessage = strings.savedStateFailed(error.localizedDescription)
        }
    }

    private func saveHistory() {
        do {
            operations = Array(operations.prefix(AppPersistence.historyLimit))
            try persistence.saveHistory(operations)
        } catch {
            alertMessage = strings.savedStateFailed(error.localizedDescription)
        }
    }
}
