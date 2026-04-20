import XCTest
import CryptoKit
@testable import ClaudeTokenManagerCore

final class ClaudeAPIClientTests: XCTestCase {

    /// Validates that the ASN.1 SPKI extractor produces the correct hash
    /// for a real claude.ai certificate (leaf, Let's Encrypt E8 chain).
    /// DER captured 2026-04-20.
    func testSPKIExtractionMatchesKnownHash() throws {
        // claude.ai leaf certificate DER (base64)
        let certBase64 = "MIIDlzCCAx2gAwIBAgISBu2ohLSLc/ZQgWdfCBWxZTsvMAoGCCqGSM49BAMDMDIxCzAJBgNVBAYTAlVTMRYwFAYDVQQKEw1MZXQncyBFbmNyeXB0MQswCQYDVQQDEwJFODAeFw0yNjAzMTcxNjI2NDlaFw0yNjA2MTUxNjI2NDhaMBQxEjAQBgNVBAMTCWNsYXVkZS5haTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABFzFOf2q0RDFZcaORX4YZr2wmM15q7w5JXC/yNzsvLl/8jwwxnMKqr9nBbU2ayFDdOHdqbBu0hLIg6U8DYJzJX6jggIvMIICKzAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYBBQUHAwEwDAYDVR0TAQH/BAIwADAdBgNVHQ4EFgQUqvMwKq8fByWFsfqd3QWoaVKYFcEwHwYDVR0jBBgwFoAUjw0TovYuftFQbDMYOF1ZjiNykcowMgYIKwYBBQUHAQEEJjAkMCIGCCsGAQUFBzAChhZodHRwOi8vZTguaS5sZW5jci5vcmcvMDYGA1UdEQQvMC2CCWNsYXVkZS5haYIRc3RhZ2luZy5jbGF1ZGUuYWmCDXd3dy5jbGF1ZGUuYWkwEwYDVR0gBAwwCjAIBgZngQwBAgEwLQYDVR0fBCYwJDAioCCgHoYcaHR0cDovL2U4LmMubGVuY3Iub3JnLzQ4LmNybDCCAQQGCisGAQQB1nkCBAIEgfUEgfIA8AB2AA5XlLzzrqk+MxssmQez95Dfm8I9cTIl3SGpJaxhxU4hAAABnPzUoVUAAAQDAEcwRQIhAP2m0ngGWSUq6weFBe6lMHa3mkFzw9SfQy+XaV5PoGDNAiA2wGCYlN8yVnfDjCogC/D/9fKO8q0y+QTSUiNylGRG0AB2AEmcm2neHXzs/DbezYdkprhbrwqHgBnRVVL76esp3fjDAAABnPzUqSYAAAQDAEcwRQIgflIjgdRHvBw2RItANOdxX/fYNxTke6SZI0/J5XRHGigCIQC7euQuwdZT0SddyJKYjDfxKBUDyxGQPbiAQt3pSVAD+zAKBggqhkjOPQQDAwNoADBlAjEA+o1biz87AnZJIJkL141saLhk4mzKUYL6iN8Y+N1HXmlCTSRiV5ixhEYJIA2I0DQ8AjBhdX82DMskXtG5l9rNEpUTswMWDn57k2wmRdNVlrX4KbTRV+DYXcENtwUhgZPra48="

        guard let certData = Data(base64Encoded: certBase64) else {
            XCTFail("Failed to decode test certificate base64")
            return
        }

        guard let spki = SPKIExtractor.extractSPKI(from: certData) else {
            XCTFail("SPKI extraction returned nil")
            return
        }

        let hash = SHA256.hash(data: spki)
        let hashBase64 = Data(hash).base64EncodedString()

        XCTAssertEqual(
            hashBase64,
            "6bbYmCUydTiUdHfXo26WKlDxCgYO032WlolDxthhXoM=",
            "SPKI hash must match known claude.ai leaf hash"
        )
    }

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
