import XCTest
@testable import ClaudeTokenManagerCore

/// Tests for the typed RawUsageReport JSON model and the
/// ClaudeAIDataSource.convert() snapshot mapper. The transport layer
/// (URLSession, Keychain, cert pinning, SessionKey redaction) was
/// replaced by WKWebView in v3.0.0; the tests for those types were
/// removed alongside the deleted files.
final class ClaudeAPIClientTests: XCTestCase {

    func testParseFullUsageResponse() throws {
        let json = """
        {
          "five_hour": {"utilization": 10.0, "resets_at": "2026-04-20T17:00:00.154153+00:00"},
          "seven_day": {"utilization": 5.0, "resets_at": "2026-04-27T07:00:01.154175+00:00"},
          "seven_day_oauth_apps": null,
          "seven_day_opus": null,
          "seven_day_sonnet": {"utilization": 0.0, "resets_at": "2026-04-27T07:00:01.154186+00:00"},
          "seven_day_cowork": null,
          "seven_day_omelette": {"utilization": 73.0, "resets_at": "2026-04-27T08:00:00.154199+00:00"},
          "iguana_necktie": null,
          "omelette_promotional": null,
          "extra_usage": {"is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null, "currency": null}
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { d in
            let c = try d.singleValueContainer()
            let s = try c.decode(String.self)
            return isoFormatter.date(from: s) ?? Date()
        }

        let report = try decoder.decode(RawUsageReport.self, from: json)
        XCTAssertEqual(report.fiveHour?.utilization, 10.0)
        XCTAssertEqual(report.sevenDayOmelette?.utilization, 73.0)
        XCTAssertNil(report.sevenDayOpus)
    }

    func testConvertPopulatesRemoteProgressBars() {
        let formatter = ISO8601DateFormatter()
        let later = formatter.date(from: "2026-04-27T07:00:01Z")!

        let raw = RawUsageReport(
            fiveHour: .init(utilization: 78, resetsAt: later),
            sevenDay: .init(utilization: 6, resetsAt: later),
            sevenDayOauthApps: nil,
            sevenDayOpus: nil,
            sevenDaySonnet: .init(utilization: 1, resetsAt: later),
            sevenDayCowork: nil,
            sevenDayOmelette: .init(utilization: 43, resetsAt: later),
            iguanaNecktie: nil,
            omelettePromotional: nil,
            extraUsage: nil
        )
        let snapshot = ClaudeAIDataSource.convert(raw: raw)

        let bars = snapshot.remoteProgressBars
        XCTAssertEqual(bars.count, 4)

        let sessionBar = bars.first { $0.id == "session" }
        XCTAssertNotNil(sessionBar)
        XCTAssertEqual(sessionBar?.percent, 78)
        XCTAssertEqual(sessionBar?.label, "Current session")

        let designBar = bars.first { $0.id == "design" }
        XCTAssertEqual(designBar?.percent, 43)
        XCTAssertEqual(designBar?.label, "Claude Design")

        XCTAssertNil(bars.first { $0.id == "opus" })
    }

    func testHottestBarIsSessionWhenHighest() {
        var snapshot = UsageSnapshot()
        snapshot.remoteProgressBars = [
            RemoteProgressBar(id: "session", label: "S", percent: 78, resetsAt: nil),
            RemoteProgressBar(id: "design", label: "D", percent: 43, resetsAt: nil),
            RemoteProgressBar(id: "all", label: "A", percent: 6, resetsAt: nil)
        ]
        XCTAssertEqual(snapshot.hottestRemoteBar?.id, "session")
        XCTAssertEqual(snapshot.hottestRemoteBar?.percent, 78)
    }

    func testLocalModeHasNoRemoteBars() {
        let snapshot = UsageSnapshot()
        XCTAssertTrue(snapshot.remoteProgressBars.isEmpty)
        XCTAssertNil(snapshot.hottestRemoteBar)
    }

    func testConvertMapsPoolsCorrectly() {
        let formatter = ISO8601DateFormatter()
        let later = formatter.date(from: "2026-04-27T07:00:01Z")!

        let raw = RawUsageReport(
            fiveHour: .init(utilization: 25, resetsAt: later),
            sevenDay: .init(utilization: 10, resetsAt: later),
            sevenDayOauthApps: nil,
            sevenDayOpus: nil,
            sevenDaySonnet: .init(utilization: 2, resetsAt: later),
            sevenDayCowork: nil,
            sevenDayOmelette: .init(utilization: 73, resetsAt: later),
            iguanaNecktie: nil,
            omelettePromotional: nil,
            extraUsage: nil
        )
        let snapshot = ClaudeAIDataSource.convert(raw: raw)
        XCTAssertNotNil(snapshot.weekByModel["all"])
        XCTAssertNotNil(snapshot.weekByModel["sonnet"])
        XCTAssertNotNil(snapshot.weekByModel["design"])
        XCTAssertNil(snapshot.weekByModel["opus"])
    }
}
