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

        print("Workspace checks passed")
    }
}
