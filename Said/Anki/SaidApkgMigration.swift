import Foundation
import SaidAnkiBackend

enum SaidApkgExportProfile {
    /// Device transfer: scheduling + deck configs, no media, sanitized note fields.
    case deviceMigration
    /// Desktop round-trip: keep fields and include media.
    case desktopSync
}

struct SaidApkgExportOptions {
    let deckID: Int64?
    let profile: SaidApkgExportProfile
    let includeScheduling: Bool

    static func deviceMigration(deckID: Int64? = nil) -> SaidApkgExportOptions {
        SaidApkgExportOptions(
            deckID: deckID,
            profile: .deviceMigration,
            includeScheduling: true
        )
    }

    static func desktopSync(deckID: Int64?, includeScheduling: Bool) -> SaidApkgExportOptions {
        SaidApkgExportOptions(
            deckID: deckID,
            profile: .desktopSync,
            includeScheduling: includeScheduling
        )
    }

    var includeMedia: Bool {
        switch profile {
        case .deviceMigration: return false
        case .desktopSync: return true
        }
    }

    var shouldSanitizeNotes: Bool {
        profile == .deviceMigration
    }
}

struct SaidApkgImportResult: Equatable {
    let newCount: Int
    let updatedCount: Int
    let duplicateCount: Int
    let notesNeedingTranslation: Int
    let notesNeedingAudio: Int

    var formattedMessage: String {
        var lines = [
            "导入完成",
            "新增 \(newCount) · 更新 \(updatedCount) · 重复 \(duplicateCount)",
        ]
        if notesNeedingTranslation > 0 {
            lines.append("待翻译 \(notesNeedingTranslation) 条（可在牌组菜单 → 批量翻译）")
        }
        if notesNeedingAudio > 0 {
            lines.append("待生成音频 \(notesNeedingAudio) 条（可在设置 → Edge TTS 批量生成）")
        }
        return lines.joined(separator: "\n")
    }
}

struct MigrationNoteSnapshot {
    let noteID: Int64
    let fields: [String]
    let tags: [String]
}

enum MigrationNoteSanitizer {
    static func containsSoundTag(_ html: String) -> Bool {
        html.range(of: "(?i)\\[sound:[^\\]]+\\]", options: .regularExpression) != nil
    }

    static func stripSoundTags(in html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(?i)\\[sound:[^\\]]+\\]") else {
            return html
        }
        var result = regex.stringByReplacingMatches(
            in: html,
            range: NSRange(html.startIndex..., in: html),
            withTemplate: ""
        )
        if let brRegex = try? NSRegularExpression(pattern: "(?i)(<br\\s*/?>\\s*){2,}") {
            result = brRegex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "<br>"
            )
        }
        return result
            .replacingOccurrences(of: "<br><br>", with: "<br>")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sanitize(
        note: SaidNote,
        fieldNames: [String]
    ) -> (note: SaidNote, hadTranslation: Bool) {
        var sanitized = note
        var hadTranslation = false

        sanitized.fields = sanitized.fields.map(stripSoundTags(in:))

        if let sourceIndex = NoteFieldMapper.sourceFieldIndex(
            in: fieldNames,
            fields: sanitized.fields
        ),
        let targetIndex = NoteFieldMapper.translationTargetIndex(
            in: fieldNames,
            sourceIndex: sourceIndex,
            fields: sanitized.fields
        ),
        sanitized.fields.indices.contains(targetIndex) {
            let targetField = sanitized.fields[targetIndex]
            if NoteFieldMapper.extractChineseTranslation(from: targetField) != nil
                || NoteFieldMapper.shouldEmbedWordMeaning(in: targetField) {
                hadTranslation = true
                sanitized.fields[targetIndex] = NoteFieldMapper.removingWordMeaningDiv(from: targetField)
                if NoteFieldMapper.extractChineseTranslation(from: sanitized.fields[targetIndex]) != nil
                    || !sanitized.fields[targetIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sanitized.fields[targetIndex] = ""
                }
            }
        } else {
            for index in sanitized.fields.indices {
                let field = sanitized.fields[index]
                if NoteFieldMapper.extractChineseTranslation(from: field) != nil
                    || NoteFieldMapper.shouldEmbedWordMeaning(in: field) {
                    hadTranslation = true
                    sanitized.fields[index] = NoteFieldMapper.removingWordMeaningDiv(from: field)
                    if NoteFieldMapper.extractChineseTranslation(from: sanitized.fields[index]) != nil {
                        sanitized.fields[index] = ""
                    }
                }
            }
        }

        if hadTranslation, !SaidNoteTags.hasNeedsTranslation(sanitized.tags) {
            sanitized.tags.append(SaidNoteTags.needsTranslation)
        }

        return (sanitized, hadTranslation)
    }

    static func sanitizeFields(
        _ fields: [String],
        tags: [String],
        fieldNames: [String]
    ) -> (fields: [String], tags: [String], hadTranslation: Bool) {
        var note = SaidNote(
            id: 0,
            notetypeID: 0,
            fields: fields,
            tags: tags
        )
        let result = sanitize(note: note, fieldNames: fieldNames)
        return (result.note.fields, result.note.tags, result.hadTranslation)
    }
}
