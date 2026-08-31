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

import XCTest
@testable import Atoll

/// Which activities the closed notch shows, and in which slot.
///
/// This replaced a chain of `else if`s, so the tests that matter most are the
/// ones proving the old winner still wins: anything that used to own the notch
/// on its own must still own it.
final class ClosedActivityResolverTests: XCTestCase {

    // MARK: - Ordering

    func testNothingActiveResolvesToNoPair() {
        XCTAssertNil(ClosedActivityResolver.pair(in: ClosedActivityState()))
        XCTAssertTrue(ClosedActivityResolver.active(in: ClosedActivityState()).isEmpty)
    }

    func testASingleActivityIsThePrimaryWithNoSecondary() {
        let pair = ClosedActivityResolver.pair(in: ClosedActivityState(download: true))
        XCTAssertEqual(pair?.primary, .download)
        XCTAssertNil(pair?.secondary)
    }

    func testMusicOutranksEverythingElse() {
        var state = ClosedActivityState()
        state.music = true
        state.timer = true
        state.shelf = true

        XCTAssertEqual(ClosedActivityResolver.pair(in: state)?.primary, .music)
    }

    func testPriorityIsIndependentOfWhichFlagsAreSet() {
        // The old chain's order, spot-checked pairwise: the lower-priority one
        // must never take the primary slot.
        let cases: [(ClosedActivityKind, ClosedActivityKind)] = [
            (.timer, .reminder),
            (.reminder, .recording),
            (.recording, .download),
            (.download, .localSend),
            (.localSend, .focus),
            (.focus, .privacy),
            (.privacy, .extensionPayload),
            (.extensionPayload, .shelf)
        ]

        for (higher, lower) in cases {
            var state = ClosedActivityState()
            set(&state, lower, true)
            set(&state, higher, true)

            let pair = ClosedActivityResolver.pair(in: state)
            XCTAssertEqual(pair?.primary, higher, "\(higher.rawValue) should outrank \(lower.rawValue)")
            XCTAssertEqual(pair?.secondary, lower)
        }
    }

    func testThirdAndLaterActivitiesAreDropped() {
        // The notch has a leading and a trailing wing and nowhere to put a
        // third, so extras are dropped rather than stacked.
        var state = ClosedActivityState()
        state.timer = true
        state.download = true
        state.focus = true
        state.shelf = true

        let pair = ClosedActivityResolver.pair(in: state)
        XCTAssertEqual(pair?.primary, .timer)
        XCTAssertEqual(pair?.secondary, .download)
        XCTAssertEqual(ClosedActivityResolver.active(in: state).count, 4)
    }

    // MARK: - usesCompactPairing

    func testTheCompactPairIsOnlyUsedForTwoNonMusicActivities() {
        var state = ClosedActivityState()
        state.timer = true
        state.download = true
        XCTAssertTrue(ClosedActivityResolver.usesCompactPairing(in: state))
    }

    func testASingleActivityKeepsItsStandaloneView() {
        // The regression this guards: a lone download must not lose its full
        // live activity just because the pairing code now exists.
        XCTAssertFalse(ClosedActivityResolver.usesCompactPairing(in: ClosedActivityState(download: true)))
    }

    func testMusicPairsWithItsOwnRicherLayoutInstead() {
        var state = ClosedActivityState()
        state.music = true
        state.timer = true
        XCTAssertFalse(ClosedActivityResolver.usesCompactPairing(in: state))
    }

    func testNothingActiveDoesNotPair() {
        XCTAssertFalse(ClosedActivityResolver.usesCompactPairing(in: ClosedActivityState()))
    }

    // MARK: - Coverage of the enum itself

    func testEveryKindHasAPriorityAndAGlyph() {
        // A kind added to the enum but not to `priority` would silently never
        // be shown, which is exactly the bug this feature is fixing.
        XCTAssertEqual(Set(ClosedActivityResolver.priority), Set(ClosedActivityKind.allCases))
        XCTAssertEqual(ClosedActivityResolver.priority.count, ClosedActivityKind.allCases.count)

        for kind in ClosedActivityKind.allCases {
            XCTAssertFalse(kind.compactSymbol.isEmpty, "\(kind.rawValue) has no glyph")
        }
    }

    func testIsActiveAgreesWithEveryFlag() {
        // Guards the hand-written switch in `isActive` against a flag being
        // wired to the wrong case.
        for kind in ClosedActivityKind.allCases {
            var state = ClosedActivityState()
            set(&state, kind, true)

            XCTAssertEqual(ClosedActivityResolver.active(in: state), [kind])
        }
    }

    // MARK: - Helpers

    private func set(_ state: inout ClosedActivityState, _ kind: ClosedActivityKind, _ value: Bool) {
        switch kind {
        case .music: state.music = value
        case .timer: state.timer = value
        case .reminder: state.reminder = value
        case .recording: state.recording = value
        case .download: state.download = value
        case .localSend: state.localSend = value
        case .focus: state.focus = value
        case .privacy: state.privacy = value
        case .extensionPayload: state.extensionPayload = value
        case .shelf: state.shelf = value
        }
    }
}
