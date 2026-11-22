import AppKit
import DisplayToggleCore

func defaultRegistryURL() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("DisplayToggle/displays.json")
}

// 모니터를 건드리지 않는 조회 명령
if CommandLine.arguments.contains("--list") {
    let backend = CoreGraphicsBackend()
    let controller = DisplayController(backend: backend, registry: DisplayRegistry(fileURL: nil))
    print("toggleAvailable=\(backend.isToggleAvailable)")
    for e in controller.entries() { print("\(e.uuid) \(e.name) active=\(e.isActive)") }
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private let watcher = ReconfigWatcher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let registryURL = defaultRegistryURL()
        let recoveryURL = registryURL.deletingLastPathComponent().appendingPathComponent("recovery.json")
        let backend = CoreGraphicsBackend(recoveryURL: recoveryURL)
        let registry = DisplayRegistry(fileURL: registryURL)
        for uuid in backend.pendingRecoveryUUIDs { registry.markOff(uuid) }
        let controller = DisplayController(backend: backend, registry: registry)
        // G4: 이전 세션에서 꺼 둔 모니터를 모두 켠다.
        controller.recoverAtLaunch()
        let menuBar = MenuBarController(controller: controller, backend: backend)
        self.menuBar = menuBar
        // G3: 구성 변경 후 켜진 모니터가 0개가 되면 복구한다.
        watcher.start { menuBar.handleReconfiguration() }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // Dock 아이콘 없음
let delegate = AppDelegate()
app.delegate = delegate
app.run()
