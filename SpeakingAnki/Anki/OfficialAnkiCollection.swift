import Foundation
import SaidAnkiBackend

struct OfficialDeckDeletionPreview: Equatable {
    let requestedDeckIDs: [Int64]
    let affectedDeckCount: Int
    let estimatedDeletedCardCount: Int
}

struct OfficialDeckDeletionResult: Equatable {
    let preview: OfficialDeckDeletionPreview
    let deletedCardCount: Int
    let backupCreated: Bool
}

/// Compatibility adapter that keeps the existing UIKit reviewer model while
/// delegating collection, rendering and scheduling to official Anki rslib.
final class OfficialAnkiCollection {
    let rootURL: URL
    let mediaDir: URL
    let backupsDir: URL

    private let backend: RustAnkiBackend
    private let services: SaidAnkiServices
    private var queuedByCardID: [Int64: SaidQueuedCard] = [:]
    private var deckNames: [Int64: String] = [:]
    private var selectedDeckID: Int64?
    private var loadedDeckOptions: [Int64: SaidDeckOptions] = [:]

    init(rootURL: URL) throws {
        self.rootURL = rootURL
        mediaDir = rootURL.appendingPathComponent("collection.media", isDirectory: true)
        backupsDir = rootURL.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: mediaDir,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: backupsDir,
            withIntermediateDirectories: true
        )

        backend = try RustAnkiBackend(preferredLangs: [
            Locale.preferredLanguages.first ?? "en",
            "en"
        ])
        services = SaidAnkiServices(backend: backend)
        try backend.openCollection(
            collectionPath: rootURL.appendingPathComponent("collection.anki2").path,
            mediaFolderPath: mediaDir.path,
            mediaDbPath: rootURL.appendingPathComponent("collection.media.db2").path
        )
        _ = try? services.createBackup(
            folder: backupsDir.path,
            force: false,
            waitForCompletion: false
        )
    }

    deinit {
        try? backend.closeCollection()
    }

    func listDecks() throws -> [AnkiDeckInfo] {
        let tree = try services.deckTree()
        deckNames.removeAll(keepingCapacity: true)
        var decks: [AnkiDeckInfo] = []
        flatten(tree, into: &decks)
        return decks.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func deckTree() throws -> [SaidDeck] {
        let tree = try services.deckTree()
        refreshDeckNameCache(from: tree)
        return tree
    }

    func deckDetail(id: Int64) throws -> SaidDeckDetail {
        try services.deckDetail(id: id)
    }

    @discardableResult
    func createDeck(name: String) throws -> SaidDeckDetail {
        let detail = try services.createDeck(name: name)
        resetCollectionCaches()
        return detail
    }

    func renameDeck(id: Int64, newName: String) throws {
        try services.renameDeck(id: id, newName: newName)
        resetCollectionCaches()
    }

    @discardableResult
    func reparentDecks(ids: [Int64], newParentID: Int64?) throws -> Int {
        let count = try services.reparentDecks(ids: ids, newParentID: newParentID)
        resetCollectionCaches()
        return count
    }

    func deckDeletionPreview(ids: [Int64]) throws -> OfficialDeckDeletionPreview {
        let uniqueIDs = Array(Set(ids))
        let selected = Set(uniqueIDs)
        var affectedDeckCount = 0
        var estimatedDeletedCardCount = 0

        func visit(_ deck: SaidDeck, ancestorSelected: Bool) {
            let selectedHere = selected.contains(deck.id)
            let covered = ancestorSelected || selectedHere
            if covered {
                affectedDeckCount += 1
                if !deck.filtered {
                    estimatedDeletedCardCount += deck.totalInDeck
                }
            }
            for child in deck.children {
                visit(child, ancestorSelected: covered)
            }
        }

        for deck in try services.deckTree() {
            visit(deck, ancestorSelected: false)
        }
        return OfficialDeckDeletionPreview(
            requestedDeckIDs: uniqueIDs.sorted(),
            affectedDeckCount: affectedDeckCount,
            estimatedDeletedCardCount: estimatedDeletedCardCount
        )
    }

    /// rslib deletion is recursive. Normal-deck cards and orphaned notes are
    /// deleted; filtered-deck cards are returned to their original decks.
    /// A forced backup is completed synchronously before the mutation starts.
    @discardableResult
    func deleteDecks(ids: [Int64]) throws -> OfficialDeckDeletionResult {
        let preview = try deckDeletionPreview(ids: ids)
        let backupCreated = try services.createBackup(
            folder: backupsDir.path,
            force: true,
            waitForCompletion: true
        )
        guard backupCreated else {
            throw AnkiError.openFailed("A safety backup could not be created; no decks were deleted.")
        }
        let result = try services.removeDecks(ids: preview.requestedDeckIDs)
        resetCollectionCaches()
        return OfficialDeckDeletionResult(
            preview: preview,
            deletedCardCount: result.deletedCardCount,
            backupCreated: true
        )
    }

    func exportDeck(id: Int64, to url: URL, includeScheduling: Bool = true) throws {
        try services.exportDeck(
            id: id,
            path: url.path,
            includeScheduling: includeScheduling
        )
    }

    func customStudyDefaults(deckID: Int64) throws -> SaidCustomStudyDefaults {
        try services.customStudyDefaults(deckID: deckID)
    }

    func extendDeckLimits(deckID: Int64, newDelta: Int32, reviewDelta: Int32) throws {
        try services.extendLimits(
            deckID: deckID,
            newDelta: newDelta,
            reviewDelta: reviewDelta
        )
        resetCollectionCaches()
    }

    func startCustomStudy(deckID: Int64, mode: SaidCustomStudy) throws {
        try services.customStudy(deckID: deckID, mode: mode)
        resetCollectionCaches()
    }

    func nextCard(deckId: Int64?) throws -> AnkiCardSnapshot? {
        if let deckId = deckId, selectedDeckID != deckId {
            try services.setCurrentDeck(deckId)
            selectedDeckID = deckId
            queuedByCardID.removeAll(keepingCapacity: true)
        }
        let queue = try services.queuedCards(limit: 1)
        guard let card = queue.cards.first else { return nil }
        queuedByCardID[card.cardID] = card

        let rendered = try services.render(cardID: card.cardID)
        let note = try services.note(id: card.noteID)
        let notetype = try services.notetype(id: note.notetypeID)
        if deckNames[card.deckID] == nil {
            _ = try? listDecks()
        }

        return AnkiCardSnapshot(
            cardId: card.cardID,
            noteId: card.noteID,
            deckId: card.deckID,
            deckName: deckNames[card.deckID] ?? "",
            modelName: notetype.name,
            ord: Int(card.templateIndex),
            type: Int(card.cardType),
            queue: Int(card.queue),
            due: Int(card.due),
            ivl: Int(card.interval),
            factor: Int(card.easeFactor),
            reps: Int(card.reps),
            lapses: Int(card.lapses),
            left: Int(card.remainingSteps),
            fields: note.fields,
            fieldNames: notetype.fieldNames,
            frontHTML: wrapHTML(rendered.frontHTML, css: rendered.css),
            backHTML: wrapHTML(rendered.backHTML, css: rendered.css),
            mediaDir: mediaDir,
            nextIntervals: Dictionary(uniqueKeysWithValues: card.nextIntervals.compactMap { rating, value in
                guard let ease = AnkiEase(rawValue: rating.rawValue) else { return nil }
                return (ease, value)
            })
        )
    }

    func answer(cardId: Int64, ease: AnkiEase, timeMs: Int) throws {
        guard let card = queuedByCardID.removeValue(forKey: cardId),
              let rating = SaidRating(rawValue: ease.rawValue) else {
            throw AnkiError.notFound
        }
        try services.answer(
            card,
            rating: rating,
            millisecondsTaken: UInt32(max(0, timeMs))
        )
    }

    func importApkg(from url: URL) throws {
        _ = try services.importAnkiPackage(path: url.path)
        resetCollectionCaches()
    }

    func exportApkg(to url: URL) throws {
        try services.exportAnkiPackage(
            deckID: nil,
            path: url.path,
            includeScheduling: true
        )
    }

    @discardableResult
    func createBackup(force: Bool) throws -> Bool {
        try services.createBackup(
            folder: backupsDir.path,
            force: force,
            waitForCompletion: true
        )
    }

    func restoreCollectionPackage(from url: URL) throws {
        try services.importCollectionPackage(
            path: url.path,
            collectionPath: rootURL.appendingPathComponent("collection.anki2").path,
            mediaFolderPath: mediaDir.path,
            mediaDBPath: rootURL.appendingPathComponent("collection.media.db2").path
        )
        resetCollectionCaches()
        _ = try services.checkDatabase()
    }

    func exportCollectionPackage(to url: URL, includeMedia: Bool) throws {
        try services.exportCollectionPackage(path: url.path, includeMedia: includeMedia)
        resetCollectionCaches()
    }

    @discardableResult
    func importText(from url: URL) throws -> String {
        let result = try services.importCsv(path: url.path)
        resetCollectionCaches()
        return result
    }

    @discardableResult
    func exportNotesText(to url: URL) throws -> UInt32 {
        try services.exportNoteCsv(path: url.path)
    }

    @discardableResult
    func exportCardsText(to url: URL) throws -> UInt32 {
        try services.exportCardCsv(path: url.path)
    }

    func checkDatabase() throws -> [String] {
        let problems = try services.checkDatabase()
        resetCollectionCaches()
        return problems
    }

    func undo() throws {
        try services.undo()
        queuedByCardID.removeAll()
    }

    func browserPage(query: String, offset: Int, limit: Int) throws -> (rows: [BrowserCardRow], total: Int) {
        let ids = try services.searchCards(query)
        let start = min(max(0, offset), ids.count)
        let end = min(start + max(1, limit), ids.count)
        if deckNames.isEmpty { _ = try listDecks() }
        var rows: [BrowserCardRow] = []
        for id in ids[start..<end] {
            let card = try services.card(id: id)
            let note = try services.note(id: card.noteID)
            let notetype = try services.notetype(id: note.notetypeID)
            let rendered = try services.render(cardID: id, browser: true)
            rows.append(BrowserCardRow(
                cardID: id,
                noteID: card.noteID,
                front: plainText(rendered.frontHTML),
                back: plainText(rendered.backHTML),
                deckName: deckNames[card.deckID] ?? "Deck \(card.deckID)",
                templateName: Int(card.templateIndex) < notetype.templateNames.count
                    ? notetype.templateNames[Int(card.templateIndex)] : "Card \(card.templateIndex + 1)",
                dueText: card.queue == -1 ? "Suspended" : (card.queue < -1 ? "Buried" : "Due \(card.due)"),
                isSuspended: card.queue == -1,
                isBuried: card.queue == -2 || card.queue == -3,
                flag: Int(card.flags & 7),
                tags: note.tags
            ))
        }
        return (rows, ids.count)
    }

    func performBrowserAction(_ action: BrowserCardAction, cardIDs: [Int64]) throws {
        switch action {
        case .suspend:
            try services.buryOrSuspend(cardIDs: cardIDs, suspend: true)
        case .bury:
            try services.buryOrSuspend(cardIDs: cardIDs, suspend: false)
        case .flag(let flag):
            try services.setFlag(UInt32(max(0, min(7, flag))), cardIDs: cardIDs)
        case .delete:
            try services.removeNotes(forCardIDs: cardIDs)
        case .move(let deckID):
            try services.moveCards(cardIDs, to: deckID)
        case .addTags(let tags):
            let noteIDs = try cardIDs.map { try services.card(id: $0).noteID }
            try services.addTags(tags, toNoteIDs: Array(Set(noteIDs)))
        }
    }

    func editableNote(id: Int64) throws -> EditableNote {
        let note = try services.note(id: id)
        let notetype = try services.notetype(id: note.notetypeID)
        return EditableNote(
            noteID: id,
            modelName: notetype.name,
            fields: zip(notetype.fieldNames, note.fields).map {
                EditableNoteField(name: $0.0, value: $0.1)
            },
            tags: note.tags
        )
    }

    func saveEditableNote(_ editable: EditableNote) throws {
        var note = try services.note(id: editable.noteID)
        guard note.fields.count == editable.fields.count else {
            throw AnkiError.openFailed("The note type changed while editing.")
        }
        note.fields = editable.fields.map(\.value)
        note.tags = editable.tags
        try services.update(note)
    }

    func deckOptions(id: Int64) throws -> DeckOptions {
        let value = try services.deckOptions(deckID: id)
        loadedDeckOptions[id] = value
        return DeckOptions(
            deckID: id,
            deckName: value.deckName,
            desiredRetention: value.desiredRetention,
            newCardsPerDay: value.newCardsPerDay,
            reviewsPerDay: value.reviewsPerDay,
            buryNewSiblings: value.buryNew,
            buryReviewSiblings: value.buryReviews,
            buryInterdayLearningSiblings: value.buryInterdayLearning
        )
    }

    func saveDeckOptions(_ options: DeckOptions) throws {
        guard let source = loadedDeckOptions[options.deckID] else {
            throw AnkiError.notFound
        }
        try services.updateDeckOptions(
            source,
            desiredRetention: options.desiredRetention,
            newCardsPerDay: options.newCardsPerDay,
            reviewsPerDay: options.reviewsPerDay,
            buryNew: options.buryNewSiblings,
            buryReviews: options.buryReviewSiblings,
            buryInterdayLearning: options.buryInterdayLearningSiblings
        )
        loadedDeckOptions.removeValue(forKey: options.deckID)
    }

    func statistics(days: UInt32, deckID: Int64?) throws -> SaidStatistics {
        let search: String
        if let deckID = deckID {
            let decks = try listDecks()
            guard let deck = decks.first(where: { $0.id == deckID }) else {
                throw AnkiError.notFound
            }
            let escapedName = deck.name
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            search = "deck:\"\(escapedName)\""
        } else {
            search = ""
        }
        return try services.statistics(days: days, search: search)
    }

    func syncLogin(username: String, password: String) throws -> String {
        try services.syncLogin(username: username, password: password)
    }

    func sync(hostKey: String, endpoint: String = "") throws -> SaidSyncResult {
        try services.sync(hostKey: hostKey, endpoint: endpoint)
    }

    func fullSync(hostKey: String, endpoint: String, upload: Bool, serverMediaUSN: Int32) throws {
        try services.fullSync(
            hostKey: hostKey,
            endpoint: endpoint,
            upload: upload,
            serverMediaUSN: serverMediaUSN
        )
    }

    func abortSync() throws {
        try services.abortSync()
    }

    func storeMedia(data: Data, suggestedName: String) throws -> String {
        try services.addMedia(desiredName: suggestedName, data: data)
    }

    private func resetCollectionCaches() {
        queuedByCardID.removeAll()
        deckNames.removeAll()
        selectedDeckID = nil
        loadedDeckOptions.removeAll()
    }

    private func refreshDeckNameCache(from nodes: [SaidDeck]) {
        deckNames.removeAll(keepingCapacity: true)
        func add(_ decks: [SaidDeck]) {
            for deck in decks {
                deckNames[deck.id] = deck.name
                add(deck.children)
            }
        }
        add(nodes)
    }

    /// Adds a scored recording through rslib's media database and writes the
    /// resulting sound tag into an audio/recording field on the source note.
    func attachRecording(_ sourceURL: URL, to card: AnkiCardSnapshot) throws {
        let data = try Data(contentsOf: sourceURL)
        let filename = "said_\(card.noteId)_\(Int(Date().timeIntervalSince1970)).wav"
        let storedName = try services.addMedia(desiredName: filename, data: data)
        var note = try services.note(id: card.noteId)
        guard !note.fields.isEmpty else { return }
        let namedIndex = card.fieldNames.firstIndex {
            let name = $0.lowercased()
            return name.contains("record") || name.contains("audio") || name.contains("录音")
        }
        let index = min(namedIndex ?? (note.fields.count - 1), note.fields.count - 1)
        let soundTag = "[sound:\(storedName)]"
        if !note.fields[index].contains(soundTag) {
            note.fields[index] += note.fields[index].isEmpty ? soundTag : "<br>\(soundTag)"
            try services.update(note)
        }
    }

    private func flatten(_ nodes: [SaidDeck], into output: inout [AnkiDeckInfo]) {
        for node in nodes {
            deckNames[node.id] = node.name
            output.append(AnkiDeckInfo(
                id: node.id,
                name: node.name,
                newCount: node.newCount,
                learnCount: node.learningCount,
                reviewCount: node.reviewCount
            ))
            flatten(node.children, into: &output)
        }
    }

    private func wrapHTML(_ body: String, css: String) -> String {
        """
        <!doctype html>
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style></head><body class="card">\(body)</body></html>
        """
    }

    private func plainText(_ html: String) -> String {
        let withoutTags = html.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        return withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
