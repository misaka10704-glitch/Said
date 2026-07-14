import Foundation

enum IELTSPart: Int, CaseIterable {
    case part1 = 1, part2 = 2, part3 = 3

    struct Limits {
        let maximumRecordingSeconds: TimeInterval
        let maximumTranscriptWords: Int
        let modelSentences: ClosedRange<Int>
    }

    var limits: Limits {
        switch self {
        case .part1: return Limits(maximumRecordingSeconds: 30, maximumTranscriptWords: 80, modelSentences: 2...3)
        case .part2: return Limits(maximumRecordingSeconds: 120, maximumTranscriptWords: 300, modelSentences: 8...12)
        case .part3: return Limits(maximumRecordingSeconds: 60, maximumTranscriptWords: 160, modelSentences: 3...5)
        }
    }

    var displayName: String { "Part \(rawValue)" }

    static func infer(deckName: String) -> IELTSPart? {
        let value = deckName.replacingOccurrences(of: " ", with: "").lowercased()
        if value.contains("part1") { return .part1 }
        if value.contains("part2") { return .part2 }
        if value.contains("part3") { return .part3 }
        return nil
    }
}

enum IELTSSpeakingMode {
    static let modelName = "IELTS Speaking"

    static func matches(card: AnkiCardSnapshot) -> Bool {
        normalized(card.modelName) == normalized(modelName)
            && fieldIndex("Question", in: card) != nil
            && fieldIndex("Part", in: card) != nil
    }

    static func part(for card: AnkiCardSnapshot) -> IELTSPart? {
        guard let value = field("Part", in: card) else { return nil }
        let digits = value.filter { $0 >= "0" && $0 <= "9" }
        return Int(digits).flatMap(IELTSPart.init(rawValue:))
    }

    static func question(for card: AnkiCardSnapshot) -> String {
        field("Question", in: card) ?? ""
    }

    private static func field(_ name: String, in card: AnkiCardSnapshot) -> String? {
        guard let index = fieldIndex(name, in: card), index < card.fields.count else { return nil }
        let value = ModeRouter.stripField(card.fields[index])
        return value.isEmpty ? nil : value
    }

    private static func fieldIndex(_ name: String, in card: AnkiCardSnapshot) -> Int? {
        let target = normalized(name)
        return card.fieldNames.firstIndex { normalized($0) == target }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum IELTSTranscriptPolicy {
    private static let stopWords: Set<String> = [
        "the", "a", "an", "or", "and", "do", "you", "your", "is", "are", "to", "of",
        "in", "on", "for", "with", "what", "how", "when", "where", "why", "which",
        "that", "this", "it", "i", "my", "me", "we", "they", "he", "she", "have",
        "has", "had", "be", "been", "was", "were", "would", "could", "should", "can",
        "will", "did", "does", "about", "from", "at", "by", "not", "no", "yes", "so",
        "if", "but", "prefer", "like", "think", "really", "very", "quite", "some"
    ]

    static func heuristicRepair(_ text: String, question: String) -> String {
        let q = question.lowercased()
        let taskTopic = ["boring", "tedious", "task", "fun", "focus", "motivat"].contains { q.contains($0) }
        let musicTopic = q.contains("music")
        let fixes: [(String, String, Bool)] = [
            ("\\bsporting\\s+tasks\\b", "boring tasks", taskTopic || !musicTopic),
            ("\\bsporting\\b", "boring", taskTopic), ("\\btaskers\\b", "tasks", true),
            ("\\bsmoking\\b", "boring", true), ("\\bemit\\b", "it makes", true),
            ("\\bthe\\s+house\\s+means\\b", "it helps me", true),
            ("\\byou\\s+may\\b", "it makes", true)
        ]
        var output = text
        for (pattern, replacement, enabled) in fixes where enabled {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            output = regex.stringByReplacingMatches(
                in: output, range: NSRange(output.startIndex..., in: output), withTemplate: replacement
            )
        }
        return output.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func isQuestionEcho(_ text: String, question: String) -> Bool {
        let answer = normalized(text), prompt = normalized(question)
        guard !answer.isEmpty, !prompt.isEmpty else { return false }
        return answer == prompt || (prompt.count > 12 && answer.contains(prompt))
            || (answer.count > 12 && prompt.contains(answer))
    }

    static func trustedRepair(raw: String, candidate: String, question: String) -> String {
        let repaired = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repaired.isEmpty, raw.caseInsensitiveCompare(repaired) != .orderedSame,
              raw.split(whereSeparator: { $0.isWhitespace }).count > 2,
              !isQuestionEcho(repaired, question: question),
              !substitutesQuestion(raw: raw, repaired: repaired, question: question) else { return "" }
        return repaired
    }

    static func needsReassessment(raw: String, repaired: String) -> Bool {
        let before = raw.lowercased().split(whereSeparator: { $0.isWhitespace })
        let after = repaired.lowercased().split(whereSeparator: { $0.isWhitespace })
        if abs(before.count - after.count) > 1 { return true }
        return zip(before, after).filter { $0 != $1 }.count > 2
    }

    private static func substitutesQuestion(raw: String, repaired: String, question: String) -> Bool {
        let a = contentWords(raw), b = contentWords(repaired), q = contentWords(question)
        let added = b.subtracting(a), removed = a.subtracting(b)
        return a != b && !added.isEmpty && !removed.isEmpty
            && !added.intersection(q).subtracting(a).isEmpty
    }

    private static func contentWords(_ text: String) -> Set<String> {
        Set(text.lowercased().components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) })
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }
}
