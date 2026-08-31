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

import AppIntents
import WidgetKit

/// The transport buttons.
///
/// These run inside the widget extension, which is sandboxed and has no way to
/// drive playback itself. Each one posts a Darwin notification that Atoll --
/// always running, as a menu bar app -- picks up and executes through the media
/// controller the user has selected. Nothing here talks to a music app
/// directly, so the widget works with every source Atoll supports.
struct PlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play or Pause"
    static var description = IntentDescription("Plays or pauses the current track.")

    func perform() async throws -> some IntentResult {
        WidgetBridge.post(.playPause)
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Track"
    static var description = IntentDescription("Skips to the next track.")

    func perform() async throws -> some IntentResult {
        WidgetBridge.post(.nextTrack)
        return .result()
    }
}

struct PreviousTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Track"
    static var description = IntentDescription("Goes back to the previous track.")

    func perform() async throws -> some IntentResult {
        WidgetBridge.post(.previousTrack)
        return .result()
    }
}
