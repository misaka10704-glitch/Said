import Foundation
import SQLite3

enum AnkiError: Error, LocalizedError {
    case openFailed(String)
    case sql(String)
    case notFound
    case importFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let s): return "无法打开集合: \(s)"
        case .sql(let s): return "SQL 错误: \(s)"
        case .notFound: return "未找到卡片"
        case .importFailed(let s): return "导入失败: \(s)"
        case .exportFailed(let s): return "导出失败: \(s)"
        }
    }
}

/// Anki collection store: SQLite schema compatible with desktop Anki `.apkg`.
/// Scheduling follows Anki SM-2 (scheduler v2) as used by classic Anki / AnkiDroid.
final class AnkiCollection {
    private(set) var db: OpaquePointer?
    let rootURL: URL
    let collectionURL: URL
    let mediaURL: URL

    private var modelsJSON: [String: Any] = [:]
    private var decksJSON: [String: Any] = [:]
    private var confJSON: [String: Any] = [:]

    init(rootURL: URL) {
        self.rootURL = rootURL
        self.collectionURL = rootURL.appendingPathComponent("collection.anki2")
        self.mediaURL = rootURL.appendingPathComponent("collection.media")
    }

    deinit {
        close()
    }

    func close() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    func open() throws {
        if db != nil { return }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        if sqlite3_open(collectionURL.path, &db) != SQLITE_OK {
            throw AnkiError.openFailed(String(cString: sqlite3_errmsg(db)))
        }
        try exec("PRAGMA foreign_keys=ON;")
        try loadMeta()
    }

    // MARK: - Import / Export

    func importApkg(from apkgURL: URL) throws {
        close()
        let fm = FileManager.default
        if fm.fileExists(atPath: rootURL.path) {
            try fm.removeItem(at: rootURL)
        }
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let staging = rootURL.appendingPathComponent("_import_staging", isDirectory: true)
        try SimpleZip.unzip(archiveURL: apkgURL, to: staging)

        let candidates = ["collection.anki2", "collection.anki21"]
        var foundDB: URL?
        for name in candidates {
            let u = staging.appendingPathComponent(name)
            if fm.fileExists(atPath: u.path) {
                foundDB = u
                break
            }
        }
        guard let dbURL = foundDB else {
            throw AnkiError.importFailed("apkg 中未找到 collection.anki2")
        }
        let destDB = rootURL.appendingPathComponent("collection.anki2")
        try fm.copyItem(at: dbURL, to: destDB)

        // media map: {"0":"foo.mp3", ...} plus numbered files
        let mediaMapURL = staging.appendingPathComponent("media")
        try fm.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        if fm.fileExists(atPath: mediaMapURL.path),
           let mapData = try? Data(contentsOf: mediaMapURL),
           let map = try? JSONSerialization.jsonObject(with: mapData) as? [String: String] {
            for (num, filename) in map {
                let src = staging.appendingPathComponent(num)
                let dst = mediaURL.appendingPathComponent(filename)
                if fm.fileExists(atPath: src.path) {
                    if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                    try fm.copyItem(at: src, to: dst)
                }
            }
        } else {
            // Fallback: copy any loose media-like files
            if let items = try? fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) {
                for item in items {
                    let name = item.lastPathComponent
                    if name == "collection.anki2" || name == "collection.anki21" || name == "media" { continue }
                    if name.hasPrefix("_") { continue }
                    let dst = mediaURL.appendingPathComponent(name)
                    if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
                    try? fm.copyItem(at: item, to: dst)
                }
            }
        }

        try? fm.removeItem(at: staging)
        try open()
    }

    func exportApkg(to apkgURL: URL) throws {
        guard db != nil else { throw AnkiError.exportFailed("集合未打开") }
        sqlite3_close(db)
        db = nil

        let staging = rootURL.appendingPathComponent("_export_staging", isDirectory: true)
        let fm = FileManager.default
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try fm.copyItem(at: collectionURL, to: staging.appendingPathComponent("collection.anki2"))

        var mediaMap: [String: String] = [:]
        if let files = try? fm.contentsOfDirectory(at: mediaURL, includingPropertiesForKeys: nil) {
            var idx = 0
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = file.lastPathComponent
                if name.hasPrefix(".") { continue }
                let num = String(idx)
                try fm.copyItem(at: file, to: staging.appendingPathComponent(num))
                mediaMap[num] = name
                idx += 1
            }
        }
        let mapData = try JSONSerialization.data(withJSONObject: mediaMap, options: [])
        try mapData.write(to: staging.appendingPathComponent("media"))

        if fm.fileExists(atPath: apkgURL.path) {
            try fm.removeItem(at: apkgURL)
        }
        try SimpleZip.zip(directory: staging, to: apkgURL)
        try? fm.removeItem(at: staging)
        try open()
    }

    // MARK: - Decks / Study

    func listDecks() throws -> [AnkiDeckInfo] {
        try loadMeta()
        var result: [AnkiDeckInfo] = []
        let sorted = decksJSON.keys.compactMap { Int64($0) }.sorted()
        for did in sorted {
            guard let deck = decksJSON[String(did)] as? [String: Any] else { continue }
            let name = deck["name"] as? String ?? "Deck"
            if name == "Default" && sorted.count > 1 {
                // keep Default if it has cards
            }
            let counts = try counts(forDeckId: did)
            result.append(AnkiDeckInfo(
                id: did,
                name: name,
                newCount: counts.new,
                learnCount: counts.learn,
                reviewCount: counts.review
            ))
        }
        return result.filter { $0.name != "Default" || $0.dueTotal > 0 || result.count == 1 }
    }

    func nextCard(deckId: Int64?) throws -> AnkiCardSnapshot? {
        let today = daysSinceCreation()
        // learn / day-learn first, then review, then new
        if let cid = try firstCardId(sql: """
            SELECT id FROM cards WHERE queue IN (1,3)
            \(deckFilter(deckId))
            ORDER BY due ASC LIMIT 1
            """) {
            return try loadCard(cardId: cid)
        }
        if let cid = try firstCardId(sql: """
            SELECT id FROM cards WHERE queue = 2 AND due <= \(today)
            \(deckFilter(deckId))
            ORDER BY due ASC LIMIT 1
            """) {
            return try loadCard(cardId: cid)
        }
        if let cid = try firstCardId(sql: """
            SELECT id FROM cards WHERE queue = 0
            \(deckFilter(deckId))
            ORDER BY due ASC LIMIT 1
            """) {
            return try loadCard(cardId: cid)
        }
        return nil
    }

    func answer(cardId: Int64, ease: AnkiEase, timeMs: Int = 5000) throws {
        guard var card = try loadRawCard(cardId: cardId) else { throw AnkiError.notFound }
        let conf = deckConfig(for: card.did)
        let updated = AnkiScheduler.answer(
            card: card,
            ease: ease,
            conf: conf,
            today: daysSinceCreation(),
            nowSec: Int(Date().timeIntervalSince1970)
        )
        try writeCard(updated)
        try insertRevlog(
            cardId: cardId,
            ease: ease.rawValue,
            ivl: updated.ivl,
            lastIvl: card.ivl,
            factor: updated.factor,
            timeMs: timeMs,
            type: updated.type
        )
        try bumpMod()
    }

    // MARK: - Card loading

    func loadCard(cardId: Int64) throws -> AnkiCardSnapshot {
        guard let raw = try loadRawCard(cardId: cardId) else { throw AnkiError.notFound }
        let note = try loadNote(noteId: raw.nid)
        let model = modelsJSON[String(note.mid)] as? [String: Any] ?? [:]
        let modelName = model["name"] as? String ?? ""
        let fieldNames = ((model["flds"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
        let tmpls = (model["tmpls"] as? [[String: Any]]) ?? []
        let tmpl = tmpls.indices.contains(raw.ord) ? tmpls[raw.ord] : tmpls.first
        let qfmt = tmpl?["qfmt"] as? String ?? "{{Front}}"
        let afmt = tmpl?["afmt"] as? String ?? "{{FrontSide}}<hr>{{Back}}"
        let fields = note.flds.components(separatedBy: "\u{1f}")
        let deckName = (decksJSON[String(raw.did)] as? [String: Any])?["name"] as? String ?? ""

        let front = renderTemplate(qfmt, fields: fields, fieldNames: fieldNames, css: model["css"] as? String)
        let back = renderTemplate(afmt, fields: fields, fieldNames: fieldNames, css: model["css"] as? String, frontHTML: front)

        return AnkiCardSnapshot(
            cardId: raw.id,
            noteId: raw.nid,
            deckId: raw.did,
            deckName: deckName,
            modelName: modelName,
            ord: raw.ord,
            type: raw.type,
            queue: raw.queue,
            due: raw.due,
            ivl: raw.ivl,
            factor: raw.factor,
            reps: raw.reps,
            lapses: raw.lapses,
            left: raw.left,
            fields: fields,
            fieldNames: fieldNames,
            frontHTML: wrapHTML(front, css: model["css"] as? String),
            backHTML: wrapHTML(back, css: model["css"] as? String),
            mediaDir: mediaURL,
            nextIntervals: [:]
        )
    }

    // MARK: - Internals

    struct RawCard {
        var id: Int64
        var nid: Int64
        var did: Int64
        var ord: Int
        var mod: Int
        var type: Int
        var queue: Int
        var due: Int
        var ivl: Int
        var factor: Int
        var reps: Int
        var lapses: Int
        var left: Int
        var odue: Int
        var odid: Int64
    }

    struct RawNote {
        var id: Int64
        var mid: Int64
        var flds: String
    }

    private func loadMeta() throws {
        confJSON = try jsonDict(fromColumn: "conf")
        modelsJSON = try jsonDict(fromColumn: "models")
        decksJSON = try jsonDict(fromColumn: "decks")
    }

    private func jsonDict(fromColumn column: String) throws -> [String: Any] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT \(column) FROM col LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw AnkiError.sql(String(cString: sqlite3_errmsg(db)))
        }
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let cstr = sqlite3_column_text(stmt, 0) else {
            return [:]
        }
        let text = String(cString: cstr)
        guard let data = text.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    private func daysSinceCreation() -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        sqlite3_prepare_v2(db, "SELECT crt FROM col LIMIT 1", -1, &stmt, nil)
        var crt: Int64 = Int64(Date().timeIntervalSince1970)
        if sqlite3_step(stmt) == SQLITE_ROW {
            crt = sqlite3_column_int64(stmt, 0)
        }
        let now = Int64(Date().timeIntervalSince1970)
        return Int(max(0, (now - crt) / 86_400))
    }

    private func deckFilter(_ deckId: Int64?) -> String {
        guard let deckId = deckId else { return "" }
        // include children by name prefix
        guard let parent = decksJSON[String(deckId)] as? [String: Any],
              let parentName = parent["name"] as? String else {
            return " AND did = \(deckId)"
        }
        var ids: [Int64] = [deckId]
        for (k, v) in decksJSON {
            guard let id = Int64(k), let deck = v as? [String: Any], let name = deck["name"] as? String else { continue }
            if name.hasPrefix(parentName + "::") {
                ids.append(id)
            }
        }
        return " AND did IN (\(ids.map(String.init).joined(separator: ",")))"
    }

    private func counts(forDeckId did: Int64) throws -> (new: Int, learn: Int, review: Int) {
        let today = daysSinceCreation()
        let filter = deckFilter(did)
        let newC = try scalar("SELECT COUNT(*) FROM cards WHERE queue = 0 \(filter)")
        let learnC = try scalar("SELECT COUNT(*) FROM cards WHERE queue IN (1,3) \(filter)")
        let reviewC = try scalar("SELECT COUNT(*) FROM cards WHERE queue = 2 AND due <= \(today) \(filter)")
        return (newC, learnC, reviewC)
    }

    private func scalar(_ sql: String) throws -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw AnkiError.sql(String(cString: sqlite3_errmsg(db)))
        }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return 0
    }

    private func firstCardId(sql: String) throws -> Int64? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw AnkiError.sql(String(cString: sqlite3_errmsg(db)))
        }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int64(stmt, 0)
        }
        return nil
    }

    private func loadRawCard(cardId: Int64) throws -> RawCard? {
        let sql = """
        SELECT id,nid,did,ord,mod,type,queue,due,ivl,factor,reps,lapses,left,odue,odid
        FROM cards WHERE id = ?
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw AnkiError.sql(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_int64(stmt, 1, cardId)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return RawCard(
            id: sqlite3_column_int64(stmt, 0),
            nid: sqlite3_column_int64(stmt, 1),
            did: sqlite3_column_int64(stmt, 2),
            ord: Int(sqlite3_column_int(stmt, 3)),
            mod: Int(sqlite3_column_int(stmt, 4)),
            type: Int(sqlite3_column_int(stmt, 5)),
            queue: Int(sqlite3_column_int(stmt, 6)),
            due: Int(sqlite3_column_int(stmt, 7)),
            ivl: Int(sqlite3_column_int(stmt, 8)),
            factor: Int(sqlite3_column_int(stmt, 9)),
            reps: Int(sqlite3_column_int(stmt, 10)),
            lapses: Int(sqlite3_column_int(stmt, 11)),
            left: Int(sqlite3_column_int(stmt, 12)),
            odue: Int(sqlite3_column_int(stmt, 13)),
            odid: sqlite3_column_int64(stmt, 14)
        )
    }

    private func loadNote(noteId: Int64) throws -> RawNote {
        let sql = "SELECT id, mid, flds FROM notes WHERE id = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw AnkiError.sql(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_int64(stmt, 1, noteId)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let flds = sqlite3_column_text(stmt, 2) else {
            throw AnkiError.notFound
        }
        return RawNote(
            id: sqlite3_column_int64(stmt, 0),
            mid: sqlite3_column_int64(stmt, 1),
            flds: String(cString: flds)
        )
    }

    private func writeCard(_ c: RawCard) throws {
        let sql = """
        UPDATE cards SET mod=?, type=?, queue=?, due=?, ivl=?, factor=?, reps=?, lapses=?, left=?, odue=?, odid=?
        WHERE id=?
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw AnkiError.sql(String(cString: sqlite3_errmsg(db)))
        }
        let mod = Int(Date().timeIntervalSince1970)
        sqlite3_bind_int(stmt, 1, Int32(mod))
        sqlite3_bind_int(stmt, 2, Int32(c.type))
        sqlite3_bind_int(stmt, 3, Int32(c.queue))
        sqlite3_bind_int(stmt, 4, Int32(c.due))
        sqlite3_bind_int(stmt, 5, Int32(c.ivl))
        sqlite3_bind_int(stmt, 6, Int32(c.factor))
        sqlite3_bind_int(stmt, 7, Int32(c.reps))
        sqlite3_bind_int(stmt, 8, Int32(c.lapses))
        sqlite3_bind_int(stmt, 9, Int32(c.left))
        sqlite3_bind_int(stmt, 10, Int32(c.odue))
        sqlite3_bind_int64(stmt, 11, c.odid)
        sqlite3_bind_int64(stmt, 12, c.id)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw AnkiError.sql(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func insertRevlog(cardId: Int64, ease: Int, ivl: Int, lastIvl: Int, factor: Int, timeMs: Int, type: Int) throws {
        let id = Int64(Date().timeIntervalSince1970 * 1000)
        // revlog.type: 0=learn, 1=review, 2=relearn, 3=filtered
        let revType: Int32
        switch type {
        case 0: revType = 0
        case 1: revType = 0
        case 3: revType = 2
        default: revType = 1
        }
        let sql = "INSERT INTO revlog (id,cid,usn,ease,ivl,lastIvl,factor,time,type) VALUES (?,?,?,?,?,?,?,?,?)"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw AnkiError.sql(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_int64(stmt, 1, id)
        sqlite3_bind_int64(stmt, 2, cardId)
        sqlite3_bind_int(stmt, 3, -1)
        sqlite3_bind_int(stmt, 4, Int32(ease))
        sqlite3_bind_int(stmt, 5, Int32(ivl))
        sqlite3_bind_int(stmt, 6, Int32(lastIvl))
        sqlite3_bind_int(stmt, 7, Int32(factor))
        sqlite3_bind_int(stmt, 8, Int32(timeMs))
        sqlite3_bind_int(stmt, 9, revType)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw AnkiError.sql(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func bumpMod() throws {
        try exec("UPDATE col SET mod = \(Int(Date().timeIntervalSince1970)), usn = -1")
    }

    private func deckConfig(for did: Int64) -> AnkiScheduler.Config {
        let deck = decksJSON[String(did)] as? [String: Any]
        let confId = deck?["conf"] as? Int ?? 1
        let dconfAll = (try? jsonDict(fromColumn: "dconf")) ?? [:]
        let conf = dconfAll[String(confId)] as? [String: Any]
        let new = conf?["new"] as? [String: Any]
        let rev = conf?["rev"] as? [String: Any]
        let delays = (new?["delays"] as? [Double]) ?? [1, 10]
        let ints = (new?["ints"] as? [Int]) ?? [1, 4, 0]
        return AnkiScheduler.Config(
            learningStepsMin: delays,
            graduatingIvl: ints.indices.contains(0) ? ints[0] : 1,
            easyIvl: ints.indices.contains(1) ? ints[1] : 4,
            startingEase: Int((new?["initialFactor"] as? Int) ?? 2500),
            easyBonus: (rev?["ease4"] as? Double) ?? 1.3,
            intervalModifier: (rev?["ivlFct"] as? Double) ?? 1.0,
            maxInterval: (rev?["maxIvl"] as? Int) ?? 36500,
            hardFactor: (rev?["hardFactor"] as? Double) ?? 1.2
        )
    }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw AnkiError.sql(msg)
        }
    }

    private func renderTemplate(
        _ fmt: String,
        fields: [String],
        fieldNames: [String],
        css: String?,
        frontHTML: String = ""
    ) -> String {
        var out = fmt
        out = out.replacingOccurrences(of: "{{FrontSide}}", with: frontHTML)
        for (i, name) in fieldNames.enumerated() {
            let value = i < fields.count ? fields[i] : ""
            out = out.replacingOccurrences(of: "{{\(name)}}", with: value)
            // cloze / conditional simplified: strip {{#Name}}...{{/Name}} if empty
            let openTag = "{{#" + name + "}}"
            let closeTag = "{{/" + name + "}}"
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let pattern = NSRegularExpression.escapedPattern(for: openTag)
                    + "[\\s\\S]*?"
                    + NSRegularExpression.escapedPattern(for: closeTag)
                if let re = try? NSRegularExpression(pattern: pattern),
                   let match = re.firstMatch(in: out, range: NSRange(out.startIndex..., in: out)),
                   let range = Range(match.range, in: out) {
                    out.replaceSubrange(range, with: "")
                }
            } else {
                out = out.replacingOccurrences(of: openTag, with: "")
                out = out.replacingOccurrences(of: closeTag, with: "")
            }
        }
        // remove remaining {{...}} tags lightly
        if let regex = try? NSRegularExpression(pattern: "\\{\\{[^}]+\\}\\}") {
            out = regex.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
        }
        return out
    }

    private func wrapHTML(_ body: String, css: String?) -> String {
        let style = css ?? "body{font-family:-apple-system;font-size:22px;padding:16px;}"
        return """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(style)</style></head><body>\(body)</body></html>
        """
    }
}
