import Foundation

public enum ToggleOutcome: Equatable {
    case done
    /// 동작은 성공했지만 다른 모니터의 해상도·배치를 복원하지 못했다.
    case doneWithWarning(ToggleWarning)
}

public final class DisplayController {
    private let backend: DisplayBackend
    public let registry: DisplayRegistry

    public init(backend: DisplayBackend, registry: DisplayRegistry) {
        self.backend = backend
        self.registry = registry
    }

    public func entries() -> [DisplayEntry] {
        let connected = backend.connectedDisplays()
        registry.observe(connected)
        return registry.entries(connected: connected)
    }

    /// 메뉴 표시용. 끌 수 없으면 이유를 돌려준다. (G2의 첫 번째 검사)
    public func disableDecision(uuid: String) -> SafetyGuard.Decision {
        SafetyGuard.canDisable(uuid: uuid, displays: backend.connectedDisplays())
    }

    public func disable(uuid: String) throws -> ToggleOutcome {
        let before = backend.connectedDisplays()
        registry.observe(before)
        // G2: 실행 직전에 한 번 더 검사한다.
        if case .denied(let reason) = SafetyGuard.canDisable(uuid: uuid, displays: before) {
            throw DisplayToggleError.blocked(reason)
        }
        let snapshot = Self.snapshot(of: before, excluding: uuid)
        try backend.setEnabled(uuid: uuid, enabled: false)
        registry.markOff(uuid)
        return restoreIfChanged(expected: snapshot)
    }

    public func enable(uuid: String) throws -> ToggleOutcome {
        let before = backend.connectedDisplays()
        registry.observe(before)
        var snapshot = Self.snapshot(of: before, excluding: uuid)
        try backend.setEnabled(uuid: uuid, enabled: true)
        registry.markOn(uuid)
        // 켜진 모니터는 기록에 저장된 마지막 모드를 우선 적용한다.
        if let last = registry.lastPlacement(for: uuid) { snapshot[uuid] = last }
        return restoreIfChanged(expected: snapshot)
    }

    public func enableAll() -> [String] {
        var failed: [String] = []
        for uuid in registry.offByApp {
            do { _ = try enable(uuid: uuid) } catch { failed.append(uuid) }
        }
        return failed
    }

    /// G3: 구성 변경 콜백에서 호출한다. 켜진 모니터가 0개이면 꺼 둔 모니터를 모두 켠다.
    @discardableResult
    public func recoverIfNeeded() -> [String] {
        let displays = backend.connectedDisplays()
        let targets = SafetyGuard.uuidsToRecover(displays: displays, offByApp: registry.offByApp)
        for uuid in targets {
            try? backend.setEnabled(uuid: uuid, enabled: true)
            registry.markOn(uuid)
        }
        return targets
    }

    /// G4: 시작할 때 이전 세션에서 꺼 둔 모니터를 모두 켠다.
    public func recoverAtLaunch() {
        for uuid in registry.offByApp {
            try? backend.setEnabled(uuid: uuid, enabled: true)
        }
        registry.clearOffMarks()
    }

    // MARK: - 스냅샷과 복원

    static func snapshot(of displays: [DisplayInfo], excluding uuid: String? = nil) -> LayoutSnapshot {
        var snap: LayoutSnapshot = [:]
        for d in displays where d.isActive && d.uuid != uuid {
            if let p = d.placement { snap[d.uuid] = p }
        }
        return snap
    }

    private func restoreIfChanged(expected: LayoutSnapshot) -> ToggleOutcome {
        let after = Self.snapshot(of: backend.connectedDisplays())
        let drifted = expected.filter { after[$0.key] != $0.value }
        if drifted.isEmpty { return .done }
        do {
            try backend.apply(layout: drifted)
        } catch {
            return .doneWithWarning(.layoutNotRestored)
        }
        let verify = Self.snapshot(of: backend.connectedDisplays())
        if drifted.contains(where: { verify[$0.key] != $0.value }) {
            return .doneWithWarning(.layoutNotRestored)
        }
        return .done
    }
}
