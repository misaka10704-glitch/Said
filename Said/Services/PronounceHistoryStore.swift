import Foundation

struct PronounceHistoryEntry: Codable, Equatable {
    let id: String
    let createdAt: Date
    let target: PronounceTarget
    let score: PronounceScoreViewModel
    let recordingPath: String?

    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        target: PronounceTarget,
        score: PronounceScoreViewModel,
        recordingURL: URL?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.target = target
        self.score = score
        self.recordingPath = recordingURL?.path
    }

    var recordingURL: URL? {
        recordingPath.map { URL(fileURLWithPath: $0) }
    }
}

protocol PronounceHistoryStoring {
    func save(_ entry: PronounceHistoryEntry, completion: ((Error?) -> Void)?)
    func latest(for target: PronounceTarget, completion: @escaping (PronounceHistoryEntry?) -> Void)
    func entries(limit: Int, completion: @escaping ([PronounceHistoryEntry]) -> Void)
    func removeAll(completion: ((Error?) -> Void)?)
}

final class PronounceHistoryStore: PronounceHistoryStoring {
    static let shared = PronounceHistoryStore()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "pronounce.history.store")
    private let maximumEntries: Int

    init(fileURL: URL? = nil, maximumEntries: Int = 500) {
        self.maximumEntries = max(1, maximumEntries)
        if let fileURL = fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Pronounce", isDirectory: true)
            self.fileURL = base.appendingPathComponent("history.json")
        }
    }

    func save(_ entry: PronounceHistoryEntry, completion: ((Error?) -> Void)? = nil) {
        queue.async {
            do {
                var values = try self.read()
                values.removeAll { $0.id == entry.id }
                values.insert(entry, at: 0)
                if values.count > self.maximumEntries {
                    values.removeLast(values.count - self.maximumEntries)
                }
                try self.write(values)
                self.finish(completion, nil)
            } catch {
                self.finish(completion, error)
            }
        }
    }

    func latest(for target: PronounceTarget, completion: @escaping (PronounceHistoryEntry?) -> Void) {
        queue.async {
            let value = (try? self.read())?.first {
                $0.target.noteID == target.noteID && $0.target.referenceText == target.referenceText
            }
            DispatchQueue.main.async { completion(value) }
        }
    }

    func entries(limit: Int, completion: @escaping ([PronounceHistoryEntry]) -> Void) {
        queue.async {
            let values = Array(((try? self.read()) ?? []).prefix(max(0, limit)))
            DispatchQueue.main.async { completion(values) }
        }
    }

    func removeAll(completion: ((Error?) -> Void)? = nil) {
        queue.async {
            do {
                if FileManager.default.fileExists(atPath: self.fileURL.path) {
                    try FileManager.default.removeItem(at: self.fileURL)
                }
                self.finish(completion, nil)
            } catch {
                self.finish(completion, error)
            }
        }
    }

    private func read() throws -> [PronounceHistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([PronounceHistoryEntry].self, from: Data(contentsOf: fileURL))
    }

    private func write(_ entries: [PronounceHistoryEntry]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    private func finish(_ completion: ((Error?) -> Void)?, _ error: Error?) {
        guard let completion = completion else { return }
        DispatchQueue.main.async { completion(error) }
    }
}
