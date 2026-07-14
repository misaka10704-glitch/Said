import Foundation

/// Mode A — Azure pronunciation only. Ported from pronounce_scorer.
enum PronounceMode {
    enum Granularity {
        case phoneme
        case phrase
        case sentence
    }

    static func parseTarget(card: AnkiCardSnapshot) -> (reference: String, phonetic: String, mode: Granularity) {
        let model = card.modelName
        let deck = card.deckName
        let fields = card.fields

        if model == "Speaking Reference", ModeRouter.deckMatches(deck, prefixes: ["Pronounce_Learning::Sentence"]) {
            return (parseSpeakingRefSentence(fields), "", .sentence)
        }
        if ModeRouter.sentenceModels.contains(model)
            || ModeRouter.deckMatches(deck, prefixes: ModeRouter.sentenceDeckPrefixes) {
            let ref = fields.first.map { ModeRouter.stripField($0) } ?? ""
            return (ref, "", .sentence)
        }
        if ModeRouter.phraseModels.contains(model)
            || ModeRouter.deckMatches(deck, prefixes: ModeRouter.phraseDeckPrefixes) {
            let ref = fields.first.map { ModeRouter.stripField($0) } ?? ""
            return (ref, "", .phrase)
        }
        let front = fields.first.map { ModeRouter.stripField($0) } ?? ""
        let (word, phonetic) = parseFront(front)
        return (word, phonetic, .phoneme)
    }

    private static func parseSpeakingRefSentence(_ fields: [String]) -> String {
        if fields.count >= 4 {
            let f = ModeRouter.stripField(fields[3])
            if !f.isEmpty { return f }
        }
        for html in fields {
            if let re = try? NSRegularExpression(pattern: "<span[^>]*>([^<]{10,})</span>"),
               let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let r = Range(m.range(at: 1), in: html) {
                return String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return fields.first.map { ModeRouter.stripField($0) } ?? ""
    }

    private static func parseFront(_ text: String) -> (String, String) {
        if let re = try? NSRegularExpression(pattern: "^([^\\s/：:]+)\\s+(/[^/]+/)"),
           let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let word = Range(m.range(at: 1), in: text).map { String(text[$0]) } ?? ""
            let phonetic = Range(m.range(at: 2), in: text).map { String(text[$0]) } ?? ""
            return (word, phonetic)
        }
        let word = text.split(separator: " ").first.map(String.init) ?? text
        return (word, "")
    }
}
