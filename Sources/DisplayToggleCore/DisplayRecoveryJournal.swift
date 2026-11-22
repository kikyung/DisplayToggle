import Foundation

struct DisplayRecoveryJournal {
    private struct Record: Codable {
        let sessionID: UUID
        let displayIDs: [String: UInt32]
    }

    let url: URL
    let sessionID: UUID

    func load() -> [String: UInt32] {
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.sessionID == sessionID else { return [:] }
        return record.displayIDs
    }

    func save(_ displayIDs: [String: UInt32]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Record(sessionID: sessionID, displayIDs: displayIDs))
        try data.write(to: url, options: .atomic)
    }
}
