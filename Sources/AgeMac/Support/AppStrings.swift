/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import Foundation

struct AppStrings {
    var language: AppLanguage

    var aboutAgeMac: String { text(en: "About Age Mac", zh: "关于 Age Mac") }
    var addDecryptFile: String { text(en: "Add Decrypt Files", zh: "添加解密文件") }
    var addEncryptedAge: String { text(en: "Add .age", zh: "添加 .age") }
    var addEncryptFile: String { text(en: "Add Encrypt Files", zh: "添加加密文件") }
    var addFiles: String { text(en: "Add Files", zh: "添加文件") }
    var addFolder: String { text(en: "Add Folder", zh: "添加文件夹") }
    var appearance: String { text(en: "Appearance", zh: "外观") }
    var archiveNamePlaceholder: String { text(en: "Output file name", zh: "输出文件名") }
    var autoImportNoNewKeys: String { text(en: "No new age keys found", zh: "没有发现新的 age 密钥") }
    var cancelCurrentTask: String { text(en: "Cancel Current Task", zh: "取消当前任务") }
    var cancelTask: String { text(en: "Cancel Task", zh: "取消任务") }
    var chooseDirectory: String { text(en: "Choose Folder", zh: "选择目录") }
    var chooseOutputDirectory: String { text(en: "Choose Output Folder", zh: "选择输出目录") }
    var clear: String { text(en: "Clear", zh: "清空") }
    var colorTheme: String { text(en: "Color theme", zh: "颜色主题") }
    var defaultCompress: String { text(en: "Compress by default", zh: "默认压缩") }
    var delete: String { text(en: "Delete", zh: "删除") }
    var deleteRecord: String { text(en: "Delete record", zh: "删除记录") }
    var deleteResult: String { text(en: "Delete result", zh: "删除结果") }
    var decryptSubtitle: String { text(en: "Decrypt .age files and auto-extract tar or tar.gz contents", zh: "解密 .age 文件并自动展开 tar 或 tar.gz 内容") }
    var decryptMethod: String { text(en: "Decrypt with", zh: "解密方式") }
    var duplicateFiles: String { text(en: "Matching files", zh: "同名文件") }
    var encryptMode: String { text(en: "Mode", zh: "模式") }
    var encryptMethod: String { text(en: "Encrypt with", zh: "加密方式") }
    var encryptSubtitle: String { text(en: "Stream local files through age encryption", zh: "打包、压缩并用 age 流式加密本地文件") }
    var exportKeyHelp: String { text(en: "Authenticate to export key", zh: "验证后导出密钥") }
    var gaussianOpacity: String { text(en: "Opacity", zh: "透明度") }
    var gaussianTransparency: String { text(en: "Gaussian transparency", zh: "高斯透明") }
    var generateKey: String { text(en: "Generate Key", zh: "生成密钥") }
    var hasPrivateKey: String { text(en: "Private key saved", zh: "含私钥") }
    var historyTitle: String { text(en: "Operation History", zh: "操作记录") }
    var historySubtitle: String { text(en: "Review local encryption and decryption operations", zh: "查看本机加密和解密操作记录") }
    var importFromFile: String { text(en: "Import from File", zh: "从文件导入") }
    var importKey: String { text(en: "Import", zh: "导入") }
    var inputFiles: String { text(en: "Input Files", zh: "输入文件") }
    var interface: String { text(en: "Interface", zh: "界面") }
    var keyName: String { text(en: "Key name", zh: "密钥名称") }
    var keysTitle: String { text(en: "Saved Keys", zh: "已保存密钥") }
    var keysSubtitle: String { text(en: "Generate, import, and manage local X25519 age keys", zh: "生成、导入并管理本地 X25519 age 密钥") }
    var languageLabel: String { text(en: "Language", zh: "语言") }
    var manualImport: String { text(en: "Manual Import", zh: "手动导入") }
    var noFilesTitle: String { text(en: "No Files", zh: "没有文件") }
    var noFilesDescription: String { text(en: "Use the buttons above to add files", zh: "使用上方按钮添加文件") }
    var noHistoryDescription: String { text(en: "Completed tasks will appear here", zh: "完成一次任务后会出现在这里") }
    var noHistoryTitle: String { text(en: "No History", zh: "没有历史记录") }
    var noKeySelection: String { text(en: "Do not use a saved key", zh: "不使用已保存密钥") }
    var noKeysDescription: String { text(en: "Generate or import an age key", zh: "生成或导入一个 age 密钥") }
    var noKeysTitle: String { text(en: "No Keys", zh: "没有密钥") }
    var newAgeMacWindow: String { text(en: "New Age Mac Window", zh: "新建 Age Mac 窗口") }
    var ok: String { text(en: "OK", zh: "好") }
    var openSourceComponents: String { text(en: "Open Source Components", zh: "开源组件") }
    var openInFinder: String { text(en: "Open in Finder", zh: "在 Finder 中打开") }
    var output: String { text(en: "Output", zh: "输出") }
    var outputAndTaskSubtitle: String { text(en: "Output folder, matching-file policy, appearance, language, and task options", zh: "输出目录、同名文件策略、外观、语言和任务参数") }
    var outputFiles: String { text(en: "Output Files", zh: "输出文件") }
    var passphrase: String { text(en: "Passphrase", zh: "密码") }
    var privateKey: String { text(en: "Private key", zh: "私钥") }
    var privateKeyOptional: String { text(en: "Private key (optional)", zh: "私钥（可选）") }
    var project: String { text(en: "Project", zh: "项目") }
    var publicKey: String { text(en: "Public key", zh: "公钥") }
    var revealPrivateKeyHelp: String { text(en: "Authenticate to reveal private key", zh: "验证后查看私钥") }
    var savedPrivateKeys: String { text(en: "Saved private keys", zh: "已保存私钥") }
    var savedPublicKeys: String { text(en: "Saved public keys", zh: "已保存公钥") }
    var scanFolder: String { text(en: "Scan Folder", zh: "扫描文件夹") }
    var settingsLanguageSubtitle: String { text(en: "Interface language", zh: "界面语言") }
    var startDecrypt: String { text(en: "Start Decrypting", zh: "开始解密") }
    var startEncrypt: String { text(en: "Start Encrypting", zh: "开始加密") }
    var task: String { text(en: "Task", zh: "任务") }
    var theme: String { text(en: "Theme", zh: "主题") }
    var versionFallback: String { text(en: "Development", zh: "开发版") }

    func appDescription() -> String {
        text(en: "Local-first age file encryption for macOS", zh: "本地优先的 age 文件加解密工具")
    }

    func ageLibraryPurpose() -> String {
        text(en: "age encryption format and X25519 support", zh: "age 加密格式与 X25519 支持")
    }

    func appleUIPurpose() -> String {
        text(en: "Native macOS interface", zh: "macOS 原生界面")
    }

    func authFailed(_ error: String) -> String {
        text(en: "Local authentication failed: \(error)", zh: "本机验证失败: \(error)")
    }

    func concurrencyLimit(_ value: Int) -> String {
        text(en: "Concurrency limit \(value)", zh: "并发上限 \(value)")
    }

    func decryptFilesTitle(_ count: Int) -> String {
        text(en: "Decrypt \(count) files", zh: "解密 \(count) 个文件")
    }

    func encryptedOutputSubtitle(_ path: String) -> String {
        text(en: "Output to \(path)/encrypted", zh: "输出到 \(path)/encrypted")
    }

    func decryptedOutputSubtitle(_ path: String) -> String {
        text(en: "Output to \(path)/decrypted", zh: "输出到 \(path)/decrypted")
    }

    func encryptFilesTitle(_ count: Int) -> String {
        text(en: "Encrypt \(count) files", zh: "加密 \(count) 个文件")
    }

    func importedKeys(_ count: Int) -> String {
        text(en: "Imported \(count) keys", zh: "已导入 \(count) 个密钥")
    }

    func importedAgeConfigKeys(_ count: Int) -> String {
        text(en: "Imported \(count) keys from ~/.config/age", zh: "已从 ~/.config/age 导入 \(count) 个密钥")
    }

    func importKeyFileFailed(_ error: String) -> String {
        text(en: "Failed to import key file: \(error)", zh: "导入密钥文件失败: \(error)")
    }

    func goPurpose() -> String {
        text(en: "Streaming encryption and decryption engine", zh: "流式加解密引擎")
    }

    func keyNameForPrivateKey(_ fallbackName: String) -> String {
        fallbackName.isEmpty ? text(en: "Imported private key", zh: "导入的私钥") : fallbackName
    }

    func missingPrivateKey() -> String {
        text(en: "This key does not have a saved private key", zh: "这个密钥没有保存私钥")
    }

    func operationModeLabel(mode: EncryptionMode, compress: Bool) -> String {
        switch (mode, compress) {
        case (.batchPack, true): return text(en: "Batch and compress", zh: "打包压缩")
        case (.batchPack, false): return text(en: "Batch", zh: "打包")
        case (.separate, true): return text(en: "Separate and compress", zh: "分别压缩加密")
        case (.separate, false): return text(en: "Separate", zh: "分别加密")
        }
    }

    func outputCount(_ count: Int) -> String {
        text(en: "Show \(count) outputs", zh: "显示 \(count) 个输出")
    }

    func pastePrivateKeyPlaceholder() -> String {
        text(en: "Or paste an age private key", zh: "或粘贴 age 私钥")
    }

    func pastePublicKeyPlaceholder() -> String {
        text(en: "Or paste an age public key", zh: "或粘贴 age 公钥")
    }

    func phaseCancelled() -> String {
        text(en: "Canceled", zh: "已取消")
    }

    func phaseCancelling() -> String {
        text(en: "Cancelling", zh: "取消中")
    }

    func phaseComplete() -> String {
        text(en: "Complete", zh: "完成")
    }

    func phaseFailed() -> String {
        text(en: "Failed", zh: "失败")
    }

    func phasePreparing() -> String {
        text(en: "Preparing", zh: "准备中")
    }

    func privacyPolicySubtitle() -> String {
        text(en: "Local-first data handling notes", zh: "本地优先的数据处理说明")
    }

    func privacyPolicyTitle() -> String {
        text(en: "Privacy Policy", zh: "隐私协议")
    }

    func licenseTitle() -> String {
        text(en: "Open Source License", zh: "开源协议")
    }

    func remove() -> String {
        text(en: "Remove", zh: "移除")
    }

    func requireDecryptFiles() -> String {
        text(en: "Choose .age files to decrypt first", zh: "请先选择要解密的 .age 文件")
    }

    func requireDecryptPassphrase() -> String {
        text(en: "Enter a decrypt passphrase", zh: "请输入解密密码")
    }

    func requireEncryptFiles() -> String {
        text(en: "Choose files to encrypt first", zh: "请先选择要加密的文件")
    }

    func requireEncryptPassphrase() -> String {
        text(en: "Enter an encryption passphrase", zh: "请输入加密密码")
    }

    func requireKeyName() -> String {
        text(en: "Key name cannot be empty", zh: "密钥名称不能为空")
    }

    func requirePrivateKey() -> String {
        text(en: "Choose or enter a private key", zh: "请选择或输入私钥")
    }

    func requirePublicKey() -> String {
        text(en: "Choose or enter a public key", zh: "请选择或输入公钥")
    }

    func releasesTitle() -> String {
        text(en: "Releases", zh: "版本发布")
    }

    func savedStateFailed(_ error: String) -> String {
        text(en: "Failed to save local state: \(error)", zh: "保存本地状态失败: \(error)")
    }

    func saveKeyFailed(_ error: String) -> String {
        text(en: "Failed to export key: \(error)", zh: "导出密钥失败: \(error)")
    }

    func sparklePurpose() -> String {
        text(en: "macOS app updates", zh: "macOS 在线更新")
    }

    func updateCheck() -> String {
        text(en: "Check for Updates", zh: "检测更新")
    }

    func version(_ version: String) -> String {
        text(en: "Version \(version)", zh: "版本 \(version)")
    }

    private func text(en: String, zh: String) -> String {
        language == .english ? en : zh
    }
}
