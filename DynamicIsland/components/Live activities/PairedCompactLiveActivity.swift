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

/// Two activities sharing the closed notch, one either side of the cutout.
///
/// Mirrors the layout the music activity already uses -- leading wing, black
/// centre matching the physical notch, trailing wing -- so a pair sits at the
/// same height and reads as the same object. Each half is compact by
/// necessity: with two activities up there is only a wing each, which is the
/// same trade the iOS island makes.
struct PairedCompactLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel

    let leading: ClosedActivityKind
    let trailing: ClosedActivityKind
    let isHovering: Bool
    let gestureProgress: CGFloat

    @ObservedObject private var timerManager = TimerManager.shared

    private var notchContentHeight: CGFloat {
        isHovering ? max(0, vm.effectiveClosedNotchHeight) : max(0, vm.effectiveClosedNotchHeight - 12)
    }

    private var outerHeight: CGFloat {
        vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0)
    }

    private var wingBaseWidth: CGFloat {
        max(0, notchContentHeight + gestureProgress / 2)
    }

    private var centerWidth: CGFloat {
        max(vm.closedNotchSize.width + (isHovering ? 8 : 0), 96)
    }

    /// A wing wide enough for a glyph and its label without letting one side
    /// grow so far that the pair stops being symmetrical.
    private func wingWidth(for kind: ClosedActivityKind) -> CGFloat {
        guard let label = label(for: kind) else { return wingBaseWidth }
        let labelWidth = CGFloat(label.count) * 7 + 10
        return min(max(wingBaseWidth, wingBaseWidth + labelWidth), wingBaseWidth + centerWidth * 0.5)
    }

    var body: some View {
        HStack(spacing: 0) {
            half(leading)
                .frame(width: wingWidth(for: leading), height: notchContentHeight, alignment: .center)

            Rectangle()
                .fill(.black)
                .frame(width: centerWidth, height: notchContentHeight)

            half(trailing)
                .frame(width: wingWidth(for: trailing), height: notchContentHeight, alignment: .center)
        }
        .frame(height: outerHeight, alignment: .center)
        .animation(.smooth(duration: 0.25), value: leading)
        .animation(.smooth(duration: 0.25), value: trailing)
    }

    private func half(_ kind: ClosedActivityKind) -> some View {
        HStack(spacing: 4) {
            Image(systemName: kind.compactSymbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint(for: kind))

            if let label = label(for: kind) {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint(for: kind))
                    .lineLimit(1)
            }
        }
        .id(kind.id)
        .contentTransition(.symbolEffect(.replace))
    }

    /// The one number an activity is worth showing in a space this small.
    /// `nil` leaves the glyph to speak for itself, which is the usual case --
    /// a wing beside the notch fits a countdown and not much else.
    private func label(for kind: ClosedActivityKind) -> String? {
        switch kind {
        case .timer:
            return Defaults[.timerShowsCountdown] ? timerManager.formattedRemainingTime() : nil
        default:
            return nil
        }
    }

    private func tint(for kind: ClosedActivityKind) -> Color {
        switch kind {
        case .timer: return timerManager.timerColor
        case .recording, .privacy: return .red
        case .focus: return .indigo
        default: return .white
        }
    }
}
