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
        statusItem.button?.image = MenuBarIcon.makeImage()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate

    /// 메뉴를 열 때마다 현재 상태로 다시 만든다. (G1 검사 포함)
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !backend.isToggleAvailable {
            menu.addItem(disabledItem(L("Turning displays off is not available on this macOS")))
            menu.addItem(.separator())
        }
        if let notice {
            menu.addItem(disabledItem(notice))
            menu.addItem(.separator())
        }

        menu.addItem(disabledItem(L("Displays")))
        for entry in controller.entries() {
            let item = NSMenuItem(title: entry.name, action: #selector(toggle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.uuid
            item.state = entry.isActive ? .on : .off
            if entry.isActive {
                if case .denied(let reason) = controller.disableDecision(uuid: entry.uuid) {
                    item.title = L("%@ (%@)", entry.name, reason.localized)
                    item.action = nil
                }
            } else {
                item.title = L("%@ (off)", entry.name)
            }
            if !backend.isToggleAvailable { item.action = nil }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let all = NSMenuItem(title: L("Enable All"), action: #selector(enableAll), keyEquivalent: "")
        all.target = self
        menu.addItem(all)

        let about = NSMenuItem(title: L("About DisplayToggle"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        if !AppLinks.github.isEmpty, let url = URL(string: AppLinks.github) {
            menu.addItem(linkItem(L("GitHub"), url))
        }
        if !AppLinks.buyMeACoffee.isEmpty, let url = URL(string: AppLinks.buyMeACoffee) {
            menu.addItem(linkItem(L("Buy me a coffee"), url))
        }

        let quit = NSMenuItem(title: L("Quit"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - 동작

    /// 구성 변경 콜백에서 호출한다. (G3)
    func handleReconfiguration() {
        let recovered = controller.recoverIfNeeded()
        guard !recovered.isEmpty else { return }
        if controller.registry.offByApp.isEmpty {
            notice = L("No active display was left, so the displays that were turned off were turned on again")
        } else {
            notice = L("Some displays could not be turned on")
        }
    }

    @objc private func toggle(_ sender: NSMenuItem) {
        guard let uuid = sender.representedObject as? String else { return }
        do {
            let outcome = sender.state == .on ? try controller.disable(uuid: uuid) : try controller.enable(uuid: uuid)
            switch outcome {
            case .done: notice = nil
            case .doneWithWarning(let warning): notice = warning.localized
            }
        } catch DisplayToggleError.blocked(let reason) {
            notice = reason.localized
        } catch {
            NSLog("DisplayToggle: %@", String(describing: error))
            notice = L("Could not change the display. Try again.")
        }
    }

    @objc private func enableAll() {
        let failed = controller.enableAll()
        notice = failed.isEmpty ? nil : L("Some displays could not be turned on")
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
