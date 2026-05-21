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

    fputs("Localization check failed: \(message) (\(file):\(line))\n", stderr)
    exit(1)
}

let olderSettingsJSON = """
{
  "outputDirectory": "/tmp/Age Mac Output",
  "duplicateStrategy": "rename",
  "compressEnabled": false,
  "concurrency": 4,
  "theme": "teal",
  "gaussianTransparencyEnabled": false,
  "gaussianTransparencyOpacity": 55
}
"""

let decodedSettings = try JSONDecoder().decode(AppSettings.self, from: Data(olderSettingsJSON.utf8))

check(AppSettings.defaults().language == .english, "defaults should use English")
check(AppSettings.defaults().appearance == .system, "defaults should follow system appearance")
check(decodedSettings.language == .english, "older settings should decode with English fallback")
check(decodedSettings.appearance == .system, "older settings should decode with system appearance fallback")
check(AppLanguage.english.title == "English", "English language label")
check(AppLanguage.chinese.title == "中文", "Chinese language label")
check(AppAppearance.system.title(in: .english) == "System", "English system appearance label")
check(AppAppearance.system.title(in: .chinese) == "跟随系统", "Chinese system appearance label")
check(AppAppearance.dark.title(in: .english) == "Dark", "English dark appearance label")
check(AppAppearance.dark.title(in: .chinese) == "深色", "Chinese dark appearance label")
check(AppSection.encrypt.title(in: .english) == "Encrypt", "English section title")
check(AppSection.encrypt.title(in: .chinese) == "加密", "Chinese section title")
check(OperationStatus.running.title(in: .english) == "Running", "English status title")
check(OperationStatus.running.title(in: .chinese) == "运行中", "Chinese status title")
check(AppStrings(language: .english).newAgeMacWindow == "New Age Mac Window", "English new window menu text")
check(AppStrings(language: .chinese).newAgeMacWindow == "新建 Age Mac 窗口", "Chinese new window menu text")
check(!AppStrings(language: .chinese).newAgeMacWindow.contains("New Age"), "Chinese new window menu should not mix English template")
check(AppStrings(language: .english).interface == "Interface", "English interface settings title")
check(AppStrings(language: .chinese).interface == "界面", "Chinese interface settings title")
check(AppStrings(language: .english).outputAndTaskSubtitle.contains("appearance"), "English settings subtitle should mention appearance")
check(AppStrings(language: .chinese).outputAndTaskSubtitle.contains("外观"), "Chinese settings subtitle should mention appearance")
check(AppStrings(language: .english).outputFiles == "Output Files", "English output files title")
check(AppStrings(language: .chinese).outputFiles == "输出文件", "Chinese output files title")
check(AppStrings(language: .english).openInFinder == "Open in Finder", "English Finder action text")
check(AppStrings(language: .chinese).openInFinder == "在 Finder 中打开", "Chinese Finder action text")
check(AppStrings(language: .english).settingsLanguageSubtitle == "Interface language", "English settings subtitle")
check(AppStrings(language: .chinese).settingsLanguageSubtitle == "界面语言", "Chinese settings subtitle")
check(AppStrings(language: .english).requireEncryptPassphrase() == "Enter an encryption passphrase", "English validation text")
check(AppStrings(language: .chinese).requireEncryptPassphrase() == "请输入加密密码", "Chinese validation text")

let sensitiveKey = KeyEntry(
    id: UUID(),
    name: "Sensitive",
    publicKey: "age1public",
    privateKey: "AGE-SECRET-KEY-PRIVATE",
    createdAt: Date(timeIntervalSince1970: 1)
)
let encodedKey = try JSONEncoder().encode(sensitiveKey)
let encodedKeyText = String(data: encodedKey, encoding: .utf8) ?? ""
check(!encodedKeyText.contains("AGE-SECRET-KEY-PRIVATE"), "encoded key metadata should not contain plaintext private key")
check(encodedKeyText.contains("privateKeyStored"), "encoded key metadata should keep private key availability")

let engineMessage = "incorrect passphrase"
check(
    EngineErrorPresenter.userMessage(for: engineMessage, command: .decrypt, language: .english).contains("passphrase"),
    "English engine error text"
)
check(
    EngineErrorPresenter.userMessage(for: engineMessage, command: .decrypt, language: .chinese).contains("密码"),
    "Chinese engine error text"
)

let tempSupportURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("AgeMacPersistence-\(UUID().uuidString)", isDirectory: true)
defer {
    try? FileManager.default.removeItem(at: tempSupportURL)
}

let persistence = AppPersistence(appSupportURL: tempSupportURL)
let legacyKey = KeyEntry(
    id: UUID(),
    name: "Legacy key",
    publicKey: "age1legacy",
    privateKey: nil,
    createdAt: Date(timeIntervalSince1970: 1)
)
let legacyOperations = (0..<250).map { index in
    OperationRecord(
        id: UUID(),
        kind: .encrypt,
        modeLabel: "Batch",
        inputFiles: ["file-\(index).txt"],
        outputPath: "/tmp",
        recipientInfo: "Passphrase",
        status: .success,
        errorMessage: nil,
        outputs: ["/tmp/file-\(index).age"],
        timestamp: Date(timeIntervalSince1970: Double(index))
    )
}
let legacyStateJSON = """
{
  "keys": [
    {
      "id": "\(legacyKey.id.uuidString)",
      "name": "Legacy key",
      "publicKey": "age1legacy",
      "createdAt": 1
    }
  ],
  "operations": [
    \(legacyOperations.map { operation in
        """
        {
          "id": "\(operation.id.uuidString)",
          "kind": "encrypt",
          "modeLabel": "Batch",
          "inputFiles": ["\(operation.inputFiles[0])"],
          "outputPath": "/tmp",
          "recipientInfo": "Passphrase",
          "status": "success",
          "outputs": ["\(operation.outputs[0])"],
          "timestamp": \(Int(operation.timestamp.timeIntervalSince1970))
        }
        """
    }.joined(separator: ",\n"))
  ],
  "settings": \(olderSettingsJSON)
}
"""
try FileManager.default.createDirectory(at: tempSupportURL, withIntermediateDirectories: true)
try Data(legacyStateJSON.utf8).write(to: persistence.legacyStateURL)

let migrated = persistence.load()
check(migrated.keys.count == 1, "legacy keys should migrate")
check(migrated.operations.count == AppPersistence.historyLimit, "legacy history should be capped during migration")
check(migrated.settings.language == .english, "legacy settings should migrate with language fallback")
check(FileManager.default.fileExists(atPath: persistence.settingsURL.path), "settings should be split into settings.json")
check(FileManager.default.fileExists(atPath: persistence.keysURL.path), "keys should be split into keys.json")
check(FileManager.default.fileExists(atPath: persistence.historyURL.path), "history should be split into history.json")

print("Localization checks passed")
