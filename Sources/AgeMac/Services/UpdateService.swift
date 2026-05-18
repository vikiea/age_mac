/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import Darwin
import Foundation
import Sparkle

@MainActor
final class UpdateService: ObservableObject {
    private let feedProvider: ArchitectureFeedProvider
    private let updaterController: SPUStandardUpdaterController

    init() {
        let feedProvider = ArchitectureFeedProvider()
        self.feedProvider = feedProvider
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: feedProvider,
            userDriverDelegate: nil
        )
        self.updaterController.updater.clearFeedURLFromUserDefaults()
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

private final class ArchitectureFeedProvider: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        Self.architectureAppcastURL.absoluteString
    }

    private static var architectureAppcastURL: URL {
        if isAppleSiliconHardware {
            return AppLinks.arm64Appcast
        }

        #if arch(arm64)
        return AppLinks.arm64Appcast
        #elseif arch(x86_64)
        return AppLinks.x86_64Appcast
        #else
        return AppLinks.appcast
        #endif
    }

    private static var isAppleSiliconHardware: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 {
            return value == 1
        }

        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
}
