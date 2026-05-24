/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import Foundation

@discardableResult
func check(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
    if condition() {
        return true
    }

    fputs("Workspace check failed: \(message) (\(file):\(line))\n", stderr)
    exit(1)
}

@main
struct WorkspaceChecks {
    @MainActor
    static func main() {
        let supportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgeMacWorkspaceChecks", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: supportURL)
        }

        let appStore = AppStore(persistence: AppPersistence(appSupportURL: supportURL))
        let first = WorkspaceStore(appStore: appStore)
        let second = WorkspaceStore(appStore: appStore)

        first.selectedSection = .decrypt
        first.addEncryptFiles([FileManager.default.temporaryDirectory.appendingPathComponent("first.txt")])
        first.archiveBaseName = "first-archive"
        first.encryptPassphrase = "first-passphrase"

        second.selectedSection = .encrypt
        second.addDecryptFiles([FileManager.default.temporaryDirectory.appendingPathComponent("second.age")])
        second.archiveBaseName = "second-archive"
        second.decryptPassphrase = "second-passphrase"

        check(first.selectedSection == .decrypt, "first workspace should keep its selected section")
        check(second.selectedSection == .encrypt, "second workspace should keep its selected section")
        check(first.encryptFiles.map(\.name) == ["first.txt"], "first workspace should keep its encrypt files")
        check(first.decryptFiles.isEmpty, "first workspace decrypt files should remain empty")
        check(second.encryptFiles.isEmpty, "second workspace encrypt files should remain empty")
        check(second.decryptFiles.map(\.name) == ["second.age"], "second workspace should keep its decrypt files")
        check(first.archiveBaseName == "first-archive", "first workspace should keep its archive draft")
        check(second.archiveBaseName == "second-archive", "second workspace should keep its archive draft")
        check(first.encryptPassphrase == "first-passphrase", "first workspace should keep its passphrase draft")
        check(second.decryptPassphrase == "second-passphrase", "second workspace should keep its passphrase draft")

        let folder = supportURL.appendingPathComponent("folder-input", isDirectory: true)
        let nested = folder.appendingPathComponent("child", isDirectory: true)
        try? FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let rootFile = folder.appendingPathComponent("root.txt")
        let nestedFile = nested.appendingPathComponent("note.txt")
        let nestedAgeFile = nested.appendingPathComponent("secret.age")
        FileManager.default.createFile(atPath: rootFile.path, contents: Data())
        FileManager.default.createFile(atPath: nestedFile.path, contents: Data())
        FileManager.default.createFile(atPath: nestedAgeFile.path, contents: Data())

        first.clearEncryptFiles()
        first.addEncryptFolder(folder)
        check(
            Set(first.encryptFiles.map(\.name)) == Set(["root.txt", "child/note.txt", "child/secret.age"]),
            "folder encryption should preserve relative child paths"
        )

        second.clearDecryptFiles()
        second.addDecryptFolder(folder)
        check(
            second.decryptFiles.map(\.name) == ["child/secret.age"],
            "folder decryption should preserve relative paths for scanned age files"
        )

        second.addEncryptFiles([FileManager.default.temporaryDirectory.appendingPathComponent("second.txt")])
        first.currentTask = .started(id: UUID(), kind: .encrypt, title: "Encrypt A", phase: "Running", total: 1)
        check(first.currentTask != nil, "first workspace should have its task")
        check(second.currentTask == nil, "second workspace should not inherit another workspace task")
        check(!first.canStartEncrypt, "running task should block only its workspace")
        check(second.canStartEncrypt, "another workspace should still be able to start")

        let historySupportURL = supportURL.appendingPathComponent("history-metadata", isDirectory: true)
        let historyStore = AppStore(persistence: AppPersistence(appSupportURL: historySupportURL))
        historyStore.settings.outputDirectory = historySupportURL.appendingPathComponent("outputs", isDirectory: true).path
        historyStore.settings.compressEnabled = true
        historyStore.settings.duplicateStrategy = .overwrite
        historyStore.settings.concurrency = 2

        let historyWorkspace = WorkspaceStore(appStore: historyStore)
        let source = historySupportURL.appendingPathComponent("source.txt")
        try? FileManager.default.createDirectory(at: historySupportURL, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: source.path, contents: Data("hello".utf8))
        historyWorkspace.addEncryptFiles([source])
        historyWorkspace.encryptAuthMode = .passphrase
        historyWorkspace.encryptPassphrase = "do-not-persist"
        historyWorkspace.startEncrypt()

        guard let record = historyStore.operations.first else {
            check(false, "starting encryption should create a history record")
            return
        }
        check(record.details?.authMethod == .passphrase, "history should record passphrase auth without the passphrase value")
        check(record.details?.encryptionMode == .batchPack, "history should record encryption mode")
        check(record.details?.compression == .enabled, "history should record compression setting")
        check(record.details?.duplicateStrategy == .overwrite, "history should record duplicate strategy")
        check(record.details?.concurrency == 2, "history should record concurrency")
        check(record.details?.inputCount == 1, "history should record input count")
        check(record.recipientInfo == AppStrings(language: .english).passphrase, "history should keep safe recipient label")
        check(!String(data: try! JSONEncoder().encode(record), encoding: .utf8)!.contains("do-not-persist"), "history should not persist passphrases")

        historyWorkspace.cancelCurrentTask()

        let namedKey = KeyEntry(
            id: UUID(),
            name: "Laptop key",
            publicKey: "age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq",
            privateKey: "AGE-SECRET-KEY-1QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        historyStore.keys.insert(namedKey, at: 0)

        let keyDecryptWorkspace = WorkspaceStore(appStore: historyStore)
        keyDecryptWorkspace.addDecryptFiles([historySupportURL.appendingPathComponent("secret.age")])
        keyDecryptWorkspace.decryptAuthMode = .key
        keyDecryptWorkspace.selectedDecryptKeyID = namedKey.id
        keyDecryptWorkspace.startDecrypt()

        guard let decryptRecord = historyStore.operations.first else {
            check(false, "starting key decryption should create a history record")
            return
        }
        check(decryptRecord.details?.authMethod == .privateKey, "history should record private key auth")
        check(decryptRecord.details?.keyHint?.name == "Laptop key", "history should prefer saved key name")
        check(decryptRecord.details?.keyHint?.publicKeyPreview?.hasPrefix("age1qqqq") == true, "history should keep public key preview for saved private key")
        let decryptJSON = String(data: try! JSONEncoder().encode(decryptRecord), encoding: .utf8)!
        check(!decryptJSON.contains("AGE-SECRET-KEY"), "history should not persist private key material")
        check(!decryptJSON.contains(namedKey.publicKey), "history should not persist full public key")

        keyDecryptWorkspace.cancelCurrentTask()

        let manualPrivateKey = "AGE-SECRET-KEY-1ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"
        let manualDecryptWorkspace = WorkspaceStore(appStore: historyStore)
        manualDecryptWorkspace.addDecryptFiles([historySupportURL.appendingPathComponent("manual.age")])
        manualDecryptWorkspace.decryptAuthMode = .key
        manualDecryptWorkspace.selectedDecryptKeyID = nil
        manualDecryptWorkspace.privateKeyInput = manualPrivateKey
        manualDecryptWorkspace.startDecrypt()

        guard let manualRecord = historyStore.operations.first else {
            check(false, "starting manual key decryption should create a history record")
            return
        }
        check(manualRecord.details?.keyHint?.name == nil, "manual private key should not invent a key name")
        check(manualRecord.details?.keyHint?.privateKeyFingerprint?.isEmpty == false, "manual private key should keep only a fingerprint hint")
        let manualJSON = String(data: try! JSONEncoder().encode(manualRecord), encoding: .utf8)!
        check(!manualJSON.contains("AGE-SECRET-KEY"), "manual private key history should not persist private key material")
        check(!manualJSON.contains(manualPrivateKey), "manual private key history should not persist the full private key")

        manualDecryptWorkspace.cancelCurrentTask()

        print("Workspace checks passed")
    }
}
