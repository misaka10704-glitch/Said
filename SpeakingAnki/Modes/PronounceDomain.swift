import Foundation

enum PronounceGranularity: String, Codable {
    case phoneme, phrase, sentence
}

struct PronounceTarget: Codable, Equatable {
    let referenceText: String
    let phonetic: String
    let granularity: PronounceGranularity
    let noteID: Int64
    let cardID: Int64
    let deckName: String
    let modelName: String

    var cacheKey: String {
        let hash = referenceText.unicodeScalars.reduce(UInt64(1469598103934665603)) {
            ($0 ^ UInt64($1.value)) &* UInt64(1099511628211)
        }
        return "\(noteID)_\(String(hash, radix: 16))"
    }
}

struct PronouncePhonemeViewModel: Codable, Equatable {
    let symbol: String
    let accuracy: Double
    let stress: Int
    var stressMark: String { stress == 1 ? "ˈ" : (stress == 2 ? "ˌ" : "") }
}

struct PronounceWordViewModel: Codable, Equatable {
    let word: String
    let accuracy: Double
    let error: String?
    let phonemes: [PronouncePhonemeViewModel]
}

struct PronounceScoreViewModel: Codable, Equatable {
    let transcript: String
    let accuracy: Double
    let fluency: Double
    let completeness: Double
    let prosody: Double?
    let words: [PronounceWordViewModel]

    var weakestWords: [PronounceWordViewModel] {
        words.filter { $0.accuracy < 80 }.sorted { $0.accuracy < $1.accuracy }
    }
}

enum PronounceReferenceTargetParser {
    static let sentenceModels: Set<String> = ["轻听英语 句库", "speaking reference"]
    static let phraseModels: Set<String> = ["轻听英语 生词"]
    static let sentenceDeckPrefixes = ["轻听英语·句库", "Pronounce_Learning::Sentence"]
    static let phraseDeckPrefixes = ["轻听英语·生词本", "Pronounce_Learning::Words", "Pronounce_Learning::Linking"]

    static func parse(card: AnkiCardSnapshot, deckHint: String? = nil) -> PronounceTarget? {
        guard !card.fields.isEmpty else { return nil }
        let model = normalizedName(card.modelName)
        let decks = [card.deckName, deckHint].compactMap { $0 }.map(normalizedDeck)
        let deckLeaves = decks.compactMap {
            $0.components(separatedBy: "::").last?.lowercased()
        }
        let reference: String
        let phonetic: String
        let granularity: PronounceGranularity

        if model == "speaking reference",
           decks.contains(where: { deckMatches($0, prefixes: ["Pronounce_Learning::Sentence"]) })
                || deckLeaves.contains("sentence") {
            reference = speakingReferenceText(card)
            phonetic = ""
            granularity = .sentence
        } else if sentenceModels.map(normalizedName).contains(model)
                    || decks.contains(where: { deckMatches($0, prefixes: sentenceDeckPrefixes) })
                    || deckLeaves.contains("sentence") {
            reference = preferredText(card, names: ["English", "Sentence", "Text", "Front"])
            phonetic = ""
            granularity = .sentence
        } else if phraseModels.map(normalizedName).contains(model)
                    || decks.contains(where: { deckMatches($0, prefixes: phraseDeckPrefixes) })
                    || deckLeaves.contains(where: { $0.hasPrefix("linking") }) {
            reference = preferredText(card, names: ["English", "Phrase", "Word", "Front"])
            phonetic = ""
            granularity = .phrase
        } else {
            let parsed = parsePhonemeFront(stripField(card.fields[0]))
            reference = parsed.0
            phonetic = parsed.1
            granularity = .phoneme
        }

        let cleanReference = normalizedWhitespace(reference)
        guard !cleanReference.isEmpty else { return nil }
        return PronounceTarget(
            referenceText: cleanReference,
            phonetic: phonetic,
            granularity: granularity,
            noteID: card.noteId,
            cardID: card.cardId,
            deckName: card.deckName.isEmpty ? (deckHint ?? "") : card.deckName,
            modelName: card.modelName
        )
    }

    static func deckMatches(_ name: String, prefixes: [String]) -> Bool {
        let deck = normalizedDeck(name)
        return prefixes.map(normalizedDeck).contains { deck == $0 || deck.hasPrefix($0 + "::") }
    }

    static func stripField(_ html: String) -> String {
        var text = replace("(?is)<(script|style)\\b[^>]*>.*?</\\1>", in: html, with: " ")
        text = replace("(?i)<br\\s*/?>|</(?:div|p|li|tr|h[1-6])\\s*>", in: text, with: " ")
        text = replace("(?i)\\[sound:[^\\]]+\\]", in: text, with: " ")
        text = replace("(?s)<[^>]+>", in: text, with: " ")
        let entities = ["&nbsp;": " ", "&#160;": " ", "&amp;": "&", "&lt;": "<",
                        "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value, options: .caseInsensitive)
        }
        return normalizedWhitespace(text)
    }

    private static func speakingReferenceText(_ card: AnkiCardSnapshot) -> String {
        if let english = field(card, names: ["English"]) { return english }
        if card.fields.count >= 4 {
            let value = stripField(card.fields[3])
            if !value.isEmpty { return value }
        }
        let pattern = "(?is)<span\\b[^>]*>([^<]{10,})</span>"
        for html in card.fields {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { continue }
            let value = stripField(String(html[range]))
            if !value.isEmpty { return value }
        }
        return preferredText(card, names: ["Sentence", "Text", "Front"])
    }

    private static func preferredText(_ card: AnkiCardSnapshot, names: [String]) -> String {
        field(card, names: names) ?? stripField(card.fields[0])
    }

    private static func field(_ card: AnkiCardSnapshot, names: [String]) -> String? {
        let wanted = names.map(normalizedName)
        for (index, fieldName) in card.fieldNames.enumerated() where index < card.fields.count {
            if wanted.contains(normalizedName(fieldName)) {
                let value = stripField(card.fields[index])
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    private static func parsePhonemeFront(_ text: String) -> (String, String) {
        let pattern = "^([^\\s/：:]+)\\s+(/[^/]+/)"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let word = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? ""
            let phonetic = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
            return (word, phonetic)
        }
        return (text.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? text, "")
    }

    private static func normalizedDeck(_ value: String) -> String {
        replace(
            "\\s*::\\s*",
            in: value
                .replacingOccurrences(of: "\u{1f}", with: "::")
                .replacingOccurrences(of: "：", with: ":"),
            with: "::"
        )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedName(_ value: String) -> String {
        normalizedWhitespace(value).lowercased()
    }

    private static func normalizedWhitespace(_ value: String) -> String {
        replace("\\s+", in: value, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(_ pattern: String, in value: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        return regex.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: replacement)
    }
}

enum PronouncePhonemeNotation {
    private static let arpabetToIPA = [
        "aa":"ɑ", "ae":"æ", "ah":"ʌ", "ao":"ɔ", "aw":"aʊ", "ax":"ə", "axr":"ɚ",
        "ay":"aɪ", "b":"b", "ch":"tʃ", "d":"d", "dh":"ð", "eh":"ɛ", "er":"ɜr",
        "ey":"eɪ", "f":"f", "g":"ɡ", "hh":"h", "ih":"ɪ", "iy":"iː", "jh":"dʒ",
        "k":"k", "l":"l", "m":"m", "n":"n", "ng":"ŋ", "ow":"oʊ", "oy":"ɔɪ",
        "p":"p", "r":"r", "s":"s", "sh":"ʃ", "t":"t", "th":"θ", "uh":"ʊ",
        "uw":"uː", "v":"v", "w":"w", "y":"j", "z":"z", "zh":"ʒ"
    ]

    static func ipa(for phoneme: String) -> String {
        let key = phoneme.lowercased().replacingOccurrences(of: "[0-9]", with: "", options: .regularExpression)
        return arpabetToIPA[key] ?? phoneme
    }
}
