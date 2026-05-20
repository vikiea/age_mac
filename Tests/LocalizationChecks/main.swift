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
check(decodedSettings.language == .english, "older settings should decode with English fallback")
check(AppLanguage.english.title == "English", "English language label")
check(AppLanguage.chinese.title == "中文", "Chinese language label")
check(AppSection.encrypt.title(in: .english) == "Encrypt", "English section title")
check(AppSection.encrypt.title(in: .chinese) == "加密", "Chinese section title")
check(OperationStatus.running.title(in: .english) == "Running", "English status title")
check(OperationStatus.running.title(in: .chinese) == "运行中", "Chinese status title")
check(AppStrings(language: .english).settingsLanguageSubtitle == "Interface language", "English settings subtitle")
check(AppStrings(language: .chinese).settingsLanguageSubtitle == "界面语言", "Chinese settings subtitle")
check(AppStrings(language: .english).requireEncryptPassphrase() == "Enter an encryption passphrase", "English validation text")
check(AppStrings(language: .chinese).requireEncryptPassphrase() == "请输入加密密码", "Chinese validation text")

let engineMessage = "incorrect passphrase"
check(
    EngineErrorPresenter.userMessage(for: engineMessage, command: .decrypt, language: .english).contains("passphrase"),
    "English engine error text"
)
check(
    EngineErrorPresenter.userMessage(for: engineMessage, command: .decrypt, language: .chinese).contains("密码"),
    "Chinese engine error text"
)

print("Localization checks passed")
