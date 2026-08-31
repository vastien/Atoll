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

/// A thing the closed notch can be showing.
///
/// Until now the closed notch picked exactly one of these from a chain of
/// `else if`s, so a timer running during a download showed only the timer and
/// the download simply vanished. This enum lets the state be resolved as an
/// ordered list instead, so the two highest-priority activities can share the
/// notch the way the iOS island does.
enum ClosedActivityKind: String, CaseIterable, Equatable, Identifiable {
    case music
    case timer
    case reminder
    case recording
    case download
    case localSend
    case focus
    case privacy
    case extensionPayload
    case shelf

    var id: String { rawValue }

    /// The glyph the compact half of a pair is drawn with.
    ///
    /// Only used for the leading slot of a pair: on its own an activity still
    /// draws its full standalone view.
    var compactSymbol: String {
        switch self {
        case .music: return "music.note"
        case .timer: return "timer"
        case .reminder: return "bell.fill"
        case .recording: return "record.circle"
        case .download: return "arrow.down.circle.fill"
        case .localSend: return "arrow.up.arrow.down.circle.fill"
        case .focus: return "moon.fill"
        case .privacy: return "camera.fill"
        case .extensionPayload: return "puzzlepiece.extension.fill"
        case .shelf: return "tray.fill"
        }
    }
}

/// Which closed-notch activities are live right now.
///
/// A flat value rather than a set of manager references so the ordering can be
/// decided -- and tested -- without standing up CoreAudio, EventKit, the
/// download watcher and the rest of the app.
struct ClosedActivityState: Equatable {
    var music = false
    var timer = false
    var reminder = false
    var recording = false
    var download = false
    var localSend = false
    var focus = false
    var privacy = false
    var extensionPayload = false
    var shelf = false

    func isActive(_ kind: ClosedActivityKind) -> Bool {
        switch kind {
        case .music: return music
        case .timer: return timer
        case .reminder: return reminder
        case .recording: return recording
        case .download: return download
        case .localSend: return localSend
        case .focus: return focus
        case .privacy: return privacy
        case .extensionPayload: return extensionPayload
        case .shelf: return shelf
        }
    }
}

enum ClosedActivityResolver {
    /// Highest priority first.
    ///
    /// This is the order the old `else if` chain already used, kept exactly so
    /// that whatever used to win the notch on its own still wins it.
    static let priority: [ClosedActivityKind] = [
        .music,
        .timer,
        .reminder,
        .recording,
        .download,
        .localSend,
        .focus,
        .privacy,
        .extensionPayload,
        .shelf
    ]

    /// Every active activity, most important first.
    static func active(in state: ClosedActivityState) -> [ClosedActivityKind] {
        priority.filter(state.isActive)
    }

    /// The at-most-two activities the closed notch shows.
    ///
    /// Anything past the second is dropped rather than stacked: the notch has a
    /// leading and a trailing wing and nowhere else to put a third.
    static func pair(in state: ClosedActivityState) -> (primary: ClosedActivityKind, secondary: ClosedActivityKind?)? {
        let active = active(in: state)
        guard let primary = active.first else { return nil }
        return (primary, active.dropFirst().first)
    }

    /// Whether the pair should be drawn by the generic compact container.
    ///
    /// Music already has a richer paired layout of its own -- artwork leading,
    /// supplement trailing -- and a lone activity still gets its full
    /// standalone view. The generic container is only for the case neither of
    /// those covers: two non-music activities at once.
    static func usesCompactPairing(in state: ClosedActivityState) -> Bool {
        guard let pair = pair(in: state) else { return false }
        return pair.primary != .music && pair.secondary != nil
    }
}
