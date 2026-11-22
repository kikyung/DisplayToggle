import Foundation

public enum SafetyGuard {
    public enum Decision: Equatable {
        case allowed
        case denied(reason: DenyReason)
    }

    /// G1, G5: 끄고 나면 켜진 모니터가 0개가 되면 거부한다.
    /// 켜진 모니터는 isActive 기준이므로 덮개를 닫은 내장 디스플레이는 세지 않는다.
    public static func canDisable(uuid: String, displays: [DisplayInfo]) -> Decision {
        guard let target = displays.first(where: { $0.uuid == uuid }) else {
            return .denied(reason: .displayNotFound)
        }
        guard target.isActive else {
            return .denied(reason: .alreadyOff)
        }
        guard target.canTurnOffSafely else {
            return .denied(reason: .unsafeToTurnOff)
        }
        let remaining = displays.filter { $0.isActive && $0.uuid != uuid }
        if remaining.isEmpty {
            return .denied(reason: .lastActiveDisplay)
        }
        return .allowed
    }

    /// G3: 켜진 모니터가 0개이면 앱이 꺼 둔 모니터를 모두 켜야 한다.
    public static func uuidsToRecover(displays: [DisplayInfo], offByApp: Set<String>) -> [String] {
        guard !displays.contains(where: { $0.isActive }) else { return [] }
        return offByApp.sorted()
    }
}
