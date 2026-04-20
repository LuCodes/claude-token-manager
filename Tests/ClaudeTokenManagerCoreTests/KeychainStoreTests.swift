import XCTest
@testable import ClaudeTokenManagerCore

final class KeychainStoreTests: XCTestCase {
    let testKey = "test.keychain.dummy.token"

    override func tearDown() {
        try? KeychainStore.delete(testKey)
        super.tearDown()
    }

    func testStoreAndRetrieve() throws {
        try KeychainStore.set("my-secret-value", for: testKey)
        let retrieved = try KeychainStore.get(testKey)
        XCTAssertEqual(retrieved, "my-secret-value")
    }

    func testRetrieveMissingReturnsNil() throws {
        let value = try KeychainStore.get("definitely-does-not-exist-\(UUID())")
        XCTAssertNil(value)
    }

    func testOverwrite() throws {
        try KeychainStore.set("first", for: testKey)
        try KeychainStore.set("second", for: testKey)
        XCTAssertEqual(try KeychainStore.get(testKey), "second")
    }

    func testDelete() throws {
        try KeychainStore.set("to-delete", for: testKey)
        try KeychainStore.delete(testKey)
        XCTAssertNil(try KeychainStore.get(testKey))
    }
}
