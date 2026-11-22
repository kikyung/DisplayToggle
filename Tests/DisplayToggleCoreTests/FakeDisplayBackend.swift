import Foundation
@testable import DisplayToggleCore

final class FakeDisplayBackend: DisplayBackend {
    var displays: [DisplayInfo]
    var setEnabledCalls: [(uuid: String, enabled: Bool)] = []
    var applyCalls: [LayoutSnapshot] = []
    /// true이면 모니터 하나가 빠질 때 남은 모니터의 모드를 바꾼다. (문제 3 재현용)
    var driftOthersOnChange = false
    var failApply = false

    init(displays: [DisplayInfo]) { self.displays = displays }

    func connectedDisplays() -> [DisplayInfo] { displays }

    func setEnabled(uuid: String, enabled: Bool) throws {
        setEnabledCalls.append((uuid, enabled))
        guard let i = displays.firstIndex(where: { $0.uuid == uuid }) else {
            throw DisplayToggleError.backend("unknown display")
        }
        displays[i].isActive = enabled
        if driftOthersOnChange {
            for j in displays.indices where j != i && displays[j].isActive {
                if var p = displays[j].placement {
                    p.mode.width /= 2
                    p.mode.height /= 2
                    displays[j].placement = p
                }
            }
        }
    }

    func apply(layout: LayoutSnapshot) throws {
        applyCalls.append(layout)
        if failApply { throw DisplayToggleError.backend("apply failed") }
        for (uuid, p) in layout {
            if let i = displays.firstIndex(where: { $0.uuid == uuid }) { displays[i].placement = p }
        }
    }
}

enum Fixtures {
    static let modeLG = DisplayMode(width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 60)
    static let modeG70 = DisplayMode(width: 3008, height: 1692, pixelWidth: 6016, pixelHeight: 3384, refreshRate: 120)

    static func lg(active: Bool = true) -> DisplayInfo {
        DisplayInfo(uuid: "LG", name: "LG HDR 4K", isActive: active,
                    placement: DisplayPlacement(mode: modeLG, x: 0, y: 0))
    }
    static func g70(active: Bool = true) -> DisplayInfo {
        DisplayInfo(uuid: "G70", name: "Odyssey G70D", isActive: active,
                    placement: DisplayPlacement(mode: modeG70, x: -3008, y: -303))
    }
}
