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
        let snapshot = Self.snapshot(of: before)
        try backend.setEnabled(uuid: uuid, enabled: false)
        registry.markOff(uuid, layoutBeforeDisable: snapshot)
        return restoreIfChanged(expected: snapshot.filter { $0.key != uuid })
    }

    public func enable(uuid: String) throws -> ToggleOutcome {
        let before = backend.connectedDisplays()
        registry.observe(before)
        var snapshot = Self.snapshot(of: before, excluding: uuid)
        // Keep current modes on the other displays, but recover their pre-disable origins.
        let original = registry.layoutBeforeDisable
        for (id, placement) in snapshot {
            if let saved = original[id] {
                snapshot[id] = DisplayPlacement(mode: placement.mode, x: saved.x, y: saved.y)
            }
        }
        if let last = original[uuid] ?? registry.lastPlacement(for: uuid) { snapshot[uuid] = last }
        try backend.setEnabled(uuid: uuid, enabled: true)
        let outcome = restoreIfChanged(expected: snapshot)
        registry.markOn(uuid)
        return outcome
    }

    public func enableAll() -> [String] {
        var failed: [String] = []
        for uuid in registry.offByApp.sorted() {
            do { _ = try enable(uuid: uuid) } catch { failed.append(uuid) }
        }
        return failed
    }

    /// G3: 구성 변경 콜백에서 호출한다. 켜진 모니터가 0개이면 꺼 둔 모니터를 모두 켠다.
    @discardableResult
    public func recoverIfNeeded() -> [String] {
        let displays = backend.connectedDisplays()
        let targets = SafetyGuard.uuidsToRecover(displays: displays, offByApp: registry.offByApp)
        return recover(targets)
    }

    /// G4: 시작할 때 이전 세션에서 꺼 둔 모니터를 다시 켜고, 실패한 항목은 재시도할 수 있게 남긴다.
    public func recoverAtLaunch() {
        recover(registry.offByApp.sorted())
    }

    @discardableResult
    private func recover(_ targets: [String]) -> [String] {
        var recovered: [String] = []
        for uuid in targets {
            do {
                _ = try enable(uuid: uuid)
                recovered.append(uuid)
            } catch {
                // 연결 상태가 바뀌면 다시 시도할 수 있도록 기록을 유지한다.
                continue
            }
        }
        return recovered
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
        let expected = Self.rebase(expected: expected, onto: after)
        let drifted = expected.filter { uuid, placement in
            !Self.matches(placement, actual: after[uuid], compareOrigin: after.count != 1)
        }.mapValues { placement in
            // A lone display defines the coordinate origin.
            after.count == 1 ? DisplayPlacement(mode: placement.mode, x: 0, y: 0) : placement
        }
        if drifted.isEmpty { return .done }
        let originsChanged = after.count > 1 && drifted.contains { uuid, placement in
            guard let actual = after[uuid] else { return false }
            return placement.x != actual.x || placement.y != actual.y
        }
        // CoreGraphics computes the arrangement as a whole, including the display at (0, 0).
        let layout = originsChanged ? expected : drifted
        do {
            try backend.apply(layout: layout)
        } catch {
            return .doneWithWarning(.layoutNotRestored)
        }
        let verify = Self.snapshot(of: backend.connectedDisplays())
        if layout.contains(where: { !Self.matches($0.value, actual: verify[$0.key], compareOrigin: verify.count != 1) }) {
            return .doneWithWarning(.layoutNotRestored)
        }
        return .done
    }

    private static func rebase(expected: LayoutSnapshot, onto actual: LayoutSnapshot) -> LayoutSnapshot {
        // If the original primary display is absent, retain relative placement around the
        // current primary. When the original primary returns, use the original origins.
        guard !expected.values.contains(where: { $0.x == 0 && $0.y == 0 }),
              let currentPrimary = actual.first(where: { $0.value.x == 0 && $0.value.y == 0 }),
              let anchor = expected[currentPrimary.key] else { return expected }
        return expected.mapValues {
            DisplayPlacement(mode: $0.mode, x: $0.x - anchor.x, y: $0.y - anchor.y)
        }
    }

    private static func matches(_ expected: DisplayPlacement, actual: DisplayPlacement?, compareOrigin: Bool) -> Bool {
        guard let actual else { return false }
        return compareOrigin ? actual == expected : actual.mode == expected.mode
    }
}
