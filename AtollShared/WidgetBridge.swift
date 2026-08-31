/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation

/// What the widget draws.
///
/// Deliberately small and free of AppKit types: it crosses a process boundary
/// as JSON, and the widget extension should not have to know anything about
/// how Atoll models playback internally.
struct NowPlayingSnapshot: Codable, Equatable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    /// Bundle identifier of whatever is playing, so the widget can badge the
    /// source the way the notch does.
    var sourceBundleIdentifier: String?
    var updatedAt: Date

    static let placeholder = NowPlayingSnapshot(
        title: "Not Playing",
        artist: "",
        album: "",
        isPlaying: false,
        sourceBundleIdentifier: nil,
        updatedAt: .distantPast
    )
}

/// The channel between Atoll and its widget extension.
///
/// A widget extension is always sandboxed, even though Atoll itself is not, so
/// it cannot read the app's files or talk to `MusicManager`. Two mechanisms
/// bridge that gap, and each is picked for a specific reason:
///
/// - State travels through an **App Group container**, the only directory both
///   processes can open.
/// - Button presses travel back as **Darwin notifications**, which cross the
///   sandbox with no entitlement at all and need no running XPC service. Atoll
///   is a menu bar app and therefore always running to receive them.
enum WidgetBridge {
    /// Must match the `com.apple.security.application-groups` entitlement on
    /// both the app and the extension.
    static let appGroupIdentifier = "group.com.Ebullioscopic.Atoll"

    private static let snapshotFileName = "now-playing.json"
    private static let artworkFileName = "now-playing-artwork.png"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent(snapshotFileName)
    }

    static var artworkURL: URL? {
        containerURL?.appendingPathComponent(artworkFileName)
    }

    // MARK: - State

    /// Writes the snapshot, and the artwork alongside it when it has changed.
    ///
    /// Both are written atomically: the widget can be woken to read them at any
    /// moment, and a half-written file would render as a blank card.
    @discardableResult
    static func write(_ snapshot: NowPlayingSnapshot, artwork: Data?) -> Bool {
        guard let snapshotURL else { return false }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: snapshotURL, options: .atomic)

            if let artwork, let artworkURL {
                try artwork.write(to: artworkURL, options: .atomic)
            }
            return true
        } catch {
            return false
        }
    }

    static func read() -> NowPlayingSnapshot? {
        guard let snapshotURL, let data = try? Data(contentsOf: snapshotURL) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(NowPlayingSnapshot.self, from: data)
    }

    static func readArtwork() -> Data? {
        guard let artworkURL else { return nil }
        return try? Data(contentsOf: artworkURL)
    }

    // MARK: - Commands

    /// A transport command a widget button can send back to the app.
    enum Command: String, CaseIterable {
        case playPause
        case nextTrack
        case previousTrack

        /// Darwin notification names are a flat global namespace shared by
        /// every process on the machine, so these are fully qualified.
        var notificationName: String {
            "com.Ebullioscopic.Atoll.widget.\(rawValue)"
        }
    }

    /// Sent from the extension; the app is listening.
    static func post(_ command: Command) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(command.notificationName as CFString),
            nil,
            nil,
            true
        )
    }
}
