import XCTest
@testable import DisplayToggleCore

final class SafetyGuardTests: XCTestCase {
    func testSingleActiveDisplayCannotBeDisabled() {
        let d = [Fixtures.lg()]
        XCTAssertEqual(SafetyGuard.canDisable(uuid: "LG", displays: d), .denied(reason: .lastActiveDisplay))
    }

    func testOneOfTwoCanBeDisabled() {
        XCTAssertEqual(SafetyGuard.canDisable(uuid: "G70", displays: [Fixtures.lg(), Fixtures.g70()]), .allowed)
    }

    func testOtherDisplayInactiveBlocksDisable() {
        // LG 신호가 없어 G70만 켜진 상태
        let d = [Fixtures.lg(active: false), Fixtures.g70()]
        XCTAssertEqual(SafetyGuard.canDisable(uuid: "G70", displays: d), .denied(reason: .lastActiveDisplay))
    }

    func testClosedLidBuiltinDoesNotCount() {
        let builtin = DisplayInfo(uuid: "BI", name: "Built-in", isActive: false, isBuiltin: true)
        XCTAssertEqual(SafetyGuard.canDisable(uuid: "LG", displays: [builtin, Fixtures.lg()]),
                       .denied(reason: .lastActiveDisplay))
    }

    func testOpenBuiltinCounts() {
        let builtin = DisplayInfo(uuid: "BI", name: "Built-in", isActive: true, isBuiltin: true)
        XCTAssertEqual(SafetyGuard.canDisable(uuid: "LG", displays: [builtin, Fixtures.lg()]), .allowed)
    }

    func testAlreadyOffIsDenied() {
        XCTAssertEqual(SafetyGuard.canDisable(uuid: "G70", displays: [Fixtures.lg(), Fixtures.g70(active: false)]),
                       .denied(reason: .alreadyOff))
    }

    func testRecoverWhenNothingActive() {
        let d = [Fixtures.lg(active: false), Fixtures.g70(active: false)]
        XCTAssertEqual(SafetyGuard.uuidsToRecover(displays: d, offByApp: ["G70"]), ["G70"])
    }

    func testNoRecoverWhenSomethingActive() {
        XCTAssertEqual(SafetyGuard.uuidsToRecover(displays: [Fixtures.lg(), Fixtures.g70(active: false)], offByApp: ["G70"]), [])
    }
}
