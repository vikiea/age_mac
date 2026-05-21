/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import AppKit
import Foundation
import UniformTypeIdentifiers

enum FilePanelService {
    static func chooseFiles(allowedExtensions: [String]? = nil) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if let allowedExtensions {
            panel.allowedContentTypes = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        }
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseFile(allowedExtensions: [String]? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if let allowedExtensions {
            panel.allowedContentTypes = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func filesInFolder(_ folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true ? url : nil
        }
    }

    static func reveal(path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }

        let folder = url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: folder.path) {
            NSWorkspace.shared.open(folder)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func saveFile(defaultName: String, allowedExtensions: [String]? = nil) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        if let allowedExtensions {
            panel.allowedContentTypes = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
