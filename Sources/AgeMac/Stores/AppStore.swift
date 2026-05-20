/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var selectedSection: AppSection? = .encrypt

    @Published var encryptFiles: [SelectedFile] = []
    @Published var decryptFiles: [SelectedFile] = []
    @Published var keys: [KeyEntry] = []
    @Published var operations: [OperationRecord] = []
    @Published var settings: AppSettings = .defaults()
    @Published private(set) var renderedGaussianTransparencyOpacity = AppSettings.defaults().gaussianTransparencyOpacity
    @Published var currentTask: RunningOperation?
    @Published var alertMessage: String?

    @Published var encryptMode: EncryptionMode = .batchPack
    @Published var encryptAuthMode: AuthMode = .passphrase
    @Published var decryptAuthMode: AuthMode = .passphrase
    @Published var archiveBaseName: String = "archive"
    @Published var encryptPassphrase: String = ""
    @Published var decryptPassphrase: String = ""
    @Published var publicKeyInput: String = ""
    @Published var privateKeyInput: String = ""
    @Published var selectedEncryptKeyID: UUID?
    @Published var selectedDecryptKeyID: UUID?
    @Published var importKeyName: String = ""
    @Published var importPublicKey: String = ""
    @Published var importPrivateKey: String = ""

    private let engine = AgeEngineClient()
    private var activeProcess: Process?
    private var activeRecordID: UUID?
    private var userCancelled = false

    var strings: AppStrings {
        AppStrings(language: settings.language)
    }

    private struct PersistedState: Codable {
        var keys: [KeyEntry]
        var operations: [OperationRecord]
        var settings: AppSettings
    }

    init() {
        loadState()
        importAgeConfigKeysIfNeeded()
    }

    var selectedEncryptKey: KeyEntry? {
        keys.first { $0.id == selectedEncryptKeyID }
    }

    var selectedDecryptKey: KeyEntry? {
        keys.first { $0.id == selectedDecryptKeyID }
    }

    var encryptTask: RunningOperation? {
        task(for: .encrypt)
    }

    var decryptTask: RunningOperation? {
        task(for: .decrypt)
    }

    var effectiveGaussianTransparencyOpacity: Int {
        renderedGaussianTransparencyOpacity
    }

    var canStartEncrypt: Bool {
        !encryptFiles.isEmpty && currentTask?.status != .running
    }

    var canStartDecrypt: Bool {
        !decryptFiles.isEmpty && currentTask?.status != .running
    }

    func chooseEncryptFiles() {
        addEncryptFiles(FilePanelService.chooseFiles())
    }

    func chooseEncryptFolder() {
        guard let folder = FilePanelService.chooseFolder() else { return }
        addEncryptFiles(FilePanelService.filesInFolder(folder))
    }

    func chooseDecryptFiles() {
        addDecryptFiles(FilePanelService.chooseFiles(allowedExtensions: ["age"]))
    }

    func chooseDecryptFolder() {
        guard let folder = FilePanelService.chooseFolder() else { return }
        let files = FilePanelService.filesInFolder(folder).filter { $0.pathExtension.lowercased() == "age" }
        addDecryptFiles(files)
    }

    func chooseOutputDirectory() {
        guard let folder = FilePanelService.chooseFolder() else { return }
        settings.outputDirectory = folder.path
        saveState()
    }

    func addEncryptFiles(_ urls: [URL]) {
        merge(urls: urls, into: &encryptFiles)
    }

    func addDecryptFiles(_ urls: [URL]) {
        merge(urls: urls, into: &decryptFiles)
    }

    func removeEncryptFile(_ file: SelectedFile) {
        encryptFiles.removeAll { $0.id == file.id }
    }

    func removeDecryptFile(_ file: SelectedFile) {
        decryptFiles.removeAll { $0.id == file.id }
    }

    func clearEncryptFiles() {
        encryptFiles.removeAll()
    }

    func clearDecryptFiles() {
        decryptFiles.removeAll()
    }

    func generateKeyPair() {
        let language = settings.language
        Task {
            do {
                let key = try await Task.detached {
                    try AgeEngineClient().generateKeyPair(language: language)
                }.value
                keys.insert(key, at: 0)
                selectedEncryptKeyID = key.id
                selectedDecryptKeyID = key.id
                saveState()
            } catch {
                alertMessage = localizedErrorDescription(error)
            }
        }
    }

    func importKey() {
        let publicKey = importPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let privateKey = importPrivateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !publicKey.isEmpty else {
            alertMessage = strings.requirePublicKey()
            return
        }
        let name = importKeyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = KeyEntry(
            id: UUID(),
            name: name.isEmpty ? "Imported key" : name,
            publicKey: publicKey,
            privateKey: privateKey.isEmpty ? nil : privateKey,
            createdAt: Date()
        )
        keys.insert(key, at: 0)
        importKeyName = ""
        importPublicKey = ""
        importPrivateKey = ""
        saveState()
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
        saveState()
    }

    func revealPrivateKey(_ key: KeyEntry) {
        guard let privateKey = key.privateKey, !privateKey.isEmpty else {
            alertMessage = strings.missingPrivateKey()
            return
        }

        Task {
            do {
                let allowed = try await LocalAuthenticationService.authenticate(reason: strings.revealPrivateKeyHelp)
                guard allowed else { return }
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
                saveKeyFile(key)
            } catch {
                alertMessage = strings.authFailed(error.localizedDescription)
            }
        }
    }

    func deleteKey(_ key: KeyEntry) {
        keys.removeAll { $0.id == key.id }
        if selectedEncryptKeyID == key.id {
            selectedEncryptKeyID = nil
        }
        if selectedDecryptKeyID == key.id {
            selectedDecryptKeyID = nil
        }
        saveState()
    }

    func startEncrypt() {
        guard currentTask?.status != .running else { return }
        guard !encryptFiles.isEmpty else {
            alertMessage = strings.requireEncryptFiles()
            return
        }

        let strings = strings
        let secret: String
        let recipientInfo: String
        let authArgument: String
        switch encryptAuthMode {
        case .passphrase:
            guard !encryptPassphrase.isEmpty else {
                alertMessage = strings.requireEncryptPassphrase()
                return
            }
            secret = encryptPassphrase
            recipientInfo = strings.passphrase
            authArgument = "passphrase"
        case .key:
            let key = selectedEncryptKey?.publicKey ?? publicKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                alertMessage = strings.requirePublicKey()
                return
            }
            secret = key
            recipientInfo = key.prefix(24) + "..."
            authArgument = "publicKey"
        }

        let outputName = computedArchiveName()
        let command: EngineCommand = encryptMode == .batchPack
            ? .encryptBatch(outputName: outputName, compress: settings.compressEnabled)
            : .encryptSeparate(compress: settings.compressEnabled)
        let modeLabel = strings.operationModeLabel(mode: encryptMode, compress: settings.compressEnabled)

        runOperation(
            kind: .encrypt,
            modeLabel: modeLabel,
            title: strings.encryptFilesTitle(encryptFiles.count),
            files: encryptFiles,
            request: EngineRequest(
                command: command,
                files: encryptFiles,
                outputDirectory: settings.outputDirectory,
                authArgument: authArgument,
                secret: secret,
                duplicateStrategy: settings.duplicateStrategy,
                concurrency: settings.concurrency,
                language: settings.language
            ),
            recipientInfo: String(recipientInfo)
        )
    }

    func startDecrypt() {
        guard currentTask?.status != .running else { return }
        guard !decryptFiles.isEmpty else {
            alertMessage = strings.requireDecryptFiles()
            return
        }

        let strings = strings
        let secret: String
        let recipientInfo: String
        let authArgument: String
        switch decryptAuthMode {
        case .passphrase:
            guard !decryptPassphrase.isEmpty else {
                alertMessage = strings.requireDecryptPassphrase()
                return
            }
            secret = decryptPassphrase
            recipientInfo = strings.passphrase
            authArgument = "passphrase"
        case .key:
            let key = selectedDecryptKey?.privateKey ?? privateKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                alertMessage = strings.requirePrivateKey()
                return
            }
            secret = key
            recipientInfo = strings.privateKey
            authArgument = "privateKey"
        }

        runOperation(
            kind: .decrypt,
            modeLabel: OperationKind.decrypt.title(in: settings.language),
            title: strings.decryptFilesTitle(decryptFiles.count),
            files: decryptFiles,
            request: EngineRequest(
                command: .decrypt,
                files: decryptFiles,
                outputDirectory: settings.outputDirectory,
                authArgument: authArgument,
                secret: secret,
                duplicateStrategy: settings.duplicateStrategy,
                concurrency: settings.concurrency,
                language: settings.language
            ),
            recipientInfo: recipientInfo
        )
    }

    func cancelCurrentTask() {
        guard currentTask?.status == .running else { return }
        userCancelled = true
        activeProcess?.terminate()
        currentTask?.status = .cancelled
        currentTask?.phase = strings.phaseCancelling()
    }

    func reveal(path: String) {
        FilePanelService.reveal(path: path)
    }

    func clearHistory() {
        operations.removeAll()
        saveState()
    }

    func removeCurrentTask(kind: OperationKind) {
        guard let task = task(for: kind), task.status != .running else { return }
        if currentTask?.id == task.id {
            currentTask = nil
        }
        removeOperation(id: task.id)
    }

    func removeOperation(id: UUID) {
        operations.removeAll { $0.id == id }
        if currentTask?.id == id {
            currentTask = nil
        }
        saveState()
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

        saveState()
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

    private func updateGaussianTransparencyOpacity(_ opacity: Int) {
        let clampedOpacity = AppSettings.clampGaussianTransparencyOpacity(opacity)
        if renderedGaussianTransparencyOpacity != clampedOpacity {
            renderedGaussianTransparencyOpacity = clampedOpacity
        }
        if settings.gaussianTransparencyOpacity != clampedOpacity {
            settings.gaussianTransparencyOpacity = clampedOpacity
        }
    }

    private func runOperation(
        kind: OperationKind,
        modeLabel: String,
        title: String,
        files: [SelectedFile],
        request: EngineRequest,
        recipientInfo: String
    ) {
        let recordID = UUID()
        let record = OperationRecord(
            id: recordID,
            kind: kind,
            modeLabel: modeLabel,
            inputFiles: files.map(\.name),
            outputPath: request.outputDirectory,
            recipientInfo: recipientInfo,
            status: .running,
            errorMessage: nil,
            outputs: [],
            timestamp: Date()
        )

        operations.insert(record, at: 0)
        currentTask = .started(id: recordID, kind: kind, title: title, phase: strings.phasePreparing(), total: files.count)
        activeRecordID = recordID
        userCancelled = false
        saveState()

        Task {
            do {
                let result = try await engine.run(
                    request: request,
                    onProcess: { [weak self] process in
                        Task { @MainActor in
                            self?.activeProcess = process
                        }
                    },
                    onEvent: { [weak self] event in
                        Task { @MainActor in
                            self?.handleEngineEvent(event)
                        }
                    }
                )
                finishOperation(id: recordID, result: result)
            } catch {
                failOperation(id: recordID, error: error)
            }
        }
    }

    private func handleEngineEvent(_ event: EngineEvent) {
        if event.event == "progress" || event.event == "done" {
            currentTask?.phase = localizedEnginePhase(event.phase) ?? currentTask?.phase ?? ""
            currentTask?.progress = event.progress ?? currentTask?.progress ?? 0
            currentTask?.processed = event.processed ?? currentTask?.processed ?? 0
            currentTask?.total = event.total ?? currentTask?.total ?? 0
            currentTask?.success = event.success ?? currentTask?.success ?? 0
            currentTask?.fail = event.fail ?? currentTask?.fail ?? 0
        }
        if let output = event.output, currentTask?.outputs.contains(output) == false {
            currentTask?.outputs.append(output)
        }
        if let outputs = event.outputs, !outputs.isEmpty {
            currentTask?.outputs = outputs
        }
        if event.event == "error" {
            currentTask?.status = .failed
            currentTask?.errorMessage = event.message
        }
    }

    private func localizedEnginePhase(_ phase: String?) -> String? {
        guard let phase, !phase.isEmpty else { return nil }
        switch phase {
        case "Packing":
            return settings.language == .english ? "Packing" : "打包中"
        case "Complete":
            return strings.phaseComplete()
        case let value where value.hasPrefix("解密中"):
            guard settings.language == .english else { return value }
            let label = value.dropFirst("解密中".count).trimmingCharacters(in: .whitespaces)
            return label.isEmpty ? "Decrypting" : "Decrypting \(label)"
        default:
            return phase
        }
    }

    private func finishOperation(id: UUID, result: EngineResult) {
        activeProcess = nil
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        operations[index].status = .success
        operations[index].outputs = result.outputs
        operations[index].outputPath = settings.outputDirectory

        currentTask?.status = .success
        currentTask?.phase = strings.phaseComplete()
        currentTask?.progress = 1
        currentTask?.success = result.success
        currentTask?.fail = result.fail
        currentTask?.outputs = result.outputs
        saveState()
    }

    private func failOperation(id: UUID, error: Error) {
        activeProcess = nil
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        let status: OperationStatus = userCancelled ? .cancelled : .failed
        let message = userCancelled ? strings.phaseCancelled() : localizedErrorDescription(error)
        operations[index].status = status
        operations[index].errorMessage = message

        currentTask?.status = status
        currentTask?.phase = status == .cancelled ? strings.phaseCancelled() : strings.phaseFailed()
        currentTask?.errorMessage = message
        userCancelled = false
        saveState()
    }

    private func localizedErrorDescription(_ error: Error) -> String {
        if let engineError = error as? EngineClientError {
            return engineError.errorDescription(in: settings.language)
        }
        return error.localizedDescription
    }

    private func merge(urls: [URL], into files: inout [SelectedFile]) {
        let existing = Set(files.map(\.path))
        let additions = urls
            .filter { !existing.contains($0.path) }
            .map(SelectedFile.init(url:))
        files.append(contentsOf: additions)
    }

    private func computedArchiveName() -> String {
        let base = archiveBaseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "archive" : archiveBaseName
        return settings.compressEnabled ? "\(base).tar.gz.age" : "\(base).tar.age"
    }

    private func task(for kind: OperationKind) -> RunningOperation? {
        guard let currentTask, currentTask.kind == kind else { return nil }
        return currentTask
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
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }
        keys = state.keys
        operations = state.operations
        settings = state.settings
        renderedGaussianTransparencyOpacity = settings.gaussianTransparencyOpacity
        selectedEncryptKeyID = keys.first?.id
        selectedDecryptKeyID = keys.first(where: { $0.hasPrivateKey })?.id
    }

    @discardableResult
    private func importKeys(from text: String, fallbackName: String) -> Int {
        let parsed = KeyFileCodec.parseMany(text, fallbackName: fallbackName)
        var existingPublicKeys = Set(keys.map(\.publicKey).filter { !$0.isEmpty })
        var existingPrivateKeys = Set(keys.compactMap(\.privateKey).filter { !$0.isEmpty })
        var additions: [KeyEntry] = []
        for key in parsed {
            let publicExists = !key.publicKey.isEmpty && existingPublicKeys.contains(key.publicKey)
            let privateExists = key.privateKey.map { existingPrivateKeys.contains($0) } ?? false
            guard !publicExists && !privateExists else { continue }
            additions.append(key)
            existingPublicKeys.insert(key.publicKey)
            if let privateKey = key.privateKey, !privateKey.isEmpty {
                existingPrivateKeys.insert(privateKey)
            }
        }
        guard !additions.isEmpty else { return 0 }
        keys.insert(contentsOf: additions, at: 0)
        selectedEncryptKeyID = keys.first(where: { !$0.publicKey.isEmpty })?.id
        selectedDecryptKeyID = keys.first(where: { $0.hasPrivateKey })?.id
        saveState()
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

    private func saveState() {
        do {
            try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
            let state = PersistedState(keys: keys, operations: Array(operations.prefix(200)), settings: settings)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: stateURL, options: [.atomic])
        } catch {
            alertMessage = strings.savedStateFailed(error.localizedDescription)
        }
    }

    private var appSupportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("AgeMac", isDirectory: true)
    }

    private var stateURL: URL {
        appSupportURL.appendingPathComponent("state.json")
    }
}
