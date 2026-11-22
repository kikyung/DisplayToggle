import AppKit
import DisplayToggleCore

/// About 패널에 표시할 링크. 비어 있으면 표시하지 않는다.
enum AppLinks {
    static let github = "https://github.com/kikyung/DisplayToggle"
    static let buyMeACoffee = "https://buymeacoffee.com/kikyung"
}

final class MenuBarController: NSObject, NSMenuDelegate {
    private let controller: DisplayController
    private let backend: CoreGraphicsBackend
    private let statusItem: NSStatusItem
    private var notice: String?

    init(controller: DisplayController, backend: CoreGraphicsBackend) {
        self.controller = controller
        self.backend = backend
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        let image = NSImage(systemSymbolName: "display", accessibilityDescription: "DisplayToggle")
        image?.isTemplate = true
        statusItem.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate

    /// 메뉴를 열 때마다 현재 상태로 다시 만든다. (G1 검사 포함)
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !backend.isToggleAvailable {
            menu.addItem(disabledItem("이 macOS에서는 모니터 끄기를 사용할 수 없음"))
            menu.addItem(.separator())
        }
        if let notice {
            menu.addItem(disabledItem(notice))
            menu.addItem(.separator())
        }

        menu.addItem(disabledItem("Displays"))
        for entry in controller.entries() {
            let item = NSMenuItem(title: entry.name, action: #selector(toggle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.uuid
            item.state = entry.isActive ? .on : .off
            if entry.isActive {
                if case .denied(let reason) = controller.disableDecision(uuid: entry.uuid) {
                    item.title = "\(entry.name)  (\(reason))"
                    item.action = nil
                }
            } else {
                item.title = "\(entry.name)  (꺼짐)"
            }
            if !backend.isToggleAvailable { item.action = nil }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let all = NSMenuItem(title: "모두 켜기", action: #selector(enableAll), keyEquivalent: "")
        all.target = self
        menu.addItem(all)

        let about = NSMenuItem(title: "About DisplayToggle", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        if !AppLinks.github.isEmpty, let url = URL(string: AppLinks.github) {
            menu.addItem(linkItem("GitHub", url))
        }
        if !AppLinks.buyMeACoffee.isEmpty, let url = URL(string: AppLinks.buyMeACoffee) {
            menu.addItem(linkItem("Buy me a coffee", url))
        }

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - 동작

    /// 구성 변경 콜백에서 호출한다. (G3)
    func handleReconfiguration() {
        let recovered = controller.recoverIfNeeded()
        if !recovered.isEmpty { notice = "켜진 화면이 없어 꺼 둔 모니터를 다시 켰습니다" }
    }

    @objc private func toggle(_ sender: NSMenuItem) {
        guard let uuid = sender.representedObject as? String else { return }
        do {
            let outcome = sender.state == .on ? try controller.disable(uuid: uuid) : try controller.enable(uuid: uuid)
            switch outcome {
            case .done: notice = nil
            case .doneWithWarning(let message): notice = message
            }
        } catch DisplayToggleError.blocked(let reason) {
            notice = reason
        } catch {
            notice = "실패: \(error)"
        }
    }

    @objc private func enableAll() {
        let failed = controller.enableAll()
        notice = failed.isEmpty ? nil : "일부 모니터를 켜지 못했습니다"
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func openLink(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    @objc private func quit() {
        // 끈 모니터를 모두 켜고 종료한다.
        _ = controller.enableAll()
        NSApp.terminate(nil)
    }

    // MARK: - 헬퍼

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func linkItem(_ title: String, _ url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(openLink(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = url
        return item
    }
}
