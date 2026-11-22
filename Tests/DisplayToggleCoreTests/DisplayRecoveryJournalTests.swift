import Foundation
import XCTest
@testable import DisplayToggleCore

final class DisplayRecoveryJournalTests: XCTestCase {
    func testRecoveryIDsSurviveRelaunchOnlyWithinSameSession() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("recovery.json")
        let session = UUID()
        try DisplayRecoveryJournal(url: url, sessionID: session).save(["LG": 2])

        let relaunched = DisplayRecoveryJournal(url: url, sessionID: session)
        XCTAssertEqual(relaunched.load(), ["LG": 2])
        XCTAssertTrue(DisplayRecoveryJournal(url: url, sessionID: UUID()).load().isEmpty)

        try relaunched.save([:])
        XCTAssertTrue(relaunched.load().isEmpty)
    }
}
