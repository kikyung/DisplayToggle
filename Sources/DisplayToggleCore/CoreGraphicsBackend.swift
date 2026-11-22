import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// CoreGraphics와 비공개 함수 CGSConfigureDisplayEnabled를 쓰는 실제 백엔드.
public final class CoreGraphicsBackend: DisplayBackend {
    private typealias ConfigureEnabledFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

    private let configureEnabled: ConfigureEnabledFn?
    private let recoveryJournal: DisplayRecoveryJournal?
    private let requiresRecoveryJournal: Bool
    private var disabledDisplayIDs: [String: CGDirectDisplayID]

    public var pendingRecoveryUUIDs: Set<String> { Set(disabledDisplayIDs.keys) }

    /// 심볼을 찾지 못하면 nil이 아니라 isToggleAvailable == false 상태로 만든다.
    public init(recoveryURL: URL? = nil) {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let sessionID = (session?["CGSSessionUniqueSessionUUID"] as? String).flatMap(UUID.init(uuidString:))
        let journal = recoveryURL.flatMap { url in
            sessionID.map { DisplayRecoveryJournal(url: url, sessionID: $0) }
        }
        recoveryJournal = journal
        requiresRecoveryJournal = recoveryURL != nil
        disabledDisplayIDs = journal?.load() ?? [:]

        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        if let sym = dlsym(rtldDefault, "CGSConfigureDisplayEnabled") {
            configureEnabled = unsafeBitCast(sym, to: ConfigureEnabledFn.self)
        } else {
            configureEnabled = nil
        }
    }

    public var isToggleAvailable: Bool { configureEnabled != nil }

    // MARK: - DisplayBackend

    public func connectedDisplays() -> [DisplayInfo] {
        let names = Self.screenNames()
        return (Self.onlineIDs() ?? []).compactMap { id in
            guard let uuid = Self.uuid(of: id) else { return nil }
            let active = CGDisplayIsActive(id) != 0
            return DisplayInfo(
                uuid: uuid,
                name: names[id],
                isActive: active,
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                placement: active ? Self.placement(of: id) : nil,
                canTurnOffSafely: canTurnOffSafely
            )
        }
    }

    public func setEnabled(uuid: String, enabled: Bool) throws {
        guard let fn = configureEnabled else {
            throw DisplayToggleError.backend("CGSConfigureDisplayEnabled is not available on this macOS")
        }
        guard let onlineIDs = Self.onlineIDs() else {
            throw DisplayToggleError.backend("CGGetOnlineDisplayList failed")
        }
        let onlineMatch = onlineIDs.first { Self.uuid(of: $0) == uuid }
        let rememberedID = disabledDisplayIDs[uuid].flatMap { id in
            let reportedUUID = Self.uuid(of: id)
            return reportedUUID == nil || reportedUUID == uuid ? id : nil
        }
        guard let id = Self.resolveDisplayID(
            enabled: enabled, onlineMatch: onlineMatch, onlineIDs: onlineIDs, rememberedID: rememberedID
        ) else {
            throw DisplayToggleError.blocked(.displayNotFound)
        }
        if !enabled && !canTurnOffSafely {
            throw DisplayToggleError.blocked(.unsafeToTurnOff)
        }
        if enabled && onlineMatch != nil && CGDisplayIsActive(id) != 0 {
            forgetRecoveryID(for: uuid)
            return
        }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else {
            throw DisplayToggleError.backend("CGBeginDisplayConfiguration failed")
        }
        let r = fn(config, id, enabled)
        guard r == .success else {
            CGCancelDisplayConfiguration(config)
            throw DisplayToggleError.backend("CGSConfigureDisplayEnabled failed (\(r.rawValue))")
        }
        if !enabled {
            var updated = disabledDisplayIDs.filter { $0.value != id }
            updated[uuid] = id
            // Save before committing the change so the next app run can recover after a crash.
            do {
                try recoveryJournal?.save(updated)
            } catch {
                CGCancelDisplayConfiguration(config)
                throw error
            }
            disabledDisplayIDs = updated
        }
        let c = CGCompleteDisplayConfiguration(config, .forSession)
        guard c == .success else {
            throw DisplayToggleError.backend("CGCompleteDisplayConfiguration failed (\(c.rawValue))")
        }
        if enabled {
            if onlineMatch == nil {
                guard connectedDisplays().contains(where: { $0.uuid == uuid && $0.isActive }) else {
                    throw DisplayToggleError.backend("The display did not return after the enable request")
                }
            }
            forgetRecoveryID(for: uuid)
        }
    }

    public func apply(layout: LayoutSnapshot) throws {
        guard let onlineIDs = Self.onlineIDs() else {
            throw DisplayToggleError.backend("CGGetOnlineDisplayList failed")
        }
        let ids = Dictionary(uniqueKeysWithValues: onlineIDs.compactMap { id in
            Self.uuid(of: id).map { ($0, id) }
        })
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else {
            throw DisplayToggleError.backend("CGBeginDisplayConfiguration failed")
        }
        for (uuid, placement) in layout {
            guard let id = ids[uuid] else { continue }
            if let mode = Self.findMode(placement.mode, for: id) {
                CGConfigureDisplayWithDisplayMode(config, id, mode, nil)
            }
            CGConfigureDisplayOrigin(config, id, Int32(placement.x), Int32(placement.y))
        }
        let c = CGCompleteDisplayConfiguration(config, .forSession)
        guard c == .success else {
            throw DisplayToggleError.backend("CGCompleteDisplayConfiguration failed (\(c.rawValue))")
        }
    }

    // MARK: - 헬퍼

    private func forgetRecoveryID(for uuid: String) {
        if disabledDisplayIDs.removeValue(forKey: uuid) != nil {
            try? recoveryJournal?.save(disabledDisplayIDs)
        }
    }

    private var canTurnOffSafely: Bool {
        !requiresRecoveryJournal || recoveryJournal != nil
    }

    static func resolveDisplayID(
        enabled: Bool,
        onlineMatch: CGDirectDisplayID?,
        onlineIDs: [CGDirectDisplayID],
        rememberedID: CGDirectDisplayID?
    ) -> CGDirectDisplayID? {
        if let onlineMatch { return onlineMatch }
        guard enabled, let rememberedID, !onlineIDs.contains(rememberedID) else { return nil }
        return rememberedID
    }

    private static func onlineIDs() -> [CGDirectDisplayID]? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard count > 0 else { return [] }
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return nil }
        return Array(ids.prefix(Int(count)))
    }

    private static func uuid(of id: CGDirectDisplayID) -> String? {
        guard let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
              let s = CFUUIDCreateString(nil, u) else { return nil }
        return s as String
    }

    private static func screenNames() -> [CGDirectDisplayID: String] {
        var result: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                result[CGDirectDisplayID(num.uint32Value)] = screen.localizedName
            }
        }
        return result
    }

    private static func placement(of id: CGDirectDisplayID) -> DisplayPlacement? {
        guard let m = CGDisplayCopyDisplayMode(id) else { return nil }
        let b = CGDisplayBounds(id)
        return DisplayPlacement(
            mode: DisplayMode(width: m.width, height: m.height, pixelWidth: m.pixelWidth,
                              pixelHeight: m.pixelHeight, refreshRate: m.refreshRate),
            x: Int(b.origin.x), y: Int(b.origin.y))
    }

    private static func findMode(_ want: DisplayMode, for id: CGDirectDisplayID) -> CGDisplayMode? {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
        return modes.first {
            $0.width == want.width && $0.height == want.height
                && $0.pixelWidth == want.pixelWidth && $0.pixelHeight == want.pixelHeight
                && abs($0.refreshRate - want.refreshRate) < 0.5
        }
    }
}
