import XCTest
@testable import DisplayToggleCore

final class DisplayControllerTests: XCTestCase {
    private func make(_ displays: [DisplayInfo]) -> (FakeDisplayBackend, DisplayController) {
        let backend = FakeDisplayBackend(displays: displays)
        return (backend, DisplayController(backend: backend, registry: DisplayRegistry(fileURL: nil)))
    }

    func testDisableOneOfTwoKeepsItListed() throws {
        let (backend, c) = make([Fixtures.lg(), Fixtures.g70()])
        XCTAssertEqual(try c.disable(uuid: "G70"), .done)
        XCTAssertEqual(backend.displays.first { $0.uuid == "G70" }?.isActive, false)
        let entries = c.entries()
        XCTAssertEqual(entries.map(\.uuid), ["LG", "G70"])
        XCTAssertEqual(entries.last?.isActive, false)
    }

    func testDisableLastDisplayIsRejectedAndBackendUntouched() {
        let (backend, c) = make([Fixtures.lg(), Fixtures.g70(active: false)])
        XCTAssertThrowsError(try c.disable(uuid: "LG")) {
            XCTAssertEqual($0 as? DisplayToggleError, .blocked("마지막 화면은 끌 수 없음"))
        }
        XCTAssertTrue(backend.setEnabledCalls.isEmpty)
    }

    func testMenuDecisionCanBecomeStaleButExecutionRechecks() throws {
        let (backend, c) = make([Fixtures.lg(), Fixtures.g70()])
        XCTAssertEqual(c.disableDecision(uuid: "G70"), .allowed)
        backend.displays[0].isActive = false  // 메뉴를 연 뒤 LG 신호가 사라짐
        XCTAssertThrowsError(try c.disable(uuid: "G70"))
        XCTAssertTrue(backend.setEnabledCalls.isEmpty)
    }

    func testOtherDisplayLayoutIsRestoredAfterDisable() throws {
        let (backend, c) = make([Fixtures.lg(), Fixtures.g70()])
        backend.driftOthersOnChange = true
        XCTAssertEqual(try c.disable(uuid: "G70"), .done)
        XCTAssertEqual(backend.displays.first { $0.uuid == "LG" }?.placement, Fixtures.lg().placement)
        XCTAssertEqual(backend.applyCalls.count, 1)
    }

    func testNoApplyWhenNothingDrifted() throws {
        let (backend, c) = make([Fixtures.lg(), Fixtures.g70()])
        _ = try c.disable(uuid: "G70")
        XCTAssertTrue(backend.applyCalls.isEmpty)
    }

    func testRestoreFailureYieldsWarning() throws {
        let (backend, c) = make([Fixtures.lg(), Fixtures.g70()])
        backend.driftOthersOnChange = true
        backend.failApply = true
        guard case .doneWithWarning = try c.disable(uuid: "G70") else { return XCTFail("경고 기대") }
    }

    func testEnableRestoresLastMode() throws {
        let (backend, c) = make([Fixtures.lg(), Fixtures.g70()])
        _ = try c.disable(uuid: "G70")
        // 켜질 때 macOS가 다른 모드를 고른 상황
        backend.displays[1].placement = DisplayPlacement(mode: Fixtures.modeLG, x: 100, y: 100)
        backend.driftOthersOnChange = false
        // setEnabled 뒤 placement가 어긋난 채 유지되도록 그대로 둔다
        XCTAssertEqual(try c.enable(uuid: "G70"), .done)
        XCTAssertEqual(backend.displays[1].placement, Fixtures.g70().placement)
        XCTAssertTrue(c.registry.offByApp.isEmpty)
    }

    func testRecoverWhenAllDisplaysGoInactive() throws {
        let (backend, c) = make([Fixtures.lg(), Fixtures.g70()])
        _ = try c.disable(uuid: "G70")
        backend.displays[0].isActive = false  // LG 입력 전환
        XCTAssertEqual(c.recoverIfNeeded(), ["G70"])
        XCTAssertEqual(backend.displays[1].isActive, true)
        XCTAssertTrue(c.registry.offByApp.isEmpty)
    }

    func testNoRecoveryWhenSomethingIsActive() throws {
        let (backend, c) = make([Fixtures.lg(), Fixtures.g70()])
        _ = try c.disable(uuid: "G70")
        XCTAssertEqual(c.recoverIfNeeded(), [])
        XCTAssertEqual(backend.displays[1].isActive, false)
    }

    func testRecoverAtLaunchEnablesPreviouslyDisabled() throws {
        let backend = FakeDisplayBackend(displays: [Fixtures.lg(), Fixtures.g70(active: false)])
        let reg = DisplayRegistry(fileURL: nil)
        reg.markOff("G70")
        let c = DisplayController(backend: backend, registry: reg)
        c.recoverAtLaunch()
        XCTAssertEqual(backend.displays[1].isActive, true)
        XCTAssertTrue(reg.offByApp.isEmpty)
    }

    func testEnableAllEnablesEveryOffDisplay() throws {
        let (backend, c) = make([Fixtures.lg(), Fixtures.g70()])
        _ = try c.disable(uuid: "G70")
        XCTAssertEqual(c.enableAll(), [])
        XCTAssertTrue(backend.displays.allSatisfy { $0.isActive })
    }
}
