// Task 0 spike: CGSConfigureDisplayEnabled 동작 확인용 최소 도구.
// 사용법:
//   swiftc Spike/spike.swift -o /tmp/spike
//   /tmp/spike list
//   /tmp/spike toggle <displayID> [seconds=5]
import ApplicationServices
import CoreGraphics
import Foundation

typealias ConfigureEnabledFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT

func loadConfigureEnabled() -> ConfigureEnabledFn? {
    guard let sym = dlsym(rtldDefault, "CGSConfigureDisplayEnabled") else { return nil }
    return unsafeBitCast(sym, to: ConfigureEnabledFn.self)
}

func onlineDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &ids, &count)
    return Array(ids.prefix(Int(count)))
}

func uuidString(_ id: CGDirectDisplayID) -> String {
    guard let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
          let s = CFUUIDCreateString(nil, u) else { return "?" }
    return s as String
}

func describe(_ id: CGDirectDisplayID) -> String {
    let b = CGDisplayBounds(id)
    let mode = CGDisplayCopyDisplayMode(id)
    let modeText = mode.map { "\($0.width)x\($0.height)@\($0.refreshRate)Hz px:\($0.pixelWidth)x\($0.pixelHeight)" } ?? "no-mode"
    return "id=\(id) uuid=\(uuidString(id)) active=\(CGDisplayIsActive(id) != 0) builtin=\(CGDisplayIsBuiltin(id) != 0) "
        + "origin=(\(Int(b.origin.x)),\(Int(b.origin.y))) mode=\(modeText) vendor=\(CGDisplayVendorNumber(id)) model=\(CGDisplayModelNumber(id))"
}

func printAll(_ title: String) {
    print("--- \(title)")
    for id in onlineDisplays() { print(describe(id)) }
}

func setEnabled(_ fn: ConfigureEnabledFn, _ id: CGDirectDisplayID, _ enabled: Bool) -> Bool {
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success else { print("Begin 실패"); return false }
    let r = fn(cfg, id, enabled)
    guard r == .success else {
        print("CGSConfigureDisplayEnabled 실패: \(r.rawValue)")
        CGCancelDisplayConfiguration(cfg)
        return false
    }
    let c = CGCompleteDisplayConfiguration(cfg, .forSession)
    print("Complete(enabled=\(enabled)) 결과: \(c.rawValue)")
    return c == .success
}

let args = CommandLine.arguments
guard args.count >= 2 else { print("사용법: spike list | spike toggle <displayID> [seconds]"); exit(1) }

guard let fn = loadConfigureEnabled() else {
    print("심볼 CGSConfigureDisplayEnabled 를 찾지 못했습니다. 이 macOS에서는 사용할 수 없습니다.")
    exit(2)
}
print("심볼 발견: CGSConfigureDisplayEnabled")

switch args[1] {
case "list":
    printAll("online displays")

case "toggle":
    guard args.count >= 3, let target = UInt32(args[2]) else { print("displayID 필요"); exit(1) }
    let seconds = args.count >= 4 ? (Double(args[3]) ?? 5) : 5
    let active = onlineDisplays().filter { CGDisplayIsActive($0) != 0 }
    guard active.count >= 2 else { print("켜진 모니터가 2대 미만이라 중단합니다."); exit(3) }
    guard active.contains(target) else { print("대상이 켜져 있지 않습니다."); exit(3) }

    // 어떤 경우에도 대상을 다시 켠다 (Ctrl-C 포함).
    var restored = false
    func restore() {
        guard !restored else { return }
        restored = true
        print("복구 시도")
        _ = setEnabled(fn, target, true)
        Thread.sleep(forTimeInterval: 2)
        printAll("복구 후")
    }
    signal(SIGINT, SIG_IGN)
    let sig = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sig.setEventHandler { restore(); exit(0) }
    sig.resume()

    printAll("끄기 전")
    guard setEnabled(fn, target, false) else { exit(4) }
    Thread.sleep(forTimeInterval: 2)
    printAll("끈 직후 (2초 뒤)")
    print("\(seconds)초 뒤 다시 켭니다. 복구 안 되면 Ctrl-C 또는 터미널을 닫지 말고 기다리세요.")
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { restore(); exit(0) }
    dispatchMain()

default:
    print("알 수 없는 명령")
    exit(1)
}
