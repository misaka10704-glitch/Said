import Foundation

/// Ease buttons matching Anki Desktop / AnkiDroid.
enum AnkiEase: Int {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4
}

/// Card queue / type constants from Anki collection schema.
enum AnkiCardQueue: Int {
    case new = 0
    case learning = 1
    case review = 2
    case dayLearn = 3
    case preview = 4
    case suspended = -1
    case siblingBuried = -2
    case manuallyBuried = -3
}

enum AnkiCardType: Int {
    case new = 0
    case learning = 1
    case review = 2
    case relearning = 3
}

enum PracticeMode {
    case pronounce
    case ielts
    case compose
    case unsupported
}

struct AnkiDeckInfo: Equatable {
    let id: Int64
    let name: String
    let newCount: Int
    let learnCount: Int
    let reviewCount: Int

    var dueTotal: Int { newCount + learnCount + reviewCount }
}

struct AnkiCardSnapshot {
    let cardId: Int64
    let noteId: Int64
    let deckId: Int64
    let deckName: String
    let modelName: String
    let ord: Int
    let type: Int
    let queue: Int
    let due: Int
    let ivl: Int
    let factor: Int
    let reps: Int
    let lapses: Int
    let left: Int
    let fields: [String]
    let fieldNames: [String]
    let frontHTML: String
    let backHTML: String
    let mediaDir: URL
    let nextIntervals: [AnkiEase: String]
}

struct ScoreResult {
    var transcript: String = ""
    var accuracy: Double = 0
    var fluency: Double = 0
    var completeness: Double = 0
    var words: [[String: Any]] = []
    var llmFix: String = ""
    var llmBetter: String = ""
    var error: String?
}
