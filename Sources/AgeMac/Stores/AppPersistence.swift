/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import Foundation

struct AppSnapshot {
    var keys: [KeyEntry]
    var operations: [OperationRecord]
    var settings: AppSettings
}

struct AppPersistence {
    static let historyLimit = 200

    var appSupportURL: URL

    init(appSupportURL: URL = AppPersistence.defaultAppSupportURL()) {
        self.appSupportURL = appSupportURL
    }

    func load() -> AppSnapshot {
        let legacyState = loadLegacyState()
        let settings = loadValue(AppSettings.self, from: settingsURL) ?? legacyState?.settings ?? .defaults()
        let keys = loadValue([KeyEntry].self, from: keysURL) ?? legacyState?.keys ?? []
        let operations = loadValue([OperationRecord].self, from: historyURL) ?? legacyState?.operations ?? []
        let snapshot = AppSnapshot(
            keys: keys,
            operations: Array(operations.prefix(Self.historyLimit)),
            settings: settings
        )
        migrateLegacyStateIfNeeded(legacyState, snapshot: snapshot)
        return snapshot
    }

    func saveKeys(_ keys: [KeyEntry]) throws {
        try saveValue(keys, to: keysURL)
    }

    func saveSettings(_ settings: AppSettings) throws {
        try saveValue(settings, to: settingsURL)
    }

    func saveHistory(_ operations: [OperationRecord]) throws {
        try saveValue(Array(operations.prefix(Self.historyLimit)), to: historyURL)
    }

    func save(snapshot: AppSnapshot) throws {
        try saveKeys(snapshot.keys)
        try saveSettings(snapshot.settings)
        try saveHistory(snapshot.operations)
    }

    static func defaultAppSupportURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("AgeMac", isDirectory: true)
    }

    var settingsURL: URL {
        appSupportURL.appendingPathComponent("settings.json")
    }

    var keysURL: URL {
        appSupportURL.appendingPathComponent("keys.json")
    }

    var historyURL: URL {
        appSupportURL.appendingPathComponent("history.json")
    }

    var legacyStateURL: URL {
        appSupportURL.appendingPathComponent("state.json")
    }

    private func saveValue<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: [.atomic])
    }

    private func loadValue<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func loadLegacyState() -> LegacyPersistedState? {
        loadValue(LegacyPersistedState.self, from: legacyStateURL)
    }

    private func migrateLegacyStateIfNeeded(_ legacyState: LegacyPersistedState?, snapshot: AppSnapshot) {
        guard legacyState != nil else { return }
        do {
            if !FileManager.default.fileExists(atPath: settingsURL.path) {
                try saveSettings(snapshot.settings)
            }
            if !FileManager.default.fileExists(atPath: keysURL.path) {
                try saveKeys(snapshot.keys)
            }
            if !FileManager.default.fileExists(atPath: historyURL.path) {
                try saveHistory(snapshot.operations)
            }
        } catch {
            return
        }
    }
}

private struct LegacyPersistedState: Codable {
    var keys: [KeyEntry]
    var operations: [OperationRecord]
    var settings: AppSettings
}
