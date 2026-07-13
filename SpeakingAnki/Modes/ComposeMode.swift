import Foundation

/// Mode B — Azure score + Qwen Fix/Better. Ported from speaking_compose / compose_worker text fallback.
enum ComposeMode {
    static func parseKeywords(card: AnkiCardSnapshot) -> [String] {
        if card.fields.count > 5,
           let data = ModeRouter.stripField(card.fields[5]).data(using: .utf8),
           let cues = try? JSONSerialization.jsonObject(with: data) as? [Any],
           !cues.isEmpty {
            let values = cues.compactMap { cue -> String? in
                if let text = cue as? String { return text }
                guard let value = cue as? [String: Any] else { return nil }
                let source = value["text"] as? String ?? ""
                let english = value["en"] as? String ?? ""
                let chinese = value["zh"] as? String ?? ""
                let parts = [source, english, chinese].filter { !$0.isEmpty }
                return parts.isEmpty ? nil : parts.joined(separator: " = ")
            }
            if !values.isEmpty { return values }
        }
        guard let front = card.fields.first else { return [] }
        let stripped = ModeRouter.stripField(front)
        // Keywords often separated by · or spaces / brackets
        let parts = stripped
            .replacingOccurrences(of: "·", with: " ")
            .replacingOccurrences(of: "[", with: " ")
            .replacingOccurrences(of: "]", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
        return parts
    }

    static func lang(card: AnkiCardSnapshot) -> String {
        if card.fields.count > 1 {
            let v = ModeRouter.stripField(card.fields[1]).lowercased()
            if v == "en" || v == "zh" || v == "mixed" { return v }
        }
        if card.deckName.contains("Chinese") { return "zh" }
        if card.deckName.contains("English") { return "en" }
        return "mixed"
    }

    static func qwenPrompt(keywords: [String], lang: String, transcript: String) -> String {
        let kw = keywords.joined(separator: " · ")
        let cue: String
        if lang == "zh" {
            cue = "Keywords (Chinese cues; student must speak English): \(kw)\nSpeak English using all ideas."
        } else {
            cue = "Keywords: \(kw)\nSpeak English using all ideas."
        }
        return """
        \(cue)
        Listen to the attached audio. Azure transcript (may contain errors): \(transcript)
        Reply in exactly 2 short lines:
        Fix: <one main grammar issue, or 'OK' if fine>
        Better: <one improved English sentence using all three ideas>
        Max 40 English words total. No other text.
        """
    }

    static func parseFixBetter(_ text: String) -> (fix: String, better: String) {
        var fix = ""
        var better = ""
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            if lower.hasPrefix("fix:") {
                fix = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("better:") {
                better = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            }
        }
        if fix.isEmpty && better.isEmpty {
            fix = String(text.prefix(120))
        }
        return (fix, better)
    }
}
