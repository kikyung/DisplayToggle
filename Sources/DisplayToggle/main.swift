import DisplayToggleCore
import Foundation

// Task 8에서 메뉴바 앱으로 교체한다. 지금은 모니터를 건드리지 않는 조회 명령만 있다.
if CommandLine.arguments.contains("--list") {
    let backend = CoreGraphicsBackend()
    let controller = DisplayController(backend: backend, registry: DisplayRegistry(fileURL: nil))
    print("toggleAvailable=\(backend.isToggleAvailable)")
    print("raw:")
    for d in backend.connectedDisplays() {
        print("  \(d.uuid) name=\(d.name ?? "nil") active=\(d.isActive) builtin=\(d.isBuiltin) placement=\(String(describing: d.placement))")
    }
    print("entries:")
    for e in controller.entries() { print("  \(e.uuid) \(e.name) active=\(e.isActive)") }
} else {
    print("DisplayToggle (--list 로 모니터 목록 확인)")
}
