/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import AppKit
import Foundation

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var selectedSection: AppSection? = .encrypt
    @Published var encryptFiles: [SelectedFile] = []
    @Published var decryptFiles: [SelectedFile] = []
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
    private weak var appStore: AppStore?
    private var activeProcess: Process?
    private var activeRecordID: UUID?
    private var userCancelled = false

    init(appStore: AppStore) {
        self.appStore = appStore
        selectedEncryptKeyID = appStore.keys.first(where: { !$0.publicKey.isEmpty })?.id
        selectedDecryptKeyID = appStore.keys.first(where: { $0.hasPrivateKey })?.id
    }

    var encryptTask: RunningOperation? {
        task(for: .encrypt)
    }

    var decryptTask: RunningOperation? {
        task(for: .decrypt)
    }

    var canStartEncrypt: Bool {
        !encryptFiles.isEmpty && currentTask?.status != .running
    }

    var canStartDecrypt: Bool {
        !decryptFiles.isEmpty && currentTask?.status != .running
    }

    var selectedEncryptKey: KeyEntry? {
        guard let appStore else { return nil }
        return appStore.keys.first { $0.id == selectedEncryptKeyID }
    }

    var selectedDecryptKey: KeyEntry? {
        guard let appStore else { return nil }
        return appStore.keys.first { $0.id == selectedDecryptKeyID }
    }

    func chooseEncryptFiles() {
        addEncryptFiles(FilePanelService.chooseFiles())
    }

    func chooseEncryptFolder() {
        guard let folder = FilePanelService.chooseFolder() else { return }
        addEncryptFolder(folder)
    }

    func chooseDecryptFiles() {
        addDecryptFiles(FilePanelService.chooseFiles(allowedExtensions: ["age"]))
    }

    func chooseDecryptFolder() {
        guard let folder = FilePanelService.chooseFolder() else { return }
        addDecryptFolder(folder)
    }

    func addEncryptFiles(_ urls: [URL]) {
        merge(urls: urls, into: &encryptFiles)
    }

    func addDecryptFiles(_ urls: [URL]) {
        merge(urls: urls, into: &decryptFiles)
    }

    func addEncryptFolder(_ folder: URL) {
        merge(folder: folder, into: &encryptFiles)
    }

    func addDecryptFolder(_ folder: URL) {
        merge(
            folder: folder,
            into: &decryptFiles,
            shouldInclude: { $0.pathExtension.lowercased() == "age" }
        )
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
        Task {
            guard let key = await appStore?.generateKeyPairForWorkspace() else { return }
            selectedEncryptKeyID = key.id
            selectedDecryptKeyID = key.id
        }
    }

    func importKey() {
        guard let appStore else { return }
        let key = appStore.importKey(
            name: importKeyName,
            publicKey: importPublicKey,
            privateKey: importPrivateKey
        )
        guard let key else { return }
        importKeyName = ""
        importPublicKey = ""
        importPrivateKey = ""
        selectedEncryptKeyID = key.id
        if key.hasPrivateKey {
            selectedDecryptKeyID = key.id
        }
    }

    func startEncrypt() {
        guard let appStore else { return }
        guard currentTask?.status != .running else { return }
        guard !encryptFiles.isEmpty else {
            alertMessage = appStore.strings.requireEncryptFiles()
            return
        }

        let strings = appStore.strings
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

        let settings = appStore.settings
        let outputName = computedArchiveName(compress: settings.compressEnabled)
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
        guard let appStore else { return }
        guard currentTask?.status != .running else { return }
        guard !decryptFiles.isEmpty else {
            alertMessage = appStore.strings.requireDecryptFiles()
            return
        }

        let strings = appStore.strings
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
            let key = selectedDecryptKey.flatMap(appStore.privateKey(for:)) ?? privateKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                alertMessage = strings.requirePrivateKey()
                return
            }
            secret = key
            recipientInfo = strings.privateKey
            authArgument = "privateKey"
        }

        let settings = appStore.settings
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
        currentTask?.phase = appStore?.strings.phaseCancelling() ?? ""
    }

    func removeCurrentTask(kind: OperationKind) {
        guard let task = task(for: kind), task.status != .running else { return }
        if currentTask?.id == task.id {
            currentTask = nil
        }
        appStore?.removeOperation(id: task.id)
    }

    private func runOperation(
        kind: OperationKind,
        modeLabel: String,
        title: String,
        files: [SelectedFile],
        request: EngineRequest,
        recipientInfo: String
    ) {
        guard let appStore else { return }
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

        appStore.addOperation(record)
        currentTask = .started(id: recordID, kind: kind, title: title, phase: appStore.strings.phasePreparing(), total: files.count)
        activeRecordID = recordID
        userCancelled = false

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
        guard let appStore, let phase, !phase.isEmpty else { return nil }
        switch phase {
        case "Packing":
            return appStore.settings.language == .english ? "Packing" : "打包中"
        case "Complete":
            return appStore.strings.phaseComplete()
        case let value where value.hasPrefix("解密中"):
            guard appStore.settings.language == .english else { return value }
            let label = value.dropFirst("解密中".count).trimmingCharacters(in: .whitespaces)
            return label.isEmpty ? "Decrypting" : "Decrypting \(label)"
        default:
            return phase
        }
    }

    private func finishOperation(id: UUID, result: EngineResult) {
        activeProcess = nil
        appStore?.updateOperation(id: id) { operation in
            operation.status = .success
            operation.outputs = result.outputs
            operation.outputPath = appStore?.settings.outputDirectory ?? operation.outputPath
        }

        currentTask?.status = .success
        currentTask?.phase = appStore?.strings.phaseComplete() ?? ""
        currentTask?.progress = 1
        currentTask?.success = result.success
        currentTask?.fail = result.fail
        currentTask?.outputs = result.outputs
    }

    private func failOperation(id: UUID, error: Error) {
        activeProcess = nil
        let status: OperationStatus = userCancelled ? .cancelled : .failed
        let message = userCancelled
            ? appStore?.strings.phaseCancelled() ?? ""
            : appStore?.localizedErrorDescription(error) ?? error.localizedDescription
        appStore?.updateOperation(id: id) { operation in
            operation.status = status
            operation.errorMessage = message
        }

        currentTask?.status = status
        currentTask?.phase = status == .cancelled ? appStore?.strings.phaseCancelled() ?? "" : appStore?.strings.phaseFailed() ?? ""
        currentTask?.errorMessage = message
        userCancelled = false
    }

    private func merge(urls: [URL], into files: inout [SelectedFile]) {
        let existing = Set(files.map(\.path))
        let additions = urls
            .filter { !existing.contains($0.path) }
            .map(SelectedFile.init(url:))
        files.append(contentsOf: additions)
    }

    private func merge(
        folder: URL,
        into files: inout [SelectedFile],
        shouldInclude: (URL) -> Bool = { _ in true }
    ) {
        let folderPath = folder.standardizedFileURL.path
        let existing = Set(files.map(\.path))
        let additions = FilePanelService.filesInFolder(folder)
            .filter(shouldInclude)
            .filter { !existing.contains($0.path) }
            .compactMap { url -> SelectedFile? in
                guard let name = relativeName(for: url, in: folderPath) else { return nil }
                return SelectedFile(url: url, name: name)
            }
        files.append(contentsOf: additions)
    }

    private func relativeName(for url: URL, in folderPath: String) -> String? {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(folderPath + "/") else { return nil }
        let relative = String(path.dropFirst(folderPath.count + 1))
        return relative.isEmpty ? nil : relative
    }

    private func computedArchiveName(compress: Bool) -> String {
        let base = archiveBaseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "archive" : archiveBaseName
        return compress ? "\(base).tar.gz.age" : "\(base).tar.age"
    }

    private func task(for kind: OperationKind) -> RunningOperation? {
        guard let currentTask, currentTask.kind == kind else { return nil }
        return currentTask
    }
}
