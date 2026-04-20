import XCTest
@testable import ClaudeTokenManagerCore

final class ClaudeAPIClientTests: XCTestCase {

    func testSessionKeyIsRedactedInDescription() {
        let key = SessionKey("sk-ant-sid01-supersecret-value-do-not-log")
        XCTAssertEqual(String(describing: key), "SessionKey(REDACTED)")
        XCTAssertEqual(String(reflecting: key), "SessionKey(REDACTED)")
        let formatted = "\(key)"
        XCTAssertFalse(formatted.contains("supersecret"))
    }

    func testSessionKeyPrefixIsSafe() {
        let key = SessionKey("sk-ant-sid01-verysecret")
        XCTAssertEqual(key.prefix6, "sk-ant\u{2026}")
    }

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
