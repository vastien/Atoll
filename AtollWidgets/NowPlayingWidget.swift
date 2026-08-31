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
import SwiftUI
import WidgetKit

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: NowPlayingSnapshot
    let artwork: NSImage?
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), snapshot: .placeholder, artwork: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        // A single entry with no refresh date: the app pushes a reload the
        // moment anything changes, so polling on a timer would only spend the
        // widget's refresh budget redrawing an unchanged card.
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> NowPlayingEntry {
        let snapshot = WidgetBridge.read() ?? .placeholder
        let artwork = WidgetBridge.readArtwork().flatMap(NSImage.init(data:))
        return NowPlayingEntry(date: Date(), snapshot: snapshot, artwork: artwork)
    }
}

// MARK: - Widgets

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.Ebullioscopic.Atoll.NowPlaying", provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    ArtworkBackground(artwork: entry.artwork)
                }
        }
        .configurationDisplayName("Now Playing")
        .description("Shows what Atoll is playing, with playback controls.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// The artwork-only variant, for people who want the cover and nothing else.
struct NowPlayingArtworkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.Ebullioscopic.Atoll.NowPlayingArtwork", provider: NowPlayingProvider()) { entry in
            ArtworkWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    ArtworkBackground(artwork: entry.artwork)
                }
        }
        .configurationDisplayName("Album Art")
        .description("Fills the widget with the current album artwork.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Views

/// The cover, blurred and darkened, behind every size.
///
/// Widgets have no vibrancy to sit on, so the card supplies its own ground; a
/// flat colour behind white text reads as a different app from the notch.
private struct ArtworkBackground: View {
    let artwork: NSImage?

    var body: some View {
        ZStack {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 24)
                Color.black.opacity(0.45)
            } else {
                Color.black.opacity(0.85)
            }
        }
    }
}

private struct ArtworkView: View {
    let artwork: NSImage?
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct TrackLabels: View {
    let snapshot: NowPlayingSnapshot
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(snapshot.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if !snapshot.artist.isEmpty {
                Text(snapshot.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
    }
}

private struct TransportControls: View {
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 18) {
            Button(intent: PreviousTrackIntent()) {
                Image(systemName: "backward.fill")
            }
            Button(intent: PlayPauseIntent()) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 18)
            }
            Button(intent: NextTrackIntent()) {
                Image(systemName: "forward.fill")
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(.white)
        .buttonStyle(.plain)
    }
}

struct NowPlayingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowPlayingEntry

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 12) {
                ArtworkView(artwork: entry.artwork)
                    .aspectRatio(1, contentMode: .fit)

                VStack(spacing: 10) {
                    TrackLabels(snapshot: entry.snapshot, alignment: .center)
                        .multilineTextAlignment(.center)
                    TransportControls(isPlaying: entry.snapshot.isPlaying)
                }
                .frame(maxWidth: .infinity)
            }
        default:
            // Small: artwork and labels only. Three transport targets in a
            // small widget end up below the size a pointer can reliably hit,
            // and the whole card already opens Atoll when clicked.
            VStack(alignment: .leading, spacing: 8) {
                ArtworkView(artwork: entry.artwork)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TrackLabels(snapshot: entry.snapshot)
            }
        }
    }
}

struct ArtworkWidgetView: View {
    let entry: NowPlayingEntry

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkView(artwork: entry.artwork, cornerRadius: 0)

            // Gradient rather than a flat scrim: the labels sit over whatever
            // the bottom of the cover happens to be, which is often bright.
            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )

            TrackLabels(snapshot: entry.snapshot)
                .padding(10)
        }
        .padding(-16)
    }
}
