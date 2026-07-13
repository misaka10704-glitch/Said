import Foundation

/// Routes cards to Pronounce (Mode A) or Compose (Mode B).
enum ModeRouter {
    static let composeModel = "Speaking Compose"
    static let composeDeckPrefixes = ["English_Speaking::Compose"]

    static let sentenceModels: Set<String> = ["轻听英语 句库", "Speaking Reference"]
    static let phraseModels: Set<String> = ["轻听英语 生词", "Words CET6 Core"]
    static let sentenceDeckPrefixes = ["轻听英语·句库", "Pronounce_Learning::Sentence"]
    static let phraseDeckPrefixes = ["轻听英语·生词本", "Pronounce_Learning::Words", "Pronounce_Learning::Linking"]
    static let pronounceDeckPrefixes = ["Pronounce_Learning"]

    static func mode(for card: AnkiCardSnapshot, deckHint: String? = nil) -> PracticeMode {
        if IELTSSpeakingMode.matches(card: card) { return .ielts }
        if isCompose(card) { return .compose }
        if isPronounce(card, deckHint: deckHint) { return .pronounce }
        if card.deckName.contains("Pronounce") || card.deckName.contains("轻听") {
            return .pronounce
        }
        return .unsupported
    }

    static func isCompose(_ card: AnkiCardSnapshot) -> Bool {
        if card.modelName == composeModel { return true }
        return deckMatches(card.deckName, prefixes: composeDeckPrefixes)
    }

    static func isPronounce(_ card: AnkiCardSnapshot, deckHint: String? = nil) -> Bool {
        if isCompose(card) { return false }
        let model = card.modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if (sentenceModels.union(phraseModels)).contains(where: { $0.lowercased() == model }) {
            return true
        }
        let deckNames = [card.deckName, deckHint].compactMap { $0 }.map(normalizedDeck)
        let leaves = deckNames.compactMap {
            $0.components(separatedBy: "::").last?.lowercased()
        }
        if leaves.contains(where: { $0 == "linking" || $0.hasPrefix("linking ") }) {
            return true
        }
        if model.hasPrefix("basic"), leaves.contains(where: {
            $0.hasPrefix("basic") || ["words", "linking", "sentence"].contains($0)
        }) {
            return true
        }
        return deckNames.contains {
            deckMatches($0, prefixes: pronounceDeckPrefixes + sentenceDeckPrefixes + phraseDeckPrefixes)
                || $0.lowercased().contains("pronounce_learning")
        }
    }

    static func deckMatches(_ name: String, prefixes: [String]) -> Bool {
        let deck = normalizedDeck(name)
        return prefixes.map(normalizedDeck).contains {
            deck == $0 || deck.hasPrefix($0 + "::")
        }
    }

    /// Strip HTML / sound tags — mirrors pronounce_scorer._strip_field.
    static func stripField(_ html: String) -> String {
        var text = html
        if let re = try? NSRegularExpression(pattern: "<[^>]+>") {
            text = re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        if let re = try? NSRegularExpression(pattern: "\\[sound:[^\\]]+\\]") {
            text = re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        if let re = try? NSRegularExpression(pattern: "\\s+") {
            text = re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func audioRoutes(for card: AnkiCardSnapshot, mode: PracticeMode) -> CardAudioRoutes {
        let taggedFields = card.fields.enumerated().map { index, field in
            TaggedAudioField(
                name: index < card.fieldNames.count ? card.fieldNames[index] : "",
                soundNames: soundNames(in: field)
            )
        }
        let renderedNames = soundNames(in: card.frontHTML + "\n" + card.backHTML)
        let explicitlyRecorded = taggedFields
            .filter { isRecordingField($0.name) }
            .flatMap { $0.soundNames }
        let generatedRecordings = unique(
            taggedFields.flatMap { $0.soundNames }.filter(isUserRecordingName)
                + renderedNames.filter(isUserRecordingName)
        )
        let recordingNames = unique(explicitlyRecorded + generatedRecordings).reversed()
        let referenceNames: [String]
        let playbackNames: [String]

        switch mode {
        case .ielts:
            referenceNames = taggedFields
                .filter { isIELTSReferenceField($0.name) }
                .flatMap { $0.soundNames }
                .filter { !isUserRecordingName($0) }
            playbackNames = Array(recordingNames)
        case .pronounce:
            referenceNames = []
            playbackNames = Array(recordingNames)
        case .compose:
            referenceNames = taggedFields
                .filter { isComposeReferenceField($0.name) }
                .flatMap { $0.soundNames }
                .filter { !isUserRecordingName($0) }
            playbackNames = Array(recordingNames)
        case .unsupported:
            referenceNames = renderedNames.filter { !isUserRecordingName($0) }
            playbackNames = Array(recordingNames)
        }

        return CardAudioRoutes(
            reference: mediaURLs(names: unique(referenceNames), card: card),
            playback: mediaURLs(names: unique(playbackNames), card: card)
        )
    }

    static func soundNames(in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "(?i)\\[sound:([^\\]]+)\\]") else {
            return []
        }
        var names: [String] = []
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let raw = decodeEntities(String(html[range]))
            let name = (raw.removingPercentEncoding ?? raw)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != ".", name != "..",
                  !name.contains("/"), !name.contains("\\") else { continue }
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    private struct TaggedAudioField {
        let name: String
        let soundNames: [String]
    }

    private static func mediaURLs(names: [String], card: AnkiCardSnapshot) -> [URL] {
        let base = card.mediaDir.standardizedFileURL
        return names.compactMap { name in
            let url = base.appendingPathComponent(name).standardizedFileURL
            guard url.deletingLastPathComponent() == base,
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }
    }

    private static func isRecordingField(_ name: String) -> Bool {
        let value = normalizedFieldName(name)
        return ["recording", "userrecording", "useraudio", "myaudio", "answerrecording"]
            .contains(value)
            || value.contains("recording")
            || value.contains("录音")
    }

    private static func isUserRecordingName(_ name: String) -> Bool {
        let value = name.lowercased()
        return value.hasPrefix("said_")
            || value.hasPrefix("pronounce_")
            || value.hasPrefix("rec_")
            || value.contains("_recording")
    }

    private static func isIELTSReferenceField(_ name: String) -> Bool {
        let value = normalizedFieldName(name)
        return ["questionaudio", "referenceaudio", "originalaudio", "reference", "original"]
            .contains(value)
            || value.contains("参考音")
            || value.contains("原音")
    }

    private static func isComposeReferenceField(_ name: String) -> Bool {
        let value = normalizedFieldName(name)
        return ["referenceaudio", "originalaudio", "audio", "reference", "original"]
            .contains(value)
            || value.contains("参考音")
            || value.contains("原音")
    }

    private static func normalizedFieldName(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func unique(_ values: [String]) -> [String] {
        values.reduce(into: []) { result, value in
            if !result.contains(value) { result.append(value) }
        }
    }

    private static func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "&quot;", with: "\"", options: .caseInsensitive)
            .replacingOccurrences(of: "&#39;", with: "'", options: .caseInsensitive)
    }

    private static func normalizedDeck(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{1f}", with: "::")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "\\s*::\\s*", with: "::", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CardAudioRoutes {
    let reference: [URL]
    let playback: [URL]
}
