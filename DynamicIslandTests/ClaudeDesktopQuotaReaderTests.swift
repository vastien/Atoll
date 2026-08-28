import XCTest
@testable import Atoll

final class ClaudeDesktopQuotaReaderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// `now` is fixed so a sample's age is a property of the test rather than of
    /// the day it runs.
    private let now = Date(timeIntervalSince1970: 1_787_951_400)

    private func reader(_ json: String) throws -> ClaudeDesktopQuotaReader {
        let url = directory.appendingPathComponent("plan-usage-history.json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return ClaudeDesktopQuotaReader(fileURL: url, now: { self.now })
    }

    private func history(ageSeconds: TimeInterval, fh: String = "85", sd: String = "48") -> String {
        let t = (now.timeIntervalSince1970 - ageSeconds) * 1000
        return #"{"version":2,"samples":[{"t":\#(t),"org":"o","u":{"fh":\#(fh),"sd":\#(sd)}}]}"#
    }

    func testAFreshSampleBecomesBothLimits() throws {
        let limits = try XCTUnwrap(reader(history(ageSeconds: 120)).limits())
        XCTAssertEqual(limits.session?.used, 85)
        XCTAssertEqual(limits.session?.limit, 100)
        XCTAssertEqual(limits.week?.used, 48)
        XCTAssertEqual(limits.session?.fraction ?? 0, 0.85, accuracy: 0.0001)
    }

    func testTheNewestSampleWinsRegardlessOfOrder() throws {
        let newest = (now.timeIntervalSince1970 - 60) * 1000
        let older = (now.timeIntervalSince1970 - 6000) * 1000
        let json = #"""
        {"version":2,"samples":[
          {"t":\#(newest),"org":"o","u":{"fh":90,"sd":50}},
          {"t":\#(older),"org":"o","u":{"fh":10,"sd":5}}
        ]}
        """#
        let limits = try XCTUnwrap(reader(json).limits())
        XCTAssertEqual(limits.session?.used, 90)
    }

    func testAStaleSampleIsNotReported() throws {
        let stale = ClaudeDesktopQuotaReader.freshnessLimit + 60
        XCTAssertNil(try reader(history(ageSeconds: stale)).limits())
    }

    func testASampleRightOnTheFreshnessLimitStillCounts() throws {
        XCTAssertNotNil(try reader(history(ageSeconds: ClaudeDesktopQuotaReader.freshnessLimit)).limits())
    }

    func testAWindowTheFileOmitsIsAbsentRatherThanZero() throws {
        let t = (now.timeIntervalSince1970 - 60) * 1000
        let json = #"{"version":2,"samples":[{"t":\#(t),"org":"o","u":{"fh":70}}]}"#
        let limits = try XCTUnwrap(reader(json).limits())
        XCTAssertEqual(limits.session?.used, 70)
        XCTAssertNil(limits.week)
    }

    func testASampleWithNeitherWindowIsNoAnswerAtAll() throws {
        let t = (now.timeIntervalSince1970 - 60) * 1000
        let json = #"{"version":2,"samples":[{"t":\#(t),"org":"o","u":{}}]}"#
        XCTAssertNil(try reader(json).limits())
    }

    func testAnEmptyHistoryIsNoAnswer() throws {
        XCTAssertNil(try reader(#"{"version":2,"samples":[]}"#).limits())
    }

    func testAMissingFileIsNoAnswer() {
        let missing = directory.appendingPathComponent("nothing-here.json")
        XCTAssertNil(ClaudeDesktopQuotaReader(fileURL: missing, now: { self.now }).limits())
    }

    func testUnreadableJSONIsNoAnswer() throws {
        XCTAssertNil(try reader("this is not json").limits())
    }
}
