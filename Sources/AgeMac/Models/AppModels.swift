/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import AppKit
import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case english
    case chinese

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: "English"
        case .chinese: "中文"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .english: "en"
        case .chinese: "zh-Hans"
        }
    }
}

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .system: language == .english ? "System" : "跟随系统"
        case .dark: language == .english ? "Dark" : "深色"
        case .light: language == .english ? "Light" : "浅色"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        }
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case encrypt
    case decrypt
    case keys
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        title(in: .english)
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .encrypt: language == .english ? "Encrypt" : "加密"
        case .decrypt: language == .english ? "Decrypt" : "解密"
        case .keys: language == .english ? "Keys" : "密钥"
        case .history: language == .english ? "History" : "历史"
        case .settings: language == .english ? "Settings" : "设置"
        }
    }

    var subtitle: String {
        subtitle(in: .english)
    }

    func subtitle(in language: AppLanguage) -> String {
        switch self {
        case .encrypt: language == .english ? "Batch or separate encryption" : "打包或分别加密"
        case .decrypt: language == .english ? "Decrypt and auto-extract" : "解密并自动解包"
        case .keys: language == .english ? "X25519 keys" : "X25519 密钥"
        case .history: language == .english ? "Local operation history" : "本地操作记录"
        case .settings: language == .english ? "Output and tasks" : "输出与任务"
        }
    }

    var systemImage: String {
        switch self {
        case .encrypt: "lock.fill"
        case .decrypt: "lock.open.fill"
        case .keys: "key.fill"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape.fill"
        }
    }
}

enum EncryptionMode: String, Codable, CaseIterable, Identifiable {
    case batchPack
    case separate

    var id: String { rawValue }

    var title: String {
        title(in: .english)
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .batchPack: language == .english ? "Batch" : "打包"
        case .separate: language == .english ? "Separate" : "分别"
        }
    }

    var detail: String {
        detail(in: .english)
    }

    func detail(in language: AppLanguage) -> String {
        switch self {
        case .batchPack: language == .english ? "Combine multiple files into one archive" : "多个文件合成一个归档"
        case .separate: language == .english ? "Create one .tar.age per file" : "每个文件生成一个 .tar.age"
        }
    }
}

enum AuthMode: String, Codable, CaseIterable, Identifiable {
    case passphrase
    case key

    var id: String { rawValue }

    var title: String {
        title(in: .english)
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .passphrase: language == .english ? "Passphrase" : "密码"
        case .key: language == .english ? "Key" : "密钥"
        }
    }
}

enum DuplicateStrategy: String, Codable, CaseIterable, Identifiable {
    case rename
    case overwrite

    var id: String { rawValue }

    var title: String {
        title(in: .english)
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .rename: language == .english ? "Auto rename" : "自动重命名"
        case .overwrite: language == .english ? "Overwrite matching files" : "覆盖同名文件"
        }
    }

    var engineValue: String { rawValue }
}

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case teal
    case indigo
    case violet
    case rose
    case amber
    case graphite

    var id: String { rawValue }

    var title: String {
        title(in: .english)
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .teal: language == .english ? "Teal" : "青绿"
        case .indigo: language == .english ? "Indigo" : "靛蓝"
        case .violet: language == .english ? "Violet" : "紫罗兰"
        case .rose: language == .english ? "Rose" : "玫红"
        case .amber: language == .english ? "Amber" : "琥珀"
        case .graphite: language == .english ? "Graphite" : "石墨"
        }
    }
}

enum OperationKind: String, Codable, CaseIterable {
    case encrypt
    case decrypt

    var title: String {
        title(in: .english)
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .encrypt: language == .english ? "Encrypt" : "加密"
        case .decrypt: language == .english ? "Decrypt" : "解密"
        }
    }

    var systemImage: String {
        switch self {
        case .encrypt: "lock.fill"
        case .decrypt: "lock.open.fill"
        }
    }
}

enum OperationStatus: String, Codable {
    case running
    case success
    case failed
    case cancelled

    var title: String {
        title(in: .english)
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .running: language == .english ? "Running" : "运行中"
        case .success: language == .english ? "Success" : "成功"
        case .failed: language == .english ? "Failed" : "失败"
        case .cancelled: language == .english ? "Canceled" : "已取消"
        }
    }
}

enum OperationAuthMethod: String, Codable, Hashable {
    case passphrase
    case publicKey
    case privateKey

    func title(in language: AppLanguage) -> String {
        switch self {
        case .passphrase: language == .english ? "Passphrase" : "密码"
        case .publicKey: language == .english ? "Public key" : "公钥"
        case .privateKey: language == .english ? "Private key" : "私钥"
        }
    }
}

enum OperationCompression: String, Codable, Hashable {
    case enabled
    case disabled
    case notApplicable

    func title(in language: AppLanguage) -> String {
        switch self {
        case .enabled: language == .english ? "Compressed" : "已压缩"
        case .disabled: language == .english ? "No compression" : "未压缩"
        case .notApplicable: language == .english ? "Auto extract" : "自动解包"
        }
    }
}

struct OperationDetails: Codable, Hashable {
    var authMethod: OperationAuthMethod
    var keyHint: OperationKeyHint?
    var encryptionMode: EncryptionMode?
    var compression: OperationCompression
    var duplicateStrategy: DuplicateStrategy
    var concurrency: Int
    var inputCount: Int
    var outputDirectory: String

    func summaryItems(in language: AppLanguage) -> [String] {
        var items = [authSummary(in: language)]
        if let encryptionMode {
            items.append(encryptionMode.title(in: language))
        }
        items.append(compression.title(in: language))
        items.append(language == .english ? "Concurrency \(concurrency)" : "并发 \(concurrency)")
        items.append(duplicateStrategy.title(in: language))
        return items
    }

    private func authSummary(in language: AppLanguage) -> String {
        let title = authMethod.title(in: language)
        guard let keyHint, let detail = keyHint.displayText else {
            return title
        }
        return "\(title): \(detail)"
    }
}

struct OperationKeyHint: Codable, Hashable {
    var name: String?
    var publicKeyPreview: String?
    var privateKeyFingerprint: String?

    var displayText: String? {
        let cleanName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPublicKeyPreview = publicKeyPreview?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPrivateKeyFingerprint = privateKeyFingerprint?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let cleanName, !cleanName.isEmpty {
            if let cleanPublicKeyPreview, !cleanPublicKeyPreview.isEmpty {
                return "\(cleanName) (\(cleanPublicKeyPreview))"
            }
            if let cleanPrivateKeyFingerprint, !cleanPrivateKeyFingerprint.isEmpty {
                return "\(cleanName) (\(cleanPrivateKeyFingerprint))"
            }
            return cleanName
        }
        if let cleanPublicKeyPreview, !cleanPublicKeyPreview.isEmpty {
            return cleanPublicKeyPreview
        }
        if let cleanPrivateKeyFingerprint, !cleanPrivateKeyFingerprint.isEmpty {
            return cleanPrivateKeyFingerprint
        }
        return nil
    }
}

struct SelectedFile: Identifiable, Codable, Hashable {
    var id: UUID
    var path: String
    var name: String
    var size: Int64

    init(url: URL) {
        self.id = UUID()
        self.path = url.path
        self.name = url.lastPathComponent
        self.size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    }

    init(url: URL, name: String) {
        self.id = UUID()
        self.path = url.path
        self.name = name
        self.size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    }

    var url: URL { URL(fileURLWithPath: path) }
}

struct KeyEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var publicKey: String
    var privateKey: String?
    var privateKeyStored: Bool
    var createdAt: Date

    init(
        id: UUID,
        name: String,
        publicKey: String,
        privateKey: String?,
        createdAt: Date,
        privateKeyStored: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.privateKeyStored = privateKeyStored ?? (privateKey?.isEmpty == false)
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case publicKey
        case privateKey
        case privateKeyStored
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        publicKey = try container.decode(String.self, forKey: .publicKey)
        privateKey = try container.decodeIfPresent(String.self, forKey: .privateKey)
        privateKeyStored = try container.decodeIfPresent(Bool.self, forKey: .privateKeyStored) ?? (privateKey?.isEmpty == false)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(publicKey, forKey: .publicKey)
        try container.encode(privateKeyStored, forKey: .privateKeyStored)
        try container.encode(createdAt, forKey: .createdAt)
    }

    var hasPrivateKey: Bool { privateKeyStored || privateKey?.isEmpty == false }

    func withPrivateKey(_ privateKey: String?, privateKeyStored: Bool? = nil) -> KeyEntry {
        KeyEntry(
            id: id,
            name: name,
            publicKey: publicKey,
            privateKey: privateKey,
            createdAt: createdAt,
            privateKeyStored: privateKeyStored ?? self.privateKeyStored
        )
    }
}

struct OperationRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: OperationKind
    var modeLabel: String
    var inputFiles: [String]
    var outputPath: String
    var recipientInfo: String
    var status: OperationStatus
    var errorMessage: String?
    var outputs: [String]
    var timestamp: Date
    var details: OperationDetails?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case modeLabel
        case inputFiles
        case outputPath
        case recipientInfo
        case status
        case errorMessage
        case outputs
        case timestamp
        case details
    }

    init(
        id: UUID,
        kind: OperationKind,
        modeLabel: String,
        inputFiles: [String],
        outputPath: String,
        recipientInfo: String,
        status: OperationStatus,
        errorMessage: String?,
        outputs: [String],
        timestamp: Date,
        details: OperationDetails? = nil
    ) {
        self.id = id
        self.kind = kind
        self.modeLabel = modeLabel
        self.inputFiles = inputFiles
        self.outputPath = outputPath
        self.recipientInfo = recipientInfo
        self.status = status
        self.errorMessage = errorMessage
        self.outputs = outputs
        self.timestamp = timestamp
        self.details = details
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(OperationKind.self, forKey: .kind)
        modeLabel = try container.decode(String.self, forKey: .modeLabel)
        inputFiles = try container.decode([String].self, forKey: .inputFiles)
        outputPath = try container.decode(String.self, forKey: .outputPath)
        recipientInfo = try container.decode(String.self, forKey: .recipientInfo)
        status = try container.decode(OperationStatus.self, forKey: .status)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        outputs = try container.decodeIfPresent([String].self, forKey: .outputs) ?? []
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        details = try container.decodeIfPresent(OperationDetails.self, forKey: .details)
    }
}

struct AppSettings: Codable, Hashable {
    var outputDirectory: String
    var duplicateStrategy: DuplicateStrategy
    var compressEnabled: Bool
    var concurrency: Int
    var language: AppLanguage
    var appearance: AppAppearance
    var theme: AppTheme
    var gaussianTransparencyEnabled: Bool
    var gaussianTransparencyOpacity: Int

    static func defaults() -> AppSettings {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return AppSettings(
            outputDirectory: home.appendingPathComponent("Documents/Age Mac Output").path,
            duplicateStrategy: .rename,
            compressEnabled: false,
            concurrency: 4,
            language: .english,
            appearance: .system,
            theme: .teal,
            gaussianTransparencyEnabled: false,
            gaussianTransparencyOpacity: 55
        )
    }

    enum CodingKeys: String, CodingKey {
        case outputDirectory
        case duplicateStrategy
        case compressEnabled
        case concurrency
        case language
        case appearance
        case theme
        case gaussianTransparencyEnabled
        case gaussianTransparencyOpacity
    }

    init(
        outputDirectory: String,
        duplicateStrategy: DuplicateStrategy,
        compressEnabled: Bool,
        concurrency: Int,
        language: AppLanguage,
        appearance: AppAppearance,
        theme: AppTheme,
        gaussianTransparencyEnabled: Bool,
        gaussianTransparencyOpacity: Int
    ) {
        self.outputDirectory = outputDirectory
        self.duplicateStrategy = duplicateStrategy
        self.compressEnabled = compressEnabled
        self.concurrency = concurrency
        self.language = language
        self.appearance = appearance
        self.theme = theme
        self.gaussianTransparencyEnabled = gaussianTransparencyEnabled
        self.gaussianTransparencyOpacity = Self.clampGaussianTransparencyOpacity(gaussianTransparencyOpacity)
    }

    init(from decoder: Decoder) throws {
        let defaults = AppSettings.defaults()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outputDirectory = try container.decodeIfPresent(String.self, forKey: .outputDirectory) ?? defaults.outputDirectory
        duplicateStrategy = try container.decodeIfPresent(DuplicateStrategy.self, forKey: .duplicateStrategy) ?? defaults.duplicateStrategy
        compressEnabled = try container.decodeIfPresent(Bool.self, forKey: .compressEnabled) ?? defaults.compressEnabled
        concurrency = try container.decodeIfPresent(Int.self, forKey: .concurrency) ?? defaults.concurrency
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? defaults.language
        appearance = try container.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? defaults.appearance
        let themeValue = try container.decodeIfPresent(String.self, forKey: .theme)
        theme = themeValue.flatMap(AppTheme.init(rawValue:)) ?? defaults.theme
        gaussianTransparencyEnabled = try container.decodeIfPresent(Bool.self, forKey: .gaussianTransparencyEnabled) ?? defaults.gaussianTransparencyEnabled
        let opacity = try Self.decodeGaussianTransparencyOpacity(from: container, defaults: defaults)
        gaussianTransparencyOpacity = Self.clampGaussianTransparencyOpacity(opacity)
    }

    private static func decodeGaussianTransparencyOpacity(
        from container: KeyedDecodingContainer<CodingKeys>,
        defaults: AppSettings
    ) throws -> Int {
        if let intValue = try container.decodeIfPresent(Int.self, forKey: .gaussianTransparencyOpacity) {
            return intValue
        }
        if let doubleValue = try container.decodeIfPresent(Double.self, forKey: .gaussianTransparencyOpacity) {
            return Int((doubleValue * 100).rounded())
        }
        return defaults.gaussianTransparencyOpacity
    }

    static func clampGaussianTransparencyOpacity(_ value: Int) -> Int {
        min(max(value, 0), 100)
    }
}

struct RunningOperation: Identifiable, Hashable {
    var id: UUID
    var kind: OperationKind
    var title: String
    var phase: String
    var progress: Double
    var processed: Int
    var total: Int
    var success: Int
    var fail: Int
    var status: OperationStatus
    var outputs: [String]
    var errorMessage: String?

    static func started(id: UUID, kind: OperationKind, title: String, phase: String, total: Int) -> RunningOperation {
        RunningOperation(
            id: id,
            kind: kind,
            title: title,
            phase: phase,
            progress: 0,
            processed: 0,
            total: total,
            success: 0,
            fail: 0,
            status: .running,
            outputs: [],
            errorMessage: nil
        )
    }
}

struct EngineFileSpec: Codable {
    var path: String
    var name: String
}

struct EngineEvent: Codable {
    var event: String
    var phase: String?
    var progress: Double?
    var processed: Int?
    var total: Int?
    var success: Int?
    var fail: Int?
    var output: String?
    var outputs: [String]?
    var message: String?
    var publicKey: String?
    var privateKey: String?
}

struct EngineResult: Hashable {
    var success: Int
    var fail: Int
    var outputs: [String]
}
