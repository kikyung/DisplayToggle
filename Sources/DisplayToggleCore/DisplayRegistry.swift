import Foundation

public struct DisplayEntry: Equatable {
    public var uuid: String
    public var name: String
    public var isActive: Bool
    public var isBuiltin: Bool
}

/// 본 적 있는 모니터와 앱이 꺼 둔 모니터를 JSON으로 저장하고, 현재 연결 상태와 합쳐 목록을 만든다.
public final class DisplayRegistry {
    struct Record: Codable, Equatable {
        var name: String
        var isBuiltin: Bool
        var lastPlacement: DisplayPlacement?
    }

    struct Store: Codable {
        var records: [String: Record] = [:]
        var offByApp: Set<String> = []
        var layoutBeforeDisable: LayoutSnapshot?
    }

    private let fileURL: URL?
    private var store: Store

    /// fileURL이 nil이면 메모리에서만 동작한다.
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let url = fileURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Store.self, from: data) {
            store = decoded
        } else {
            store = Store()
        }
    }

    public var offByApp: Set<String> { store.offByApp }
    var layoutBeforeDisable: LayoutSnapshot { store.layoutBeforeDisable ?? [:] }

    public func lastPlacement(for uuid: String) -> DisplayPlacement? {
        store.records[uuid]?.lastPlacement
    }

    /// 현재 연결된 모니터로 기록을 갱신한다. 이름이 없는 임시 항목은 기록하지 않는다.
    public func observe(_ displays: [DisplayInfo]) {
        for d in displays {
            guard let name = d.name, !name.isEmpty else { continue }
            var rec = store.records[d.uuid] ?? Record(name: name, isBuiltin: d.isBuiltin, lastPlacement: nil)
            rec.name = name
            rec.isBuiltin = d.isBuiltin
            if d.isActive, let p = d.placement { rec.lastPlacement = p }
            store.records[d.uuid] = rec
        }
        save()
    }

    public func markOff(_ uuid: String) {
        markOff(uuid, layoutBeforeDisable: nil)
    }

    func markOff(_ uuid: String, layoutBeforeDisable: LayoutSnapshot?) {
        if store.layoutBeforeDisable == nil {
            store.layoutBeforeDisable = layoutBeforeDisable
        }
        store.offByApp.insert(uuid)
        save()
    }

    public func markOn(_ uuid: String) {
        store.offByApp.remove(uuid)
        if store.offByApp.isEmpty { store.layoutBeforeDisable = nil }
        save()
    }

    public func clearOffMarks() {
        store.offByApp.removeAll()
        store.layoutBeforeDisable = nil
        save()
    }

    /// 목록 = 현재 연결된 모니터 ∪ 앱이 꺼 둔 모니터. UUID가 같으면 항목 하나.
    public func entries(connected: [DisplayInfo]) -> [DisplayEntry] {
        var result: [String: DisplayEntry] = [:]
        var order: [String] = []

        func add(_ e: DisplayEntry) {
            if result[e.uuid] == nil { order.append(e.uuid) }
            result[e.uuid] = e
        }

        for d in connected {
            let name = (d.name?.isEmpty == false ? d.name : nil) ?? store.records[d.uuid]?.name
            guard let name else { continue }  // 이름 없는 임시 항목은 표시하지 않는다
            add(DisplayEntry(uuid: d.uuid, name: name, isActive: d.isActive, isBuiltin: d.isBuiltin))
        }
        for uuid in store.offByApp.sorted() where result[uuid] == nil {
            guard let rec = store.records[uuid] else { continue }
            add(DisplayEntry(uuid: uuid, name: rec.name, isActive: false, isBuiltin: rec.isBuiltin))
        }
        return order.compactMap { result[$0] }
    }

    private func save() {
        guard let url = fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(store).write(to: url, options: .atomic)
        } catch {
            // 저장 실패는 치명적이지 않다. 다음 호출에서 다시 시도한다.
        }
    }
}
