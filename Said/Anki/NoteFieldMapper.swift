import Foundation

enum SaidNoteTags {
    static let needsTranslation = "trans"

    static func hasNeedsTranslation(_ tags: [String]) -> Bool {
        for tag in tags {
            if matchesNeedsTranslation(tag) { return true }
            for part in tag.split(whereSeparator: \.isWhitespace) where !part.isEmpty {
                if matchesNeedsTranslation(String(part)) { return true }
            }
        }
        return false
    }

    static func matchesNeedsTranslation(_ tag: String) -> Bool {
        let normalized = tag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "：", with: ":")
            .lowercased()
        return normalized == "trans"
            || normalized == "said::needs_translation"
            || normalized.hasSuffix("::needs_translation")
            || normalized == "needs_translation"
    }

    static func removingNeedsTranslation(from tags: [String]) -> [String] {
        tags.filter { !matchesNeedsTranslation($0) }
    }
}

/// Shared field-name heuristics for English source text and Chinese translations.
enum NoteFieldMapper {
    static let englishCandidates = [
        "English", "Word", "Phrase", "Sentence", "Text", "Question", "Topic", "Answer", "Keywords"
    ]
    static let chineseCandidates = [
        "Chinese", "中文", "Translation", "Meaning", "释义", "汉语", "Definition"
    ]
    private static let primaryContentNames = [
        "word", "phrase", "english", "sentence", "text", "front", "question", "topic", "keywords",
        "单词", "短语", "句子"
    ]
    private static let skipTargetFieldNames = [
        "audio", "course", "episode", "context", "meta", "level", "lang", "structures", "cues", "tags"
    ]
    private static let wordMeaningDivClass = "said-word-meaning"
    private static let phonemeTeachingMarkers = [
        "舌尖", "齿龈", "爆破", "气流", "短元音", "长元音", "双唇", "摩擦", "塞音", "鼻音",
        "辅音", "元音", "声带", "咬舌", "卷舌", "（清）", "（浊）", "（短促）"
    ]

    static func primaryContentFieldIndex(in fieldNames: [String]) -> Int? {
        fieldNames.firstIndex { field in
            let value = normalized(field)
            return primaryContentNames.contains { value == $0 || value.contains($0) }
        }
    }

    static func sourceFieldIndex(in fieldNames: [String], fields: [String]) -> Int? {
        if let primary = primaryContentFieldIndex(in: fieldNames),
           fields.indices.contains(primary) {
            let text = strip(fields[primary])
            if !text.isEmpty, looksEnglish(text) || !looksChinese(text) {
                return primary
            }
        }
        if let idx = englishFieldIndex(in: fieldNames, fields: fields) { return idx }
        for (index, field) in fields.enumerated() {
            let text = strip(field)
            if !text.isEmpty, looksEnglish(text), !looksChinese(text) {
                return index
            }
        }
        return nil
    }

    static func englishFieldIndex(in fieldNames: [String], fields: [String] = []) -> Int? {
        if let idx = fieldIndex(in: fieldNames, candidates: englishCandidates) { return idx }
        return pairedFieldIndex(
            in: fieldNames,
            fields: fields,
            matching: { looksEnglish($0) && !looksChinese($0) }
        )
    }

    static func chineseFieldIndex(in fieldNames: [String], fields: [String] = []) -> Int? {
        if let idx = fieldIndex(in: fieldNames, candidates: chineseCandidates) { return idx }
        return pairedFieldIndex(
            in: fieldNames,
            fields: fields,
            matching: { looksChinese($0) && !looksEnglish($0) }
        )
    }

    static func translationTargetIndex(
        in fieldNames: [String],
        sourceIndex: Int,
        fields: [String] = []
    ) -> Int? {
        if let idx = fieldIndex(in: fieldNames, candidates: chineseCandidates), idx != sourceIndex {
            return idx
        }

        let normalizedNames = fieldNames.map(normalized)
        if let front = normalizedNames.firstIndex(of: "front"),
           let back = normalizedNames.firstIndex(of: "back"),
           front != back {
            let candidate = sourceIndex == front ? back : front
            if candidate != sourceIndex { return candidate }
        }

        if fields.count == fieldNames.count {
            if fields.count == 2, sourceIndex != 1 - sourceIndex {
                return 1 - sourceIndex
            }
            for (index, field) in fields.enumerated() where index != sourceIndex {
                let name = normalized(fieldNames[index])
                if skipTargetFieldNames.contains(where: { name == $0 || name.contains($0) }) {
                    continue
                }
                if strip(field).isEmpty { return index }
            }
        }
        return nil
    }

    static func lacksChineseTranslation(_ text: String) -> Bool {
        extractChineseTranslation(from: text) == nil
    }

    static func chineseText(for card: AnkiCardSnapshot) -> String? {
        if isPhonemeCard(card) {
            return wordMeaningText(in: card.fields)
        }

        if let sourceIndex = sourceFieldIndex(in: card.fieldNames, fields: card.fields),
           let targetIndex = translationTargetIndex(
               in: card.fieldNames,
               sourceIndex: sourceIndex,
               fields: card.fields
           ),
           card.fields.indices.contains(targetIndex),
           let text = extractChineseTranslation(from: card.fields[targetIndex]) {
            return text
        }

        if let idx = chineseFieldIndex(in: card.fieldNames, fields: card.fields),
           card.fields.indices.contains(idx),
           let text = extractChineseTranslation(from: card.fields[idx]) {
            return text
        }

        let englishIndex = englishFieldIndex(in: card.fieldNames, fields: card.fields)
        for (index, field) in card.fields.enumerated() where index != englishIndex {
            if let text = extractChineseTranslation(from: field) {
                return text
            }
        }
        return nil
    }

    static func shouldEmbedWordMeaning(in html: String) -> Bool {
        if extractStoredWordMeaning(from: html) != nil { return true }
        let plain = strip(html)
        if plain.isEmpty { return false }
        return isPhonemeTeachingContent(plain)
    }

    static func mergeWordMeaning(_ meaning: String, into html: String) -> String {
        let trimmed = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return html }
        let div = "<div class=\"\(wordMeaningDivClass)\">\(escapeHTML(trimmed))</div>"
        let remainder = removingWordMeaningDiv(from: html).trimmingCharacters(in: .whitespacesAndNewlines)
        if remainder.isEmpty { return div }
        return div + "\n" + remainder
    }

    static func isPhonemeCard(_ card: AnkiCardSnapshot) -> Bool {
        PronounceReferenceTargetParser.parse(card: card)?.granularity == .phoneme
    }

    /// Pulls readable Chinese copy from a field that may also contain English or HTML.
    static func extractChineseTranslation(from text: String) -> String? {
        if let stored = extractStoredWordMeaning(from: text) {
            return stored
        }

        let plain = strip(text)
        guard containsCJKIdeograph(plain) else { return nil }
        if isPhonemeTeachingContent(plain) { return nil }

        var segments: [String] = []
        var current = ""
        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if containsCJKIdeograph(trimmed), !isPhonemeTeachingContent(trimmed) {
                segments.append(trimmed)
            }
            current = ""
        }

        for character in plain {
            if containsCJKIdeograph(String(character)) || isCJKPunctuation(character) {
                current.append(character)
            } else if character.isWhitespace {
                if !current.isEmpty { current.append(character) }
            } else {
                flush()
            }
        }
        flush()

        let joined = segments.joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty, !isPhonemeTeachingContent(joined) else { return nil }
        return joined
    }

    static func isPhonemeTeachingContent(_ text: String) -> Bool {
        let plain = strip(text)
        guard containsCJKIdeograph(plain) else { return false }

        let markerHits = phonemeTeachingMarkers.filter { plain.contains($0) }.count
        if markerHits >= 2 { return true }

        if markerHits >= 1,
           plain.range(of: "（[清浊短促]+）", options: .regularExpression) != nil {
            return true
        }

        if plain.range(
            of: "[\\u4e00-\\u9fff]（[清浊短促]+）",
            options: .regularExpression
        ) != nil {
            return true
        }

        return false
    }

    static func containsCJKIdeograph(_ text: String) -> Bool {
        text.unicodeScalars.contains { isCJKIdeograph($0) }
    }

    static func looksChinese(_ text: String) -> Bool {
        containsCJKIdeograph(text)
    }

    static func looksEnglish(_ text: String) -> Bool {
        text.range(of: "[A-Za-z]", options: .regularExpression) != nil
    }

    private static func isCJKIdeograph(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF:
            return true
        default:
            return false
        }
    }

    private static func isCJKPunctuation(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
            return false
        }
        switch scalar.value {
        case 0x3000...0x303F, 0xFF00...0xFFEF:
            return true
        default:
            return false
        }
    }

    private static func pairedFieldIndex(
        in fieldNames: [String],
        fields: [String],
        matching: (String) -> Bool
    ) -> Int? {
        guard fields.count == fieldNames.count else { return nil }
        for name in ["Front", "Back"] {
            guard let idx = fieldNames.firstIndex(where: { normalized($0) == normalized(name) }) else {
                continue
            }
            let text = strip(fields[idx])
            if !text.isEmpty, matching(text) { return idx }
        }
        return nil
    }

    private static func fieldIndex(in fieldNames: [String], candidates: [String]) -> Int? {
        let wanted = candidates.map(normalized)
        for (index, name) in fieldNames.enumerated() {
            let value = normalized(name)
            if wanted.contains(where: { value == $0 || value.contains($0) }) {
                return index
            }
        }
        return nil
    }

    private static func strip(_ html: String) -> String {
        PronounceReferenceTargetParser.stripField(html)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func wordMeaningText(in fields: [String]) -> String? {
        for field in fields {
            if let text = extractStoredWordMeaning(from: field) {
                return text
            }
        }
        return nil
    }

    private static func extractStoredWordMeaning(from html: String) -> String? {
        let pattern = "(?is)<div\\b[^>]*class=\"[^\"]*\\b\(wordMeaningDivClass)\\b[^\"]*\"[^>]*>(.*?)</div>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let inner = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let plain = strip(String(html[inner]))
        return plain.isEmpty ? nil : plain
    }

    static func removingWordMeaningDiv(from html: String) -> String {
        let pattern = "(?is)<div\\b[^>]*class=\"[^\"]*\\b\(wordMeaningDivClass)\\b[^\"]*\"[^>]*>.*?</div>\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        return regex.stringByReplacingMatches(
            in: html,
            range: NSRange(html.startIndex..., in: html),
            withTemplate: ""
        )
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
