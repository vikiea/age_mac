/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case encrypt
    case decrypt
    case keys
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .encrypt: "加密"
        case .decrypt: "解密"
        case .keys: "密钥"
        case .history: "历史"
        case .settings: "设置"
        }
    }

    var subtitle: String {
        switch self {
        case .encrypt: "打包或分别加密"
        case .decrypt: "解密并自动解包"
        case .keys: "X25519 密钥"
        case .history: "本地操作记录"
        case .settings: "输出与任务"
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
        switch self {
        case .batchPack: "打包"
        case .separate: "分别"
        }
    }

    var detail: String {
        switch self {
        case .batchPack: "多个文件合成一个归档"
        case .separate: "每个文件生成一个 .tar.age"
        }
    }
}

enum AuthMode: String, Codable, CaseIterable, Identifiable {
    case passphrase
    case key

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passphrase: "密码"
        case .key: "密钥"
        }
    }
}

enum DuplicateStrategy: String, Codable, CaseIterable, Identifiable {
    case rename
    case overwrite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rename: "自动重命名"
        case .overwrite: "覆盖同名文件"
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
        switch self {
        case .teal: "青绿"
        case .indigo: "靛蓝"
        case .violet: "紫罗兰"
        case .rose: "玫红"
        case .amber: "琥珀"
        case .graphite: "石墨"
        }
    }
}

enum OperationKind: String, Codable, CaseIterable {
    case encrypt
    case decrypt

    var title: String {
        switch self {
        case .encrypt: "加密"
        case .decrypt: "解密"
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
        switch self {
        case .running: "运行中"
        case .success: "成功"
        case .failed: "失败"
        case .cancelled: "已取消"
        }
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

    var url: URL { URL(fileURLWithPath: path) }
}

struct KeyEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var publicKey: String
    var privateKey: String?
    var createdAt: Date

    var hasPrivateKey: Bool { privateKey?.isEmpty == false }
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
}

struct AppSettings: Codable, Hashable {
    var outputDirectory: String
    var duplicateStrategy: DuplicateStrategy
    var compressEnabled: Bool
    var concurrency: Int
    var theme: AppTheme
    var gaussianTransparencyEnabled: Bool
    var gaussianTransparencyOpacity: Int

    static func defaults() -> AppSettings {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return AppSettings(
            outputDirectory: home.appendingPathComponent("Documents/Age Mac Output").path,
            duplicateStrategy: .rename,
            compressEnabled: true,
            concurrency: 4,
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
        case theme
        case gaussianTransparencyEnabled
        case gaussianTransparencyOpacity
    }

    init(
        outputDirectory: String,
        duplicateStrategy: DuplicateStrategy,
        compressEnabled: Bool,
        concurrency: Int,
        theme: AppTheme,
        gaussianTransparencyEnabled: Bool,
        gaussianTransparencyOpacity: Int
    ) {
        self.outputDirectory = outputDirectory
        self.duplicateStrategy = duplicateStrategy
        self.compressEnabled = compressEnabled
        self.concurrency = concurrency
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

    static func started(id: UUID, kind: OperationKind, title: String, total: Int) -> RunningOperation {
        RunningOperation(
            id: id,
            kind: kind,
            title: title,
            phase: "准备中",
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
