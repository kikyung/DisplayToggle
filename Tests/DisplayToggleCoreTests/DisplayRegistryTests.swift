import XCTest
@testable import DisplayToggleCore

final class DisplayRegistryTests: XCTestCase {
    func testSameUUIDTwiceYieldsOneEntry() {
        let reg = DisplayRegistry(fileURL: nil)
        let dup = [Fixtures.g70(), Fixtures.g70(active: false)]
        reg.observe(dup)
        XCTAssertEqual(reg.entries(connected: dup).filter { $0.uuid == "G70" }.count, 1)
    }

    func testDisabledDisplayStaysListedEvenWhenNotConnected() {
        let reg = DisplayRegistry(fileURL: nil)
        reg.observe([Fixtures.lg(), Fixtures.g70()])
        reg.markOff("G70")
        let entries = reg.entries(connected: [Fixtures.lg()])
        XCTAssertEqual(entries.map(\.uuid), ["LG", "G70"])
        XCTAssertEqual(entries.last?.isActive, false)
    }

    func testConnectedInactiveAndOffByAppMergeIntoOne() {
        let reg = DisplayRegistry(fileURL: nil)
        reg.observe([Fixtures.lg(), Fixtures.g70()])
        reg.markOff("G70")
        let entries = reg.entries(connected: [Fixtures.lg(), Fixtures.g70(active: false)])
        XCTAssertEqual(entries.count, 2)
    }

    func testNamelessTransientEntryIsHidden() {
        let reg = DisplayRegistry(fileURL: nil)
        let ghost = DisplayInfo(uuid: "GHOST", name: nil, isActive: false)
        XCTAssertTrue(reg.entries(connected: [Fixtures.lg(), ghost]).allSatisfy { $0.uuid != "GHOST" })
    }

    func testNameComesFromRecordWhenBackendHasNone() {
        let reg = DisplayRegistry(fileURL: nil)
        reg.observe([Fixtures.g70()])
        let nameless = DisplayInfo(uuid: "G70", name: nil, isActive: false)
        XCTAssertEqual(reg.entries(connected: [nameless]).first?.name, "Odyssey G70D")
    }

    func testPersistsAcrossInstances() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dt-\(UUID().uuidString)/displays.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let a = DisplayRegistry(fileURL: url)
        a.observe([Fixtures.lg(), Fixtures.g70()])
        a.markOff("G70")
        let b = DisplayRegistry(fileURL: url)
        XCTAssertEqual(b.offByApp, ["G70"])
        XCTAssertEqual(b.lastPlacement(for: "G70"), Fixtures.g70().placement)
    }

    func testInactiveObservationKeepsLastPlacement() {
        let reg = DisplayRegistry(fileURL: nil)
        reg.observe([Fixtures.g70()])
        var off = Fixtures.g70(active: false)
        off.placement = nil
        reg.observe([off])
        XCTAssertEqual(reg.lastPlacement(for: "G70"), Fixtures.g70().placement)
    }
}
