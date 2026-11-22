import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// CoreGraphics와 비공개 함수 CGSConfigureDisplayEnabled를 쓰는 실제 백엔드.
public final class CoreGraphicsBackend: DisplayBackend {
    private typealias ConfigureEnabledFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

    private let configureEnabled: ConfigureEnabledFn?

    /// 심볼을 찾지 못하면 nil이 아니라 isToggleAvailable == false 상태로 만든다.
    public init() {
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
        return Self.onlineIDs().compactMap { id in
            guard let uuid = Self.uuid(of: id) else { return nil }
            let active = CGDisplayIsActive(id) != 0
            return DisplayInfo(
                uuid: uuid,
                name: names[id],
                isActive: active,
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                placement: active ? Self.placement(of: id) : nil
            )
        }
    }

    public func setEnabled(uuid: String, enabled: Bool) throws {
        guard let fn = configureEnabled else {
            throw DisplayToggleError.backend("이 macOS에서는 모니터 끄기를 사용할 수 없습니다")
        }
        guard let id = Self.onlineIDs().first(where: { Self.uuid(of: $0) == uuid }) else {
            throw DisplayToggleError.backend("모니터를 찾을 수 없습니다")
        }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else {
            throw DisplayToggleError.backend("구성 시작 실패")
        }
        let r = fn(config, id, enabled)
        guard r == .success else {
            CGCancelDisplayConfiguration(config)
            throw DisplayToggleError.backend("CGSConfigureDisplayEnabled 실패 (\(r.rawValue))")
        }
        let c = CGCompleteDisplayConfiguration(config, .forSession)
        guard c == .success else {
            throw DisplayToggleError.backend("구성 적용 실패 (\(c.rawValue))")
        }
    }

    public func apply(layout: LayoutSnapshot) throws {
        let ids = Dictionary(uniqueKeysWithValues: Self.onlineIDs().compactMap { id in
            Self.uuid(of: id).map { ($0, id) }
        })
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else {
            throw DisplayToggleError.backend("구성 시작 실패")
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
            throw DisplayToggleError.backend("구성 적용 실패 (\(c.rawValue))")
        }
    }

    // MARK: - 헬퍼

    private static func onlineIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
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

/// 디스플레이 구성 변경을 감시한다. 변경이 몰려서 오므로 잠깐 모아서 한 번만 알린다.
public final class ReconfigWatcher {
    private var handler: (() -> Void)?
    private var pending: DispatchWorkItem?
    private let delay: TimeInterval

    public init(delay: TimeInterval = 0.5) { self.delay = delay }

    public func start(_ handler: @escaping () -> Void) {
        self.handler = handler
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
            // begin 단계는 건너뛰고 완료 후에만 처리한다.
            guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
            let me = Unmanaged<ReconfigWatcher>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { me.schedule() }
        }, ptr)
    }

    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.handler?() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
