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

    func testDisplayWithoutSafeRecoveryCannotBeDisabled() {
        var lg = Fixtures.lg()
        lg.canTurnOffSafely = false
        let (backend, c) = make([lg, Fixtures.g70()])

        XCTAssertEqual(c.disableDecision(uuid: "LG"), .denied(reason: .unsafeToTurnOff))
        XCTAssertThrowsError(try c.disable(uuid: "LG")) {
            XCTAssertEqual($0 as? DisplayToggleError, .blocked(.unsafeToTurnOff))
        }
        XCTAssertTrue(backend.setEnabledCalls.isEmpty)
        XCTAssertTrue(c.registry.offByApp.isEmpty)
    }

    func testMissingDisplayUsesRememberedIDOnlyForRecovery() {
        XCTAssertEqual(CoreGraphicsBackend.resolveDisplayID(
            enabled: true, onlineMatch: nil, onlineIDs: [1], rememberedID: 2
        ), 2)
        XCTAssertNil(CoreGraphicsBackend.resolveDisplayID(
            enabled: false, onlineMatch: nil, onlineIDs: [1], rememberedID: 2
        ))
        XCTAssertNil(CoreGraphicsBackend.resolveDisplayID(
            enabled: true, onlineMatch: nil, onlineIDs: [1, 2], rememberedID: 2
        ))
        XCTAssertEqual(CoreGraphicsBackend.resolveDisplayID(
            enabled: true, onlineMatch: 3, onlineIDs: [1, 3], rememberedID: 2
        ), 3)
    }

    func testDisableLastDisplayIsRejectedAndBackendUntouched() {
        let (backend, c) = make([Fixtures.lg(), Fixtures.g70(active: false)])
        XCTAssertThrowsError(try c.disable(uuid: "LG")) {
            XCTAssertEqual($0 as? DisplayToggleError, .blocked(.lastActiveDisplay))
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

    func testRemainingDisplayRestoresModeAtSingleDisplayOrigin() throws {
        let (backend, c) = make([Fixtures.lg(), Fixtures.g70()])
        backend.driftOthersOnChange = true

        XCTAssertEqual(try c.disable(uuid: "LG"), .done)
        XCTAssertEqual(backend.applyCalls.first?["G70"], DisplayPlacement(mode: Fixtures.modeG70, x: 0, y: 0))
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
        guard case .doneWithWarning = try c.disable(uuid: "G70") else { return XCTFail("expected a warning") }
    }

    func testEnableAllRestoresArrangementAfterRemainingDisplayBecomesOrigin() throws {
        let (backend, c) = make([Fixtures.lg(), Fixtures.g70()])
        _ = try c.disable(uuid: "LG")
        backend.displays[1].placement = DisplayPlacement(mode: Fixtures.modeG70, x: 0, y: 0)
        _ = c.entries() // Opening the menu observes the temporary single-display layout.
        backend.displays[0].placement = DisplayPlacement(mode: Fixtures.modeLG, x: -2560, y: 0)

        XCTAssertEqual(c.enableAll(), [])
        XCTAssertEqual(backend.displays[0].placement, Fixtures.lg().placement)
        XCTAssertEqual(backend.displays[1].placement, Fixtures.g70().placement)
    }

    func testThreeDisplaysKeepRelativePlacementWhenPrimaryIsDisabled() throws {
        let displays = multiDisplayFixtures(includeFourth: false)
        let (backend, c) = make(displays)
        backend.rebaseDisplaysOnChange = true

        XCTAssertEqual(try c.disable(uuid: "LG"), .done)
        XCTAssertEqual(backend.displays[2].placement?.x, 5568)
        XCTAssertEqual(backend.displays[2].placement?.y, 803)
        XCTAssertEqual(c.enableAll(), [])
        XCTAssertEqual(backend.displays, displays)
    }

    func testFourDisplaysRecoverAfterRelaunchAndRetryMissingDisplay() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("displays.json")
        let displays = multiDisplayFixtures(includeFourth: true)
        let backend = FakeDisplayBackend(displays: displays)
        backend.rebaseDisplaysOnChange = true
        let c = DisplayController(backend: backend, registry: DisplayRegistry(fileURL: url))

        _ = try c.disable(uuid: "LG")
        _ = try c.disable(uuid: "G70")
        _ = try c.disable(uuid: "Right")
        XCTAssertThrowsError(try c.disable(uuid: "Above"))
        _ = c.entries()
        let missing = backend.displays.remove(at: 1)
        let relaunched = DisplayController(backend: backend, registry: DisplayRegistry(fileURL: url))
        relaunched.recoverAtLaunch()

        XCTAssertEqual(relaunched.registry.offByApp, ["G70"])
        backend.displays.insert(missing, at: 1)
        XCTAssertEqual(relaunched.enableAll(), [])
        XCTAssertEqual(backend.displays, displays)
        XCTAssertTrue(relaunched.registry.layoutBeforeDisable.isEmpty)
    }

    private func multiDisplayFixtures(includeFourth: Bool) -> [DisplayInfo] {
        let right = DisplayInfo(uuid: "Right", name: "Right", isActive: true,
                                placement: DisplayPlacement(mode: Fixtures.modeLG, x: 2560, y: 500))
        let above = DisplayInfo(uuid: "Above", name: "Above", isActive: true,
                                placement: DisplayPlacement(mode: Fixtures.modeLG, x: 200, y: -1440))
        let displays = [Fixtures.lg(), Fixtures.g70(), right]
        return includeFourth ? displays + [above] : displays
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

    func testFailedAutomaticRecoveryRemainsEligibleForRetry() {
        let (backend, c) = make([])
        c.registry.markOff("G70")

        XCTAssertEqual(c.recoverIfNeeded(), [])
        XCTAssertEqual(c.registry.offByApp, ["G70"])

        backend.displays = [Fixtures.g70(active: false)]
        XCTAssertEqual(c.recoverIfNeeded(), ["G70"])
        XCTAssertEqual(backend.displays.first?.isActive, true)
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

    func testLaunchRecoveryKeepsOnlyFailedDisplaysForEnableAll() {
        let (backend, c) = make([Fixtures.lg(active: false)])
        c.registry.markOff("LG")
        c.registry.markOff("G70")

        c.recoverAtLaunch()

        XCTAssertEqual(backend.displays.first?.isActive, true)
        XCTAssertEqual(c.registry.offByApp, ["G70"])

        backend.displays.append(Fixtures.g70(active: false))
        XCTAssertEqual(c.enableAll(), [])
        XCTAssertEqual(backend.displays.last?.isActive, true)
        XCTAssertTrue(c.registry.offByApp.isEmpty)
    }

    func testEnableAllEnablesEveryOffDisplay() throws {
        let (backend, c) = make([Fixtures.lg(), Fixtures.g70()])
        _ = try c.disable(uuid: "G70")
        XCTAssertEqual(c.enableAll(), [])
        XCTAssertTrue(backend.displays.allSatisfy { $0.isActive })
    }
}
