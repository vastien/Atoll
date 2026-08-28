//
//  ClaudeDesktopQuotaReader.swift
//  DynamicIsland
//
//  Claude quota read from the Claude desktop app's own records.
//

import Foundation

/// Claude's quota, taken from what the desktop app has already written down.
///
/// The OAuth path needs a credential Claude Code left in the Keychain, which is
/// there only for someone signed in to the *terminal* client -- and it goes
/// stale, since an expired token with no refresh token cannot be renewed.
/// Anyone using only the desktop app therefore had no quota at all, despite
/// the app knowing the answer and keeping it on disk.
///
/// The desktop app samples its plan usage every so often and appends to
/// `plan-usage-history.json`. Each sample carries the same two figures the API
/// returns -- utilisation of the five-hour and seven-day windows, as
/// percentages -- so the newest one is a straight substitute.
struct ClaudeDesktopQuotaReader {
    /// How old the newest sample may be and still describe now. The app writes
    /// one every few tens of minutes, so a couple of hours leaves room for a
    /// quiet period without reporting yesterday's figures as today's.
    static let freshnessLimit: TimeInterval = 2 * 60 * 60

    let fileURL: URL
    let now: () -> Date

    init(
        fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json"),
        now: @escaping () -> Date = Date.init
    ) {
        self.fileURL = fileURL
        self.now = now
    }

    private struct History: Decodable {
        struct Sample: Decodable {
            struct Utilization: Decodable {
                /// Five-hour window, as a percentage.
                let fh: Double?
                /// Seven-day window, as a percentage.
                let sd: Double?
            }
            /// Milliseconds since the epoch.
            let t: Double
            let u: Utilization
        }
        let samples: [Sample]
    }

    /// The newest sample, if the file has one recent enough to mean anything.
    func limits() -> (session: UsageLimit?, week: UsageLimit?)? {
        guard let data = try? Data(contentsOf: fileURL),
              let history = try? JSONDecoder().decode(History.self, from: data)
        else { return nil }

        // Newest by timestamp rather than by position: the file is written as a
        // log, but trusting the order of someone else's file is a free way to be
        // wrong later.
        guard let newest = history.samples.max(by: { $0.t < $1.t }) else { return nil }

        let takenAt = Date(timeIntervalSince1970: newest.t / 1000)
        guard now().timeIntervalSince(takenAt) <= Self.freshnessLimit else { return nil }

        let session = newest.u.fh.map { UsageLimit(used: $0, limit: 100) }
        let week = newest.u.sd.map { UsageLimit(used: $0, limit: 100) }
        guard session != nil || week != nil else { return nil }
        return (session, week)
    }
}
