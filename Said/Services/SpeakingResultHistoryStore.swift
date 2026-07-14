import Foundation

/// A compact, card-keyed snapshot of the last completed speaking assessment.
/// It intentionally stays outside the Anki collection: re-scoring a card must
/// be able to compare against the previous local attempt without mutating its
/// note fields or scheduling data.
struct SpeakingResultSnapshot: Codable {
    struct Metric: Codable {
        let title: String
        let value: Double
    }

    struct Section: Codable {
        let title: String
        let body: String
        let style: String
    }

    struct WeakItem: Codable {
        let word: String
        let score: Double
        let detail: String
    }

    let cardID: Int64
    let createdAt: Date
    let title: String
    let transcript: String
    let metrics: [Metric]
    let sections: [Section]
    let weakItems: [WeakItem]
    /// Optional preserves compatibility with history snapshots created before
    /// word-level Azure details were persisted.
    let pronunciationWords: [PronunciationWordScore]?

    init(cardID: Int64, content: SpeakingResultContent) {
        self.cardID = cardID
        createdAt = Date()
        title = content.title
        transcript = content.transcript
        metrics = content.metrics.map { Metric(title: $0.title, value: $0.value) }
        sections = content.sections.map {
            Section(title: $0.title, body: $0.body, style: $0.style.historyValue)
        }
        weakItems = content.weakItems.map {
            WeakItem(word: $0.word, score: $0.score, detail: $0.detail)
        }
        pronunciationWords = content.pronunciationWords
    }

    func content() -> SpeakingResultContent {
        SpeakingResultContent(
            title: title,
            transcript: transcript,
            metrics: metrics.map { SpeakingMetric(title: $0.title, value: $0.value) },
            sections: sections.map {
                SpeakingResultSection(title: $0.title, body: $0.body, style: .fromHistory($0.style))
            },
            weakItems: weakItems.map {
                SpeakingWeakItem(word: $0.word, score: $0.score, detail: $0.detail)
            },
            pronunciationWords: pronunciationWords ?? []
        )
    }
}

final class SpeakingResultHistoryStore {
    static let shared = SpeakingResultHistoryStore()
    private let key = "said_speaking_result_history_v1"
    private let queue = DispatchQueue(label: "com.said.speaking.result-history")

    func save(cardID: Int64, content: SpeakingResultContent) {
        let snapshot = SpeakingResultSnapshot(cardID: cardID, content: content)
        queue.async {
            var entries = self.read()
            entries.removeAll { $0.cardID == cardID }
            entries.insert(snapshot, at: 0)
            UserDefaults.standard.set(
                try? JSONEncoder().encode(Array(entries.prefix(500))),
                forKey: self.key
            )
        }
    }

    func latest(cardID: Int64, completion: @escaping (SpeakingResultSnapshot?) -> Void) {
        queue.async {
            let value = self.read().first { $0.cardID == cardID }
            DispatchQueue.main.async { completion(value) }
        }
    }

    private func read() -> [SpeakingResultSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SpeakingResultSnapshot].self, from: data)) ?? []
    }
}

private extension SpeakingResultSectionStyle {
    var historyValue: String {
        switch self {
        case .neutral: return "neutral"
        case .azure: return "azure"
        case .qwenModel: return "model"
        case .qwenCoach: return "coach"
        case .qwenCorrection: return "correction"
        case .qwenImprovement: return "improvement"
        case .error: return "error"
        }
    }

    static func fromHistory(_ value: String) -> SpeakingResultSectionStyle {
        switch value {
        case "azure": return .azure
        case "model": return .qwenModel
        case "coach": return .qwenCoach
        case "correction": return .qwenCorrection
        case "improvement": return .qwenImprovement
        case "error": return .error
        default: return .neutral
        }
    }
}
