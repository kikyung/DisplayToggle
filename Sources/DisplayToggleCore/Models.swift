import Foundation

public struct DisplayMode: Equatable, Codable {
    public var width: Int
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refreshRate: Double

    public init(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refreshRate: Double) {
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
    }
}

public struct DisplayPlacement: Equatable, Codable {
    public var mode: DisplayMode
    public var x: Int
    public var y: Int

    public init(mode: DisplayMode, x: Int, y: Int) {
        self.mode = mode
        self.x = x
        self.y = y
    }
}

/// 백엔드가 보고하는 모니터 한 대. 꺼진 모니터도 온라인이면 isActive == false 로 나온다.
public struct DisplayInfo: Equatable {
    public var uuid: String
    public var name: String?
    public var isActive: Bool
    public var isBuiltin: Bool
    public var placement: DisplayPlacement?

    public init(uuid: String, name: String?, isActive: Bool, isBuiltin: Bool = false, placement: DisplayPlacement? = nil) {
        self.uuid = uuid
        self.name = name
        self.isActive = isActive
        self.isBuiltin = isBuiltin
        self.placement = placement
    }
}

/// 켜진 모니터들의 해상도와 배치. UUID 기준.
public typealias LayoutSnapshot = [String: DisplayPlacement]

public protocol DisplayBackend: AnyObject {
    func connectedDisplays() -> [DisplayInfo]
    func setEnabled(uuid: String, enabled: Bool) throws
    /// 주어진 모니터들의 모드와 좌표를 한 번의 구성 트랜잭션으로 적용한다.
    func apply(layout: LayoutSnapshot) throws
}

/// 끌 수 없는 이유. 화면에 표시할 문장은 UI 계층에서 현지화한다.
public enum DenyReason: Equatable {
    case displayNotFound
    case alreadyOff
    case lastActiveDisplay
}

/// 동작은 성공했지만 사용자에게 알려야 하는 경고.
public enum ToggleWarning: Equatable {
    case layoutNotRestored
}

public enum DisplayToggleError: Error, Equatable {
    case blocked(DenyReason)
    /// 기술적인 상세 설명. 현지화하지 않는다.
    case backend(String)
}
