import XCTest
@testable import ClaudeTokenManagerCore

final class NotificationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        NotificationManager.shared.clearAllFiredAlerts()
    }

    override func tearDown() {
        NotificationManager.shared.clearAllFiredAlerts()
        super.tearDown()
    }

    func testProgressBarNotificationFiresOnceAt80() {
        let windowEnd = Date().addingTimeInterval(3600)
        let bar = RemoteProgressBar(
            id: "test-design",
            label: "Test Design",
            percent: 82,
            resetsAt: windowEnd
        )

        NotificationManager.shared.evaluateProgressBar(bar)
        XCTAssertTrue(
            NotificationManager.shared.hasFired(barId: "test-design", threshold: .warning, windowEnd: windowEnd)
        )

        // Re-evaluate — should not double-fire (dedup)
        NotificationManager.shared.evaluateProgressBar(bar)
        // Still true (already fired), but no crash or double-send
        XCTAssertTrue(
            NotificationManager.shared.hasFired(barId: "test-design", threshold: .warning, windowEnd: windowEnd)
        )
    }

    func testProgressBarAt96FiresBothThresholds() {
        let windowEnd = Date().addingTimeInterval(3600)
        let bar = RemoteProgressBar(
            id: "test-session",
            label: "Test Session",
            percent: 96,
            resetsAt: windowEnd
        )

        NotificationManager.shared.evaluateProgressBar(bar)
        XCTAssertTrue(
            NotificationManager.shared.hasFired(barId: "test-session", threshold: .warning, windowEnd: windowEnd)
        )
        XCTAssertTrue(
            NotificationManager.shared.hasFired(barId: "test-session", threshold: .critical, windowEnd: windowEnd)
        )
    }

    func testProgressBarBelow80DoesNotFire() {
        let windowEnd = Date().addingTimeInterval(3600)
        let bar = RemoteProgressBar(
            id: "test-low",
            label: "Test Low",
            percent: 50,
            resetsAt: windowEnd
        )

        NotificationManager.shared.evaluateProgressBar(bar)
        XCTAssertFalse(
            NotificationManager.shared.hasFired(barId: "test-low", threshold: .warning, windowEnd: windowEnd)
        )
    }
}
