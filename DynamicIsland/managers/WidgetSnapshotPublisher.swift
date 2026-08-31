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

import AppKit
import Combine
import Foundation
import WidgetKit
import os.log

private let widgetLog = OSLog(subsystem: "com.atoll.dynamicisland", category: "Widgets")

/// Keeps the desktop widgets fed, and carries their button presses back into
/// the app.
///
/// The widget extension is sandboxed and cannot reach `MusicManager`, so this
/// is the only thing on the app side that knows the widgets exist.
@MainActor
final class WidgetSnapshotPublisher {
    static let shared = WidgetSnapshotPublisher()

    private var cancellables = Set<AnyCancellable>()
    private var lastSnapshot: NowPlayingSnapshot?
    private var lastArtworkHash: Int?
    private var isStarted = false

    /// Widgets refresh on the order of seconds, and a scrubbing track would
    /// otherwise rewrite the container many times a second for no visible gain.
    private static let coalescingInterval: TimeInterval = 0.4

    /// Artwork is decoded inside a memory-limited extension, so it is scaled
    /// down here rather than handing over a full-size cover.
    private static let artworkSide: CGFloat = 256

    private init() {}

    func start() {
        guard !isStarted else { return }
        guard WidgetBridge.containerURL != nil else {
            // No container means the App Group entitlement is missing, which is
            // what an unsigned local build looks like. Widgets simply will not
            // appear; nothing else should break.
            os_log(.info, log: widgetLog, "No App Group container -- widgets disabled for this build")
            return
        }
        isStarted = true

        let music = MusicManager.shared
        Publishers.CombineLatest4(
            music.$songTitle,
            music.$artistName,
            music.$album,
            music.$isPlaying
        )
        .combineLatest(music.$albumArt)
        .debounce(for: .seconds(Self.coalescingInterval), scheduler: RunLoop.main)
        .sink { [weak self] _, _ in
            self?.publish()
        }
        .store(in: &cancellables)

        observeCommands()
        publish()
    }

    // MARK: - Publishing

    private func publish() {
        let music = MusicManager.shared
        let snapshot = NowPlayingSnapshot(
            title: music.songTitle,
            artist: music.artistName,
            album: music.album,
            isPlaying: music.isPlaying,
            sourceBundleIdentifier: music.bundleIdentifier,
            updatedAt: Date()
        )

        let artwork = pngData(for: music.albumArt)
        let artworkHash = artwork?.hashValue

        // `updatedAt` changes on every call, so compare everything else: an
        // unchanged track must not reload the timelines.
        let unchanged = lastSnapshot.map {
            $0.title == snapshot.title
                && $0.artist == snapshot.artist
                && $0.album == snapshot.album
                && $0.isPlaying == snapshot.isPlaying
                && $0.sourceBundleIdentifier == snapshot.sourceBundleIdentifier
        } ?? false

        guard !unchanged || artworkHash != lastArtworkHash else { return }

        lastSnapshot = snapshot
        lastArtworkHash = artworkHash

        guard WidgetBridge.write(snapshot, artwork: artwork) else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func pngData(for image: NSImage) -> Data? {
        let side = Self.artworkSide
        let scaled = NSImage(size: NSSize(width: side, height: side))

        scaled.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: side, height: side),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        scaled.unlockFocus()

        guard let tiff = scaled.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    // MARK: - Commands from the widget

    private func observeCommands() {
        for command in WidgetBridge.Command.allCases {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque(),
                { _, observer, name, _, _ in
                    guard let observer, let name else { return }
                    let publisher = Unmanaged<WidgetSnapshotPublisher>
                        .fromOpaque(observer)
                        .takeUnretainedValue()

                    // The Darwin callback arrives on an arbitrary thread and
                    // carries no payload beyond the name, so the command is
                    // recovered from it and handled back on the main actor.
                    let raw = name.rawValue as String
                    Task { @MainActor in
                        publisher.handle(notificationName: raw)
                    }
                },
                command.notificationName as CFString,
                nil,
                .deliverImmediately
            )
        }
    }

    private func handle(notificationName: String) {
        guard let command = WidgetBridge.Command.allCases.first(
            where: { $0.notificationName == notificationName }
        ) else { return }

        switch command {
        case .playPause:
            MusicManager.shared.togglePlay()
        case .nextTrack:
            MusicManager.shared.nextTrack()
        case .previousTrack:
            MusicManager.shared.previousTrack()
        }

        // The app's own state lands a beat after the command does; give it a
        // moment before telling the widgets to redraw.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            self.publish()
        }
    }
}
