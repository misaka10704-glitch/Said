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

struct TranslationNoteCandidate: Equatable {
    let noteID: Int64
    let sourceText: String
    let targetFieldIndex: Int
}

struct DeckTranslationSummary: Equatable {
    let total: Int
    let missing: Int
}

/// Compatibility adapter that keeps the existing UIKit reviewer model while
/// delegating collection, rendering and scheduling to official Anki rslib.
final class OfficialAnkiCollection {
    let rootURL: URL
    let mediaDir: URL
    let backupsDir: URL

    private let backend: RustAnkiBackend
    private let services: SaidAnkiServices
    private let queuedCardsLock = NSLock()
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
        try exportApkg(
            to: url,
            options: .desktopSync(deckID: id, includeScheduling: includeScheduling)
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

    /// Limit extensions keep studying in the source deck. Other custom-study
    /// modes create or reuse rslib's localized filtered deck and return its ID.
    func startCustomStudy(deckID: Int64, mode: SaidCustomStudy) throws -> Int64? {
        let createsFilteredDeck: Bool
        switch mode {
        case .increaseNewLimit, .increaseReviewLimit:
            createsFilteredDeck = false
        case .forgotten, .reviewAhead, .previewNew, .cram:
            createsFilteredDeck = true
        }
        let before = createsFilteredDeck ? try filteredDecksByID() : [:]
        try services.customStudy(deckID: deckID, mode: mode)
        resetCollectionCaches()
        guard createsFilteredDeck else { return nil }

        let after = try filteredDecksByID()
        let created = after.keys.filter { before[$0] == nil }
        if created.count == 1 { return created[0] }
        let changed = after.keys.filter { id in
            guard let previous = before[id], let current = after[id] else { return false }
            return previous != current
        }
        if changed.count == 1 { return changed[0] }
        if after.count == 1 { return after.keys.first }
        throw AnkiError.openFailed(
            "自定义学习已创建，但无法可靠确定对应的筛选牌组。请返回牌组列表后手动打开筛选牌组。"
        )
    }

    func emptyFilteredDeck(id: Int64) throws {
        try services.emptyFilteredDeck(deckID: id)
        resetCollectionCaches()
    }

    @discardableResult
    func rebuildFilteredDeck(id: Int64) throws -> Int {
        let count = try services.rebuildFilteredDeck(deckID: id)
        resetCollectionCaches()
        return count
    }

    func nextCard(deckId: Int64?) throws -> AnkiCardSnapshot? {
        if let deckId = deckId, selectedDeckID != deckId {
            try services.setCurrentDeck(deckId)
            selectedDeckID = deckId
            withQueuedCardsLock {
                queuedByCardID.removeAll(keepingCapacity: true)
            }
        }
        let queue = try services.queuedCards(limit: 1)
        guard let card = queue.cards.first else { return nil }
        withQueuedCardsLock {
            queuedByCardID[card.cardID] = card
        }

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
        guard let card = withQueuedCardsLock({ queuedByCardID[cardId] }),
              let rating = SaidRating(rawValue: ease.rawValue) else {
            throw AnkiError.notFound
        }
        try services.answer(
            card,
            rating: rating,
            millisecondsTaken: UInt32(clamping: max(0, timeMs))
        )
        withQueuedCardsLock {
            queuedByCardID.removeValue(forKey: cardId)
        }
    }

    @discardableResult
    func importApkg(from url: URL) throws -> SaidApkgImportResult {
        let response = try services.importAnkiPackage(path: url.path)
        resetCollectionCaches()
        return SaidApkgImportResult(
            newCount: Int(response.log.new.count),
            updatedCount: Int(response.log.updated.count),
            duplicateCount: Int(response.log.duplicate.count),
            notesNeedingTranslation: try countNotesNeedingTranslation(),
            notesNeedingAudio: try countNotesNeedingReferenceAudio()
        )
    }

    func exportApkg(to url: URL) throws {
        try exportApkg(to: url, options: .deviceMigration())
    }

    func exportApkg(to url: URL, options: SaidApkgExportOptions) throws {
        var snapshots: [MigrationNoteSnapshot] = []
        if options.shouldSanitizeNotes {
            snapshots = try applyMigrationSanitization(for: options.deckID)
        }
        defer {
            if !snapshots.isEmpty {
                try? restoreMigrationSnapshots(snapshots)
            }
        }
        try services.exportAnkiPackage(
            deckID: options.deckID,
            path: url.path,
            includeScheduling: options.includeScheduling,
            includeMedia: options.includeMedia
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
        withQueuedCardsLock {
            queuedByCardID.removeAll()
        }
    }

    func canUndo() throws -> Bool {
        try services.canUndo()
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

    func addTags(_ tags: [String], toNoteID noteID: Int64) throws {
        let normalized = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return }
        try services.addTags(normalized, toNoteIDs: [noteID])
    }

    func noteTypes(inDeck deckID: Int64) throws -> [SaidNotetype] {
        let decks = try listDecks()
        guard let deck = decks.first(where: { $0.id == deckID }) else {
            throw AnkiError.notFound
        }
        let escapedName = deck.name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let cardIDs = try services.searchCards("deck:\"\(escapedName)\"")
        var seen = Set<Int64>()
        var types: [SaidNotetype] = []
        for cardID in cardIDs {
            let note = try services.note(id: services.card(id: cardID).noteID)
            guard seen.insert(note.notetypeID).inserted else { continue }
            types.append(try services.notetype(id: note.notetypeID))
        }
        return types.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Reusable templates are collection-wide in Anki. A target subdeck may be
    /// empty, so it must not prevent users from selecting the existing Words
    /// (or any other) note type stored elsewhere in the collection.
    func allNoteTypes() throws -> [SaidNotetype] {
        let cardIDs = try services.searchCards("")
        var seen = Set<Int64>()
        var types: [SaidNotetype] = []
        for cardID in cardIDs {
            let note = try services.note(id: services.card(id: cardID).noteID)
            guard seen.insert(note.notetypeID).inserted else { continue }
            types.append(try services.notetype(id: note.notetypeID))
        }
        return types.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func translationSummary(inDeck deckID: Int64) throws -> DeckTranslationSummary {
        let noteIDs = try taggedNoteIDs(inDeck: deckID)
        var pending = 0
        for noteID in noteIDs {
            if try translationCandidate(noteID: noteID) != nil {
                pending += 1
            }
        }
        return DeckTranslationSummary(total: noteIDs.count, missing: pending)
    }

    func translationCandidates(inDeck deckID: Int64) throws -> [TranslationNoteCandidate] {
        try taggedNoteIDs(inDeck: deckID).compactMap { try translationCandidate(noteID: $0) }
    }

    func applyTranslation(noteID: Int64, targetFieldIndex: Int, translation: String) throws {
        var note = try services.note(id: noteID)
        guard note.fields.indices.contains(targetFieldIndex) else {
            throw AnkiError.openFailed("Translation field is no longer available.")
        }
        let trimmed = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        if NoteFieldMapper.shouldEmbedWordMeaning(in: note.fields[targetFieldIndex]) {
            note.fields[targetFieldIndex] = NoteFieldMapper.mergeWordMeaning(
                trimmed,
                into: note.fields[targetFieldIndex]
            )
        } else {
            note.fields[targetFieldIndex] = trimmed
        }
        note.tags = SaidNoteTags.removingNeedsTranslation(from: note.tags)
        try services.update(note)
    }

    private func translationCandidate(noteID: Int64) throws -> TranslationNoteCandidate? {
        let note = try services.note(id: noteID)
        guard SaidNoteTags.hasNeedsTranslation(note.tags) else { return nil }
        let type = try services.notetype(id: note.notetypeID)
        guard
            let sourceIndex = NoteFieldMapper.sourceFieldIndex(
                in: type.fieldNames,
                fields: note.fields
            ),
            let targetIndex = NoteFieldMapper.translationTargetIndex(
                in: type.fieldNames,
                sourceIndex: sourceIndex,
                fields: note.fields
            ),
            sourceIndex != targetIndex,
            sourceIndex < note.fields.count,
            targetIndex < note.fields.count
        else { return nil }

        let sourcePlain = PronounceReferenceTargetParser.stripField(note.fields[sourceIndex])
        guard !sourcePlain.isEmpty else { return nil }
        guard NoteFieldMapper.lacksChineseTranslation(note.fields[targetIndex]) else { return nil }
        return TranslationNoteCandidate(
            noteID: noteID,
            sourceText: sourcePlain,
            targetFieldIndex: targetIndex
        )
    }

    private func taggedNoteIDs(inDeck deckID: Int64) throws -> [Int64] {
        let deckIDs = try descendantDeckIDs(for: deckID)
        var noteIDs = Set<Int64>()

        for query in [
            "tag:trans",
            "tag:said::needs_translation",
            "tag:needs_translation",
        ] {
            for noteID in try services.searchNotes(query) {
                if try noteIsInDeckTree(noteID, deckIDs: deckIDs) {
                    noteIDs.insert(noteID)
                }
            }
        }

        for cardID in try cardIDs(inDeck: deckID) {
            let noteID = try services.card(id: cardID).noteID
            let note = try services.note(id: noteID)
            if SaidNoteTags.hasNeedsTranslation(note.tags) {
                noteIDs.insert(noteID)
            }
        }

        return noteIDs.sorted()
    }

    private func descendantDeckIDs(for deckID: Int64) throws -> Set<Int64> {
        let tree = try services.deckTree()
        guard let ids = findDescendantDeckIDs(rootID: deckID, in: tree) else {
            throw AnkiError.notFound
        }
        return ids
    }

    private func findDescendantDeckIDs(rootID: Int64, in nodes: [SaidDeck]) -> Set<Int64>? {
        for node in nodes {
            if node.id == rootID {
                var ids: Set<Int64> = [node.id]
                collectDescendantDeckIDs(from: node.children, into: &ids)
                return ids
            }
            if let found = findDescendantDeckIDs(rootID: rootID, in: node.children) {
                return found
            }
        }
        return nil
    }

    private func collectDescendantDeckIDs(from nodes: [SaidDeck], into ids: inout Set<Int64>) {
        for node in nodes {
            ids.insert(node.id)
            collectDescendantDeckIDs(from: node.children, into: &ids)
        }
    }

    private func noteIsInDeckTree(_ noteID: Int64, deckIDs: Set<Int64>) throws -> Bool {
        for cardID in try services.searchCards("nid:\(noteID)") {
            if deckIDs.contains(try services.card(id: cardID).deckID) {
                return true
            }
        }
        return false
    }

    func referenceTexts(inDeck deckID: Int64) throws -> [String] {
        let cardIDs = try cardIDs(inDeck: deckID)
        var seen = Set<String>()
        var results: [String] = []
        for cardID in cardIDs {
            let note = try services.note(id: services.card(id: cardID).noteID)
            let type = try services.notetype(id: note.notetypeID)
            let pairs = Dictionary(uniqueKeysWithValues: zip(type.fieldNames, note.fields))
            let text = ["English", "Sentence", "Text", "Phrase", "Word", "Front"]
                .compactMap { pairs[$0] }
                .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                ?? note.fields.first
                ?? ""
            let plain = plainText(text).trimmingCharacters(in: .whitespacesAndNewlines)
            if !plain.isEmpty, seen.insert(plain).inserted {
                results.append(plain)
            }
        }
        return results
    }

    @discardableResult
    func addNote(
        deckID: Int64,
        notetypeID: Int64,
        fields: [String],
        tags: [String]
    ) throws -> Int64 {
        let noteID = try services.addNote(
            notetypeID: notetypeID,
            deckID: deckID,
            fields: fields,
            tags: tags
        )
        if !tags.isEmpty {
            try services.addTags(tags, toNoteIDs: [noteID])
        }
        resetCollectionCaches()
        return noteID
    }

    func deckOptions(id: Int64) throws -> DeckOptions {
        let value = try services.deckOptions(deckID: id)
        loadedDeckOptions[id] = value
        return DeckOptions(
            deckID: id,
            deckName: value.deckName,
            presetName: value.presetName,
            presetUseCount: value.presetUseCount,
            configID: value.configID,
            fsrsEnabled: value.fsrsEnabled,
            desiredRetention: value.desiredRetention,
            desiredRetentionIsOverride: value.desiredRetentionIsOverride,
            presetNewCardsPerDay: value.presetNewCardsPerDay,
            presetReviewsPerDay: value.presetReviewsPerDay,
            deckNewCardsPerDay: value.deckNewCardsPerDay,
            deckReviewsPerDay: value.deckReviewsPerDay,
            todayNewCardsPerDay: value.todayNewCardsPerDay,
            todayReviewsPerDay: value.todayReviewsPerDay,
            learnSteps: value.learnSteps,
            graduatingIntervalGood: value.graduatingIntervalGood,
            graduatingIntervalEasy: value.graduatingIntervalEasy,
            relearnSteps: value.relearnSteps,
            minimumLapseInterval: value.minimumLapseInterval,
            leechThreshold: value.leechThreshold,
            leechAction: value.leechAction,
            maximumReviewInterval: value.maximumReviewInterval,
            historicalRetention: value.historicalRetention,
            newCardInsertOrder: value.newCardInsertOrder,
            newCardGatherPriority: value.newCardGatherPriority,
            newCardSortOrder: value.newCardSortOrder,
            newMix: value.newMix,
            interdayLearningMix: value.interdayLearningMix,
            reviewOrder: value.reviewOrder,
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
            desiredRetentionIsOverride: options.desiredRetentionIsOverride,
            presetNewCardsPerDay: options.presetNewCardsPerDay,
            presetReviewsPerDay: options.presetReviewsPerDay,
            deckNewCardsPerDay: options.deckNewCardsPerDay,
            deckReviewsPerDay: options.deckReviewsPerDay,
            todayNewCardsPerDay: options.todayNewCardsPerDay,
            todayReviewsPerDay: options.todayReviewsPerDay,
            learnSteps: options.learnSteps,
            graduatingIntervalGood: options.graduatingIntervalGood,
            graduatingIntervalEasy: options.graduatingIntervalEasy,
            relearnSteps: options.relearnSteps,
            minimumLapseInterval: options.minimumLapseInterval,
            leechThreshold: options.leechThreshold,
            leechAction: options.leechAction,
            maximumReviewInterval: options.maximumReviewInterval,
            historicalRetention: options.historicalRetention,
            newCardInsertOrder: options.newCardInsertOrder,
            newCardGatherPriority: options.newCardGatherPriority,
            newCardSortOrder: options.newCardSortOrder,
            newMix: options.newMix,
            interdayLearningMix: options.interdayLearningMix,
            reviewOrder: options.reviewOrder,
            buryNew: options.buryNewSiblings,
            buryReviews: options.buryReviewSiblings,
            buryInterdayLearning: options.buryInterdayLearningSiblings
        )
        loadedDeckOptions.removeValue(forKey: options.deckID)
    }

    func deckPresets(for deckID: Int64) throws -> [SaidDeckPreset] {
        try services.deckPresets(deckID: deckID)
    }

    func selectDeckPreset(deckID: Int64, presetID: Int64) throws {
        try services.selectDeckPreset(deckID: deckID, presetID: presetID)
        loadedDeckOptions.removeValue(forKey: deckID)
    }

    func cloneDeckPreset(deckID: Int64, name: String) throws {
        try services.cloneDeckPreset(deckID: deckID, name: name)
        loadedDeckOptions.removeValue(forKey: deckID)
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
        resetCollectionCaches()
    }

    func abortSync() throws {
        try services.abortSync()
    }

    func storeMedia(data: Data, suggestedName: String) throws -> String {
        try services.addMedia(desiredName: suggestedName, data: data)
    }

    private func resetCollectionCaches() {
        withQueuedCardsLock {
            queuedByCardID.removeAll()
        }
        deckNames.removeAll()
        selectedDeckID = nil
        loadedDeckOptions.removeAll()
    }

    private func applyMigrationSanitization(for deckID: Int64?) throws -> [MigrationNoteSnapshot] {
        let noteIDs = try noteIDs(forDeck: deckID)
        var snapshots: [MigrationNoteSnapshot] = []
        var sanitizedNotes: [SaidNote] = []
        for noteID in noteIDs {
            let note = try services.note(id: noteID)
            snapshots.append(
                MigrationNoteSnapshot(
                    noteID: noteID,
                    fields: note.fields,
                    tags: note.tags
                )
            )
            let notetype = try services.notetype(id: note.notetypeID)
            sanitizedNotes.append(
                MigrationNoteSanitizer.sanitize(note: note, fieldNames: notetype.fieldNames).note
            )
        }
        for note in sanitizedNotes {
            try services.update(note)
        }
        return snapshots
    }

    private func restoreMigrationSnapshots(_ snapshots: [MigrationNoteSnapshot]) throws {
        for snapshot in snapshots {
            var note = try services.note(id: snapshot.noteID)
            note.fields = snapshot.fields
            note.tags = snapshot.tags
            try services.update(note)
        }
    }

    private func noteIDs(forDeck deckID: Int64?) throws -> [Int64] {
        if let deckID = deckID {
            var noteIDs = Set<Int64>()
            for cardID in try cardIDs(inDeck: deckID) {
                noteIDs.insert(try services.card(id: cardID).noteID)
            }
            return noteIDs.sorted()
        }
        return try allNoteIDs()
    }

    private func allNoteIDs() throws -> [Int64] {
        var noteIDs = Set<Int64>()
        for cardID in try services.searchCards("deck:*") {
            noteIDs.insert(try services.card(id: cardID).noteID)
        }
        return noteIDs.sorted()
    }

    func countNotesNeedingTranslation() throws -> Int {
        try services.searchNotes("tag:trans").count
    }

    func countNotesNeedingReferenceAudio() throws -> Int {
        var count = 0
        for noteID in try allNoteIDs() {
            let note = try services.note(id: noteID)
            if note.fields.contains(where: MigrationNoteSanitizer.containsSoundTag) {
                continue
            }
            let notetype = try services.notetype(id: note.notetypeID)
            guard let sourceIndex = NoteFieldMapper.sourceFieldIndex(
                in: notetype.fieldNames,
                fields: note.fields
            ),
            note.fields.indices.contains(sourceIndex) else {
                continue
            }
            let source = PronounceReferenceTargetParser.stripField(note.fields[sourceIndex])
            if !source.isEmpty {
                count += 1
            }
        }
        return count
    }

    private func withQueuedCardsLock<T>(_ body: () throws -> T) rethrows -> T {
        queuedCardsLock.lock()
        defer { queuedCardsLock.unlock() }
        return try body()
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

    private func filteredDecksByID() throws -> [Int64: SaidDeck] {
        var result: [Int64: SaidDeck] = [:]
        func collect(_ decks: [SaidDeck]) {
            for deck in decks {
                if deck.filtered { result[deck.id] = deck }
                collect(deck.children)
            }
        }
        collect(try services.deckTree())
        return result
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

    private func cardIDs(inDeck deckID: Int64) throws -> [Int64] {
        let deckIDs = try descendantDeckIDs(for: deckID)
        let idList = deckIDs.sorted().map(String.init).joined(separator: ",")
        if !idList.isEmpty {
            let byDeckID = try services.searchCards("did:\(idList)")
            if !byDeckID.isEmpty { return byDeckID }
        }

        let decks = try listDecks()
        guard let deck = decks.first(where: { $0.id == deckID }) else {
            throw AnkiError.notFound
        }
        let escapedName = deck.name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return try services.searchCards("deck:\"\(escapedName)\"")
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
