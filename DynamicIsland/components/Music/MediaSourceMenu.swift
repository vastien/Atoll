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

import Defaults
import SwiftUI

/// The little source badge on the album art, as a way to choose which app the
/// notch controls.
///
/// Several players can be sounding at once, and "Now Playing" follows whichever
/// touched the system last — so starting a video takes the controls away from
/// the music you actually wanted to steer. Naming a source pins it, and the
/// badge is where the question already gets asked, because it is the thing on
/// screen saying which app is being controlled.
struct MediaSourceMenu: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.mediaController) private var mediaController

    let size: CGFloat

    @State private var autoCloseToken = UUID()

    var body: some View {
        Menu {
            Picker("Media source", selection: $mediaController) {
                ForEach(availableControllers) { controller in
                    Text(label(for: controller)).tag(controller)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: size, height: size)
        .help("Choose which app the notch controls")
        // The notch closes itself when the pointer leaves, and a menu takes the
        // pointer with it. Hold it open from the moment the badge is hovered
        // until the menu has been dealt with.
        .onHover { vm.setAutoCloseSuppression($0, token: autoCloseToken) }
        .onChange(of: mediaController) { _, _ in
            vm.setAutoCloseSuppression(false, token: autoCloseToken)
            NotificationCenter.default.post(name: Notification.Name.mediaControllerChanged, object: nil)
        }
        .onDisappear { vm.setAutoCloseSuppression(false, token: autoCloseToken) }
    }

    /// "Now Playing" is the automatic one, and it is the only entry whose name
    /// does not say what it does.
    private func label(for controller: MediaControllerType) -> String {
        controller == .nowPlaying
            ? String(localized: "Now Playing (follows the active app)")
            : controller.localizedName
    }

    private var availableControllers: [MediaControllerType] {
        MusicManager.shared.isNowPlayingDeprecated
            ? MediaControllerType.allCases.filter { $0 != .nowPlaying }
            : MediaControllerType.allCases
    }
}
