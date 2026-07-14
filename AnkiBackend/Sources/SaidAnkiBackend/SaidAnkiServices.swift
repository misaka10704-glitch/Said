import AnkiProto
import Foundation
import SwiftProtobuf

public struct SaidDeck: Equatable, Sendable {
    public let id: Int64
    public let name: String
    public let level: UInt32
    public let newCount: Int
    public let learningCount: Int
    public let reviewCount: Int
    public let totalInDeck: Int
    public let totalIncludingChildren: Int
    public let filtered: Bool
    public let children: [SaidDeck]
}

public struct SaidDeckDetail: Equatable, Sendable {
    public let id: Int64
    public let name: String
    public let level: UInt32
    public let filtered: Bool
    public let description: String
    public let configID: Int64?
    public let newCount: Int
    public let learningCount: Int
    public let reviewCount: Int
    public let totalInDeck: Int
    public let totalIncludingChildren: Int
}

public struct SaidDeckPreset: Equatable, Sendable {
    public let id: Int64
    public let name: String
    public let useCount: Int
}

public struct SaidDeckDeletionResult: Equatable, Sendable {
    /// Number of cards deleted by rslib. Child decks are included.
    /// Cards in filtered decks are returned to their original decks instead.
    public let deletedCardCount: Int
}

public struct SaidCustomStudyTag: Equatable, Sendable {
    public let name: String
    public let included: Bool
    public let excluded: Bool
}

public struct SaidCustomStudyDefaults: Equatable, Sendable {
    public let tags: [SaidCustomStudyTag]
    public let extendNew: Int
    public let extendReview: Int
    public let availableNew: Int
    public let availableReview: Int
    public let availableNewInChildren: Int
    public let availableReviewInChildren: Int
}

public enum SaidCustomStudyCramKind: Sendable {
    case due
    case newCards
    case review
    case all
}

public enum SaidCustomStudy: Sendable {
    case increaseNewLimit(Int32)
    case increaseReviewLimit(Int32)
    case forgotten(days: UInt32)
    case reviewAhead(days: UInt32)
    case previewNew(days: UInt32)
    case cram(
        kind: SaidCustomStudyCramKind,
        cardLimit: UInt32,
        includeTags: [String],
        excludeTags: [String]
    )
}

public enum SaidRating: Int, CaseIterable, Sendable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4
}

public struct SaidQueuedCard: Sendable {
    public let cardID: Int64
    public let noteID: Int64
    public let deckID: Int64
    public let templateIndex: UInt32
    public let cardType: UInt32
    public let queue: Int32
    public let due: Int32
    public let interval: UInt32
    public let easeFactor: UInt32
    public let reps: UInt32
    public let lapses: UInt32
    public let remainingSteps: UInt32
    public let states: Data
    public let nextIntervals: [SaidRating: String]
}

public struct SaidQueue: Sendable {
    public let cards: [SaidQueuedCard]
    public let newCount: Int
    public let learningCount: Int
    public let reviewCount: Int
}

public struct SaidRenderedCard: Sendable {
    public let frontHTML: String
    public let backHTML: String
    public let css: String
}

public struct SaidNote: Sendable {
    public let id: Int64
    public let notetypeID: Int64
    public var fields: [String]
    public var tags: [String]
}

public struct SaidNotetype: Sendable {
    public let id: Int64
    public let name: String
    public let fieldNames: [String]
    public let templateNames: [String]
}

public struct SaidBrowserCard: Sendable {
    public let id: Int64
    public let noteID: Int64
    public let deckID: Int64
    public let templateIndex: UInt32
    public let queue: Int32
    public let due: Int32
    public let flags: UInt32
}

public struct SaidDeckOptions: Sendable {
    public let deckID: Int64
    public let deckName: String
    public let presetName: String
    public let presetUseCount: Int
    public let configID: Int64
    public let fsrsEnabled: Bool
    public let desiredRetention: Double
    public let desiredRetentionIsOverride: Bool
    public let presetNewCardsPerDay: Int
    public let presetReviewsPerDay: Int
    public let deckNewCardsPerDay: Int?
    public let deckReviewsPerDay: Int?
    public let todayNewCardsPerDay: Int?
    public let todayReviewsPerDay: Int?
    public let effectiveNewCardsPerDay: Int
    public let effectiveReviewsPerDay: Int
    public let learnSteps: [Double]
    public let graduatingIntervalGood: Int
    public let graduatingIntervalEasy: Int
    public let relearnSteps: [Double]
    public let minimumLapseInterval: Int
    public let leechThreshold: Int
    public let leechAction: Int
    public let maximumReviewInterval: Int
    public let historicalRetention: Double
    public let newCardInsertOrder: Int
    public let newCardGatherPriority: Int
    public let newCardSortOrder: Int
    public let newMix: Int
    public let interdayLearningMix: Int
    public let reviewOrder: Int
    public let buryNew: Bool
    public let buryReviews: Bool
    public let buryInterdayLearning: Bool
    fileprivate let source: Data
}

public struct SaidGraphPoint: Sendable {
    public let day: Int32
    public let count: UInt32
    public let milliseconds: UInt64
}

public struct SaidCountBucket: Sendable {
    public let bucket: UInt32
    public let count: UInt32
}

public struct SaidTodayStatistics: Sendable {
    public let answerCount: UInt32
    public let answerMilliseconds: UInt32
    public let correctCount: UInt32
    public let matureCorrect: UInt32
    public let matureCount: UInt32
    public let learnCount: UInt32
    public let reviewCount: UInt32
    public let relearnCount: UInt32
    public let earlyReviewCount: UInt32
}

public struct SaidCardStateCounts: Sendable {
    public let new: UInt32
    public let learning: UInt32
    public let relearning: UInt32
    public let young: UInt32
    public let mature: UInt32
    public let suspended: UInt32
    public let buried: UInt32
}

public struct SaidStatistics: Sendable {
    public let reviewed: Int
    public let secondsStudied: Int
    public let retention: Double?
    public let reviewHistory: [SaidGraphPoint]
    public let futureDue: [Int32: UInt32]
    public let futureDueHasBacklog: Bool
    public let futureDueDailyLoad: UInt32
    public let today: SaidTodayStatistics
    public let cardStates: SaidCardStateCounts
    public let buttonCounts: [UInt32]
    public let buttonPeriodDays: UInt32
    public let rolloverHour: UInt32
    public let fsrsEnabled: Bool
    public let stability: [SaidCountBucket]
    public let difficulty: [SaidCountBucket]
    public let medianDifficulty: Double?
    public let retrievability: [SaidCountBucket]
    public let averageRetrievability: Double?
}

public enum SaidSyncRequirement: Sendable {
    case noChanges
    case normal
    case chooseFullSync
    case fullDownload
    case fullUpload
}

public struct SaidSyncResult: Sendable {
    public let requirement: SaidSyncRequirement
    public let serverMessage: String
    public let endpoint: String?
    public let serverMediaUSN: Int32
}

/// Typed, iOS-12-safe facade over the official Anki rslib protobuf API.
/// All methods are synchronous; callers must invoke them on the app's serial
/// backend queue, never the main thread.
public final class SaidAnkiServices {
    public let backend: RustAnkiBackend

    public init(backend: RustAnkiBackend) {
        self.backend = backend
    }

    public func deckTree(now: Date = Date()) throws -> [SaidDeck] {
        var request = Anki_Decks_DeckTreeRequest()
        request.now = Int64(now.timeIntervalSince1970)
        let root: Anki_Decks_DeckTreeNode = try backend.invoke(
            service: RustAnkiBackend.Service.decks,
            method: RustAnkiBackend.DecksMethod.getDeckTree,
            request: request
        )
        return root.children.map(mapDeck)
    }

    @discardableResult
    public func createDeck(name: String) throws -> SaidDeckDetail {
        var deck: Anki_Decks_Deck = try backend.invoke(
            service: RustAnkiBackend.Service.decks,
            method: RustAnkiBackend.DecksMethod.newDeck
        )
        deck.name = name
        let response: Anki_Collection_OpChangesWithId = try backend.invoke(
            service: RustAnkiBackend.Service.decks,
            method: RustAnkiBackend.DecksMethod.addDeck,
            request: deck
        )
        return try deckDetail(id: response.id)
    }

    public func deckDetail(id: Int64, now: Date = Date()) throws -> SaidDeckDetail {
        var request = Anki_Decks_DeckId()
        request.did = id
        let deck: Anki_Decks_Deck = try backend.invoke(
            service: RustAnkiBackend.Service.decks,
            method: RustAnkiBackend.DecksMethod.getDeck,
            request: request
        )
        let treeNode = findDeck(id: id, in: try deckTree(now: now))
        let description: String
        let configID: Int64?
        switch deck.kind {
        case .normal(let normal):
            description = normal.description_p
            configID = normal.configID
        case .filtered:
            description = ""
            configID = nil
        case .none:
            description = ""
            configID = nil
        }
        return SaidDeckDetail(
            id: deck.id,
            name: deck.name,
            level: treeNode?.level ?? UInt32(max(0, deck.name.components(separatedBy: "::").count - 1)),
            filtered: {
                if case .filtered? = deck.kind { return true }
                return false
            }(),
            description: description,
            configID: configID,
            newCount: treeNode?.newCount ?? 0,
            learningCount: treeNode?.learningCount ?? 0,
            reviewCount: treeNode?.reviewCount ?? 0,
            totalInDeck: treeNode?.totalInDeck ?? 0,
            totalIncludingChildren: treeNode?.totalIncludingChildren ?? 0
        )
    }

    public func renameDeck(id: Int64, newName: String) throws {
        var request = Anki_Decks_RenameDeckRequest()
        request.deckID = id
        request.newName = newName
        try backend.callVoid(
            service: RustAnkiBackend.Service.decks,
            method: RustAnkiBackend.DecksMethod.renameDeck,
            request: request
        )
    }

    @discardableResult
    public func removeDecks(ids: [Int64]) throws -> SaidDeckDeletionResult {
        var request = Anki_Decks_DeckIds()
        request.dids = ids
        let response: Anki_Collection_OpChangesWithCount = try backend.invoke(
            service: RustAnkiBackend.Service.decks,
            method: RustAnkiBackend.DecksMethod.removeDecks,
            request: request
        )
        return SaidDeckDeletionResult(deletedCardCount: Int(response.count))
    }

    /// Passing nil moves the decks to the top level.
    @discardableResult
    public func reparentDecks(ids: [Int64], newParentID: Int64?) throws -> Int {
        var request = Anki_Decks_ReparentDecksRequest()
        request.deckIds = ids
        request.newParent = newParentID ?? 0
        let response: Anki_Collection_OpChangesWithCount = try backend.invoke(
            service: RustAnkiBackend.Service.decks,
            method: RustAnkiBackend.DecksMethod.reparentDecks,
            request: request
        )
        return Int(response.count)
    }

    public func customStudyDefaults(deckID: Int64) throws -> SaidCustomStudyDefaults {
        var request = Anki_Scheduler_CustomStudyDefaultsRequest()
        request.deckID = deckID
        let response: Anki_Scheduler_CustomStudyDefaultsResponse = try backend.invoke(
            service: RustAnkiBackend.Service.scheduler,
            method: RustAnkiBackend.SchedulerMethod.customStudyDefaults,
            request: request
        )
        return SaidCustomStudyDefaults(
            tags: response.tags.map {
                SaidCustomStudyTag(name: $0.name, included: $0.include, excluded: $0.exclude)
            },
            extendNew: Int(response.extendNew),
            extendReview: Int(response.extendReview),
            availableNew: Int(response.availableNew),
            availableReview: Int(response.availableReview),
            availableNewInChildren: Int(response.availableNewInChildren),
            availableReviewInChildren: Int(response.availableReviewInChildren)
        )
    }

    public func extendLimits(deckID: Int64, newDelta: Int32, reviewDelta: Int32) throws {
        var request = Anki_Scheduler_ExtendLimitsRequest()
        request.deckID = deckID
        request.newDelta = newDelta
        request.reviewDelta = reviewDelta
        try backend.callVoid(
            service: RustAnkiBackend.Service.scheduler,
            method: RustAnkiBackend.SchedulerMethod.extendLimits,
            request: request
        )
    }

    public func customStudy(deckID: Int64, mode: SaidCustomStudy) throws {
        var request = Anki_Scheduler_CustomStudyRequest()
        request.deckID = deckID
        switch mode {
        case .increaseNewLimit(let delta):
            request.newLimitDelta = delta
        case .increaseReviewLimit(let delta):
            request.reviewLimitDelta = delta
        case .forgotten(let days):
            request.forgotDays = days
        case .reviewAhead(let days):
            request.reviewAheadDays = days
        case .previewNew(let days):
            request.previewDays = days
        case .cram(let kind, let cardLimit, let includeTags, let excludeTags):
            var cram = Anki_Scheduler_CustomStudyRequest.Cram()
            switch kind {
            case .due: cram.kind = .due
            case .newCards: cram.kind = .new
            case .review: cram.kind = .review
            case .all: cram.kind = .all
            }
            cram.cardLimit = cardLimit
            cram.tagsToInclude = includeTags
            cram.tagsToExclude = excludeTags
            request.cram = cram
        }
        try backend.callVoid(
            service: RustAnkiBackend.Service.scheduler,
            method: RustAnkiBackend.SchedulerMethod.customStudy,
            request: request
        )
    }

    public func emptyFilteredDeck(deckID: Int64) throws {
        var request = Anki_Decks_DeckId()
        request.did = deckID
        try backend.callVoid(
            service: RustAnkiBackend.Service.scheduler,
            method: RustAnkiBackend.SchedulerMethod.emptyFilteredDeck,
            request: request
        )
    }

    @discardableResult
    public func rebuildFilteredDeck(deckID: Int64) throws -> Int {
        var request = Anki_Decks_DeckId()
        request.did = deckID
        let response: Anki_Collection_OpChangesWithCount = try backend.invoke(
            service: RustAnkiBackend.Service.scheduler,
            method: RustAnkiBackend.SchedulerMethod.rebuildFilteredDeck,
            request: request
        )
        return Int(response.count)
    }

    public func setCurrentDeck(_ deckID: Int64) throws {
        var request = Anki_Decks_DeckId()
        request.did = deckID
        try backend.callVoid(
            service: RustAnkiBackend.Service.decks,
            method: RustAnkiBackend.DecksMethod.setCurrentDeck,
            request: request
        )
    }

    public func queuedCards(limit: UInt32 = 20) throws -> SaidQueue {
        var request = Anki_Scheduler_GetQueuedCardsRequest()
        request.fetchLimit = limit
        let response: Anki_Scheduler_QueuedCards = try backend.invoke(
            service: RustAnkiBackend.Service.scheduler,
            method: RustAnkiBackend.SchedulerMethod.getQueuedCards,
            request: request
        )
        let cards = try response.cards.map { queued -> SaidQueuedCard in
            guard queued.hasCard, queued.hasStates else {
                throw BackendError(
                    kind: .protoError,
                    message: "Anki 调度队列返回了缺少卡片或状态的数据"
                )
            }
            let intervals = officialNextIntervals(queued.states)
            return SaidQueuedCard(
                cardID: queued.card.id,
                noteID: queued.card.noteID,
                deckID: queued.card.deckID,
                templateIndex: queued.card.templateIdx,
                cardType: queued.card.ctype,
                queue: queued.card.queue,
                due: queued.card.due,
                interval: queued.card.interval,
                easeFactor: queued.card.easeFactor,
                reps: queued.card.reps,
                lapses: queued.card.lapses,
                remainingSteps: queued.card.remainingSteps,
                states: try queued.states.serializedData(),
                nextIntervals: intervals
            )
        }
        return SaidQueue(
            cards: cards,
            newCount: Int(response.newCount),
            learningCount: Int(response.learningCount),
            reviewCount: Int(response.reviewCount)
        )
    }

    private func officialNextIntervals(
        _ states: Anki_Scheduler_SchedulingStates
    ) -> [SaidRating: String] {
        if let response: Anki_Generic_StringList = try? backend.invoke(
            service: RustAnkiBackend.Service.scheduler,
            method: RustAnkiBackend.SchedulerMethod.describeNextStates,
            request: states
        ), response.vals.count >= SaidRating.allCases.count {
            return Dictionary(uniqueKeysWithValues: SaidRating.allCases.enumerated().map {
                ($0.element, response.vals[$0.offset])
            })
        }

        // Keep the reviewer usable if an older embedded backend lacks the RPC.
        return [
            .again: formatInterval(scheduledSeconds(states.again)),
            .hard: formatInterval(scheduledSeconds(states.hard)),
            .good: formatInterval(scheduledSeconds(states.good)),
            .easy: formatInterval(scheduledSeconds(states.easy)),
        ]
    }

    public func answer(
        _ card: SaidQueuedCard,
        rating: SaidRating,
        millisecondsTaken: UInt32
    ) throws {
        let states = try Anki_Scheduler_SchedulingStates(serializedBytes: card.states)
        let newState: Anki_Scheduler_SchedulingState
        let protoRating: Anki_Scheduler_CardAnswer.Rating
        switch rating {
        case .again:
            newState = states.again
            protoRating = .again
        case .hard:
            newState = states.hard
            protoRating = .hard
        case .good:
            newState = states.good
            protoRating = .good
        case .easy:
            newState = states.easy
            protoRating = .easy
        }
        var answer = Anki_Scheduler_CardAnswer()
        answer.cardID = card.cardID
        answer.currentState = states.current
        answer.newState = newState
        answer.rating = protoRating
        answer.answeredAtMillis = Int64(Date().timeIntervalSince1970 * 1000)
        answer.millisecondsTaken = millisecondsTaken
        try backend.callVoid(
            service: RustAnkiBackend.Service.scheduler,
            method: RustAnkiBackend.SchedulerMethod.answerCard,
            request: answer
        )
    }

    public func render(cardID: Int64, browser: Bool = false) throws -> SaidRenderedCard {
        var request = Anki_CardRendering_RenderExistingCardRequest()
        request.cardID = cardID
        request.browser = browser
        request.partialRender = false
        let response: Anki_CardRendering_RenderCardResponse = try backend.invoke(
            service: RustAnkiBackend.Service.cardRendering,
            method: RustAnkiBackend.CardRenderingMethod.renderExistingCard,
            request: request
        )
        return SaidRenderedCard(
            frontHTML: renderNodes(response.questionNodes),
            backHTML: renderNodes(response.answerNodes),
            css: response.css
        )
    }

    public func searchNotes(_ query: String) throws -> [Int64] {
        var request = Anki_Search_SearchRequest()
        request.search = query
        let response: Anki_Search_SearchResponse = try backend.invoke(
            service: RustAnkiBackend.Service.search,
            method: RustAnkiBackend.SearchMethod.searchNotes,
            request: request
        )
        return response.ids
    }

    public func searchCards(_ query: String) throws -> [Int64] {
        var request = Anki_Search_SearchRequest()
        request.search = query
        let response: Anki_Search_SearchResponse = try backend.invoke(
            service: RustAnkiBackend.Service.search,
            method: RustAnkiBackend.SearchMethod.searchCards,
            request: request
        )
        return response.ids
    }

    public func card(id: Int64) throws -> SaidBrowserCard {
        var request = Anki_Cards_CardId()
        request.cid = id
        let response: Anki_Cards_Card = try backend.invoke(
            service: RustAnkiBackend.Service.cards,
            method: RustAnkiBackend.CardsMethod.getCard,
            request: request
        )
        return SaidBrowserCard(
            id: response.id,
            noteID: response.noteID,
            deckID: response.deckID,
            templateIndex: response.templateIdx,
            queue: response.queue,
            due: response.due,
            flags: response.flags
        )
    }

    public func note(id: Int64) throws -> SaidNote {
        var request = Anki_Notes_NoteId()
        request.nid = id
        let response: Anki_Notes_Note = try backend.invoke(
            service: RustAnkiBackend.Service.notes,
            method: RustAnkiBackend.NotesMethod.getNote,
            request: request
        )
        return SaidNote(
            id: response.id,
            notetypeID: response.notetypeID,
            fields: response.fields,
            tags: response.tags
        )
    }

    public func update(_ note: SaidNote) throws {
        var proto = Anki_Notes_Note()
        proto.id = note.id
        proto.notetypeID = note.notetypeID
        proto.fields = note.fields
        proto.tags = note.tags
        var request = Anki_Notes_UpdateNotesRequest()
        request.notes = [proto]
        request.skipUndoEntry = false
        try backend.callVoid(
            service: RustAnkiBackend.Service.notes,
            method: RustAnkiBackend.NotesMethod.updateNotes,
            request: request
        )
    }

    public func notetype(id: Int64) throws -> SaidNotetype {
        var request = Anki_Notetypes_NotetypeId()
        request.ntid = id
        let response: Anki_Notetypes_Notetype = try backend.invoke(
            service: RustAnkiBackend.Service.notetypes,
            method: RustAnkiBackend.NotetypesMethod.getNotetype,
            request: request
        )
        return SaidNotetype(
            id: response.id,
            name: response.name,
            fieldNames: response.fields.map(\.name),
            templateNames: response.templates.map(\.name)
        )
    }

    /// Creates a note with rslib so field validation, duplicate detection and
    /// scheduling remain owned by Anki instead of a parallel local database.
    @discardableResult
    public func addNote(
        notetypeID: Int64,
        deckID: Int64,
        fields: [String],
        tags: [String]
    ) throws -> Int64 {
        var notetypeRequest = Anki_Notetypes_NotetypeId()
        notetypeRequest.ntid = notetypeID
        var note: Anki_Notes_Note = try backend.invoke(
            service: RustAnkiBackend.Service.notes,
            method: RustAnkiBackend.NotesMethod.newNote,
            request: notetypeRequest
        )
        note.fields = fields
        note.tags = tags

        var request = Anki_Notes_AddNoteRequest()
        request.note = note
        request.deckID = deckID
        let response: Anki_Notes_AddNoteResponse = try backend.invoke(
            service: RustAnkiBackend.Service.notes,
            method: RustAnkiBackend.NotesMethod.addNote,
            request: request
        )
        return response.noteID
    }

    public func buryOrSuspend(cardIDs: [Int64], suspend: Bool) throws {
        var request = Anki_Scheduler_BuryOrSuspendCardsRequest()
        request.cardIds = cardIDs
        request.mode = suspend ? .suspend : .buryUser
        try backend.callVoid(
            service: RustAnkiBackend.Service.scheduler,
            method: RustAnkiBackend.SchedulerMethod.buryOrSuspendCards,
            request: request
        )
    }

    public func setFlag(_ flag: UInt32, cardIDs: [Int64]) throws {
        var request = Anki_Cards_SetFlagRequest()
        request.cardIds = cardIDs
        request.flag = flag
        try backend.callVoid(
            service: RustAnkiBackend.Service.cards,
            method: RustAnkiBackend.CardsMethod.setFlag,
            request: request
        )
    }

    public func moveCards(_ cardIDs: [Int64], to deckID: Int64) throws {
        var request = Anki_Cards_SetDeckRequest()
        request.cardIds = cardIDs
        request.deckID = deckID
        try backend.callVoid(
            service: RustAnkiBackend.Service.cards,
            method: RustAnkiBackend.CardsMethod.setDeck,
            request: request
        )
    }

    public func removeNotes(forCardIDs cardIDs: [Int64]) throws {
        var request = Anki_Notes_RemoveNotesRequest()
        request.cardIds = cardIDs
        try backend.callVoid(
            service: RustAnkiBackend.Service.notes,
            method: RustAnkiBackend.NotesMethod.removeNotes,
            request: request
        )
    }

    public func addTags(_ tags: [String], toNoteIDs noteIDs: [Int64]) throws {
        var request = Anki_Tags_NoteIdsAndTagsRequest()
        request.noteIds = noteIDs
        request.tags = tags.joined(separator: " ")
        try backend.callVoid(
            service: RustAnkiBackend.Service.tags,
            method: RustAnkiBackend.TagsMethod.addNoteTags,
            request: request
        )
    }

    public func deckOptions(deckID: Int64) throws -> SaidDeckOptions {
        var request = Anki_Decks_DeckId()
        request.did = deckID
        let response: Anki_DeckConfig_DeckConfigsForUpdate = try backend.invoke(
            service: RustAnkiBackend.Service.deckConfig,
            method: RustAnkiBackend.DeckConfigMethod.getDeckConfigsForUpdate,
            request: request
        )
        guard let selectedWithExtra = response.allConfig.first(where: {
            $0.config.id == response.currentDeck.configID
        }) else {
            throw BackendError(kind: .notFoundError, message: "Deck preset is unavailable")
        }
        let selected = selectedWithExtra.config
        let config = selected.config
        let limits = response.currentDeck.limits
        let retention = response.currentDeck.limits.hasDesiredRetention
            ? response.currentDeck.limits.desiredRetention : config.desiredRetention
        let deckNew = limits.hasNew ? Int(limits.new) : nil
        let deckReviews = limits.hasReview ? Int(limits.review) : nil
        let todayNew = limits.hasNewToday && limits.newTodayActive ? Int(limits.newToday) : nil
        let todayReviews = limits.hasReviewToday && limits.reviewTodayActive
            ? Int(limits.reviewToday) : nil
        return SaidDeckOptions(
            deckID: deckID,
            deckName: response.currentDeck.name,
            presetName: selected.name,
            presetUseCount: Int(selectedWithExtra.useCount),
            configID: selected.id,
            fsrsEnabled: response.fsrs,
            desiredRetention: Double(retention),
            desiredRetentionIsOverride: limits.hasDesiredRetention,
            presetNewCardsPerDay: Int(config.newPerDay),
            presetReviewsPerDay: Int(config.reviewsPerDay),
            deckNewCardsPerDay: deckNew,
            deckReviewsPerDay: deckReviews,
            todayNewCardsPerDay: todayNew,
            todayReviewsPerDay: todayReviews,
            effectiveNewCardsPerDay: todayNew ?? deckNew ?? Int(config.newPerDay),
            effectiveReviewsPerDay: todayReviews ?? deckReviews ?? Int(config.reviewsPerDay),
            learnSteps: config.learnSteps.map(Double.init),
            graduatingIntervalGood: Int(config.graduatingIntervalGood),
            graduatingIntervalEasy: Int(config.graduatingIntervalEasy),
            relearnSteps: config.relearnSteps.map(Double.init),
            minimumLapseInterval: Int(config.minimumLapseInterval),
            leechThreshold: Int(config.leechThreshold),
            leechAction: config.leechAction.rawValue,
            maximumReviewInterval: Int(config.maximumReviewInterval),
            historicalRetention: Double(config.historicalRetention),
            newCardInsertOrder: config.newCardInsertOrder.rawValue,
            newCardGatherPriority: config.newCardGatherPriority.rawValue,
            newCardSortOrder: config.newCardSortOrder.rawValue,
            newMix: config.newMix.rawValue,
            interdayLearningMix: config.interdayLearningMix.rawValue,
            reviewOrder: config.reviewOrder.rawValue,
            buryNew: config.buryNew,
            buryReviews: config.buryReviews,
            buryInterdayLearning: config.buryInterdayLearning,
            source: try response.serializedData()
        )
    }

    public func deckPresets(deckID: Int64) throws -> [SaidDeckPreset] {
        let source = try deckConfigsForUpdate(deckID: deckID)
        return source.allConfig.map {
            SaidDeckPreset(
                id: $0.config.id,
                name: $0.config.name,
                useCount: Int($0.useCount)
            )
        }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public func selectDeckPreset(deckID: Int64, presetID: Int64) throws {
        let source = try deckConfigsForUpdate(deckID: deckID)
        guard let preset = source.allConfig.first(where: { $0.config.id == presetID })?.config else {
            throw BackendError(kind: .notFoundError, message: "Deck preset is unavailable")
        }
        try applyPresetChange(deckID: deckID, source: source, selectedPreset: preset)
    }

    public func cloneDeckPreset(deckID: Int64, name: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw BackendError(kind: .invalidInput, message: "Preset name cannot be empty")
        }
        let source = try deckConfigsForUpdate(deckID: deckID)
        guard var clone = source.allConfig.first(where: {
            $0.config.id == source.currentDeck.configID
        })?.config else {
            throw BackendError(kind: .notFoundError, message: "Current deck preset is unavailable")
        }
        // Config ID 0 asks rslib to allocate a new preset ID. The final config
        // in the request becomes the selected preset for the target deck.
        clone.id = 0
        clone.name = trimmedName
        try applyPresetChange(deckID: deckID, source: source, selectedPreset: clone)
    }

    private func deckConfigsForUpdate(
        deckID: Int64
    ) throws -> Anki_DeckConfig_DeckConfigsForUpdate {
        var request = Anki_Decks_DeckId()
        request.did = deckID
        return try backend.invoke(
            service: RustAnkiBackend.Service.deckConfig,
            method: RustAnkiBackend.DeckConfigMethod.getDeckConfigsForUpdate,
            request: request
        )
    }

    private func applyPresetChange(
        deckID: Int64,
        source: Anki_DeckConfig_DeckConfigsForUpdate,
        selectedPreset: Anki_DeckConfig_DeckConfig
    ) throws {
        var request = Anki_DeckConfig_UpdateDeckConfigsRequest()
        request.targetDeckID = deckID
        request.configs = [selectedPreset]
        request.mode = .normal
        request.limits = source.currentDeck.limits
        request.cardStateCustomizer = source.cardStateCustomizer
        request.newCardsIgnoreReviewLimit = source.newCardsIgnoreReviewLimit
        request.fsrs = source.fsrs
        request.applyAllParentLimits = source.applyAllParentLimits
        request.fsrsHealthCheck = source.fsrsHealthCheck
        try backend.callVoid(
            service: RustAnkiBackend.Service.deckConfig,
            method: RustAnkiBackend.DeckConfigMethod.updateDeckConfigs,
            request: request
        )
    }

    public func updateDeckOptions(
        _ options: SaidDeckOptions,
        desiredRetention: Double,
        desiredRetentionIsOverride: Bool,
        presetNewCardsPerDay: Int,
        presetReviewsPerDay: Int,
        deckNewCardsPerDay: Int?,
        deckReviewsPerDay: Int?,
        todayNewCardsPerDay: Int?,
        todayReviewsPerDay: Int?,
        learnSteps: [Double],
        graduatingIntervalGood: Int,
        graduatingIntervalEasy: Int,
        relearnSteps: [Double],
        minimumLapseInterval: Int,
        leechThreshold: Int,
        leechAction: Int,
        maximumReviewInterval: Int,
        historicalRetention: Double,
        newCardInsertOrder: Int,
        newCardGatherPriority: Int,
        newCardSortOrder: Int,
        newMix: Int,
        interdayLearningMix: Int,
        reviewOrder: Int,
        buryNew: Bool,
        buryReviews: Bool,
        buryInterdayLearning: Bool
    ) throws {
        let source = try Anki_DeckConfig_DeckConfigsForUpdate(serializedBytes: options.source)
        guard var selected = source.allConfig.first(where: {
            $0.config.id == source.currentDeck.configID
        })?.config else {
            throw BackendError(kind: .notFoundError, message: "Deck preset is unavailable")
        }
        // Desired retention is a deck override in the loaded state, so it must
        // be written back to Limits instead of silently changing the preset.
        var limits = source.currentDeck.limits
        if desiredRetentionIsOverride {
            limits.desiredRetention = Float(desiredRetention)
        } else {
            limits.clearDesiredRetention()
        }
        selected.config.newPerDay = UInt32(max(0, presetNewCardsPerDay))
        selected.config.reviewsPerDay = UInt32(max(0, presetReviewsPerDay))
        setLimit(deckNewCardsPerDay, value: { limits.new = $0 }, clear: { limits.clearNew() })
        setLimit(deckReviewsPerDay, value: { limits.review = $0 }, clear: { limits.clearReview() })
        if let todayNewCardsPerDay = todayNewCardsPerDay {
            limits.newToday = UInt32(max(0, todayNewCardsPerDay))
            limits.newTodayActive = true
        } else if source.currentDeck.limits.newTodayActive {
            limits.clearNewToday()
            limits.newTodayActive = false
        }
        if let todayReviewsPerDay = todayReviewsPerDay {
            limits.reviewToday = UInt32(max(0, todayReviewsPerDay))
            limits.reviewTodayActive = true
        } else if source.currentDeck.limits.reviewTodayActive {
            limits.clearReviewToday()
            limits.reviewTodayActive = false
        }
        selected.config.learnSteps = learnSteps.map(Float.init)
        selected.config.graduatingIntervalGood = UInt32(max(1, graduatingIntervalGood))
        selected.config.graduatingIntervalEasy = UInt32(max(1, graduatingIntervalEasy))
        selected.config.relearnSteps = relearnSteps.map(Float.init)
        selected.config.minimumLapseInterval = UInt32(max(0, minimumLapseInterval))
        selected.config.leechThreshold = UInt32(max(1, leechThreshold))
        selected.config.leechAction = .init(rawValue: leechAction) ?? selected.config.leechAction
        selected.config.maximumReviewInterval = UInt32(max(1, maximumReviewInterval))
        selected.config.historicalRetention = Float(historicalRetention)
        selected.config.newCardInsertOrder =
            .init(rawValue: newCardInsertOrder) ?? selected.config.newCardInsertOrder
        selected.config.newCardGatherPriority =
            .init(rawValue: newCardGatherPriority) ?? selected.config.newCardGatherPriority
        selected.config.newCardSortOrder =
            .init(rawValue: newCardSortOrder) ?? selected.config.newCardSortOrder
        selected.config.newMix = .init(rawValue: newMix) ?? selected.config.newMix
        selected.config.interdayLearningMix =
            .init(rawValue: interdayLearningMix) ?? selected.config.interdayLearningMix
        selected.config.reviewOrder = .init(rawValue: reviewOrder) ?? selected.config.reviewOrder
        selected.config.buryNew = buryNew
        selected.config.buryReviews = buryReviews
        selected.config.buryInterdayLearning = buryInterdayLearning
        var request = Anki_DeckConfig_UpdateDeckConfigsRequest()
        request.targetDeckID = options.deckID
        request.configs = [selected]
        request.mode = .normal
        request.limits = limits
        request.cardStateCustomizer = source.cardStateCustomizer
        request.newCardsIgnoreReviewLimit = source.newCardsIgnoreReviewLimit
        request.fsrs = source.fsrs
        request.applyAllParentLimits = source.applyAllParentLimits
        request.fsrsHealthCheck = source.fsrsHealthCheck
        try backend.callVoid(
            service: RustAnkiBackend.Service.deckConfig,
            method: RustAnkiBackend.DeckConfigMethod.updateDeckConfigs,
            request: request
        )
    }

    private func setLimit(
        _ value: Int?,
        value assign: (UInt32) -> Void,
        clear: () -> Void
    ) {
        if let value = value {
            assign(UInt32(max(0, value)))
        } else {
            clear()
        }
    }

    public func statistics(days: UInt32, search: String = "") throws -> SaidStatistics {
        var request = Anki_Stats_GraphsRequest()
        request.days = days
        request.search = search
        let response: Anki_Stats_GraphsResponse = try backend.invoke(
            service: RustAnkiBackend.Service.stats,
            method: RustAnkiBackend.StatsMethod.graphs,
            request: request
        )
        let firstIncludedDay = -Int32(days) + 1
        let points = response.reviews.count.keys.sorted().filter {
            $0 >= firstIncludedDay && $0 <= 0
        }.map { day -> SaidGraphPoint in
            let counts = response.reviews.count[day]!
            let times = response.reviews.time[day] ?? Anki_Stats_GraphsResponse.ReviewCountsAndTimes.Reviews()
            return SaidGraphPoint(
                day: day,
                count: reviewTotal(counts),
                milliseconds: UInt64(reviewTotal(times))
            )
        }
        let reviewed = points.reduce(0) { $0 + Int($1.count) }
        let milliseconds = points.reduce(UInt64(0)) { $0 + $1.milliseconds }
        let retention = retentionFor(days: days, response: response)
        let buttons = buttonsFor(days: days, response: response)
        let cardCounts = response.cardCounts.excludingInactive
        let difficulty = sortedBuckets(response.difficulty.eases)
        let retrievability = sortedBuckets(response.retrievability.retrievability)
        return SaidStatistics(
            reviewed: reviewed,
            secondsStudied: Int(milliseconds / 1_000),
            retention: retention,
            reviewHistory: points,
            futureDue: response.futureDue.futureDue,
            futureDueHasBacklog: response.futureDue.haveBacklog,
            futureDueDailyLoad: response.futureDue.dailyLoad,
            today: SaidTodayStatistics(
                answerCount: response.today.answerCount,
                answerMilliseconds: response.today.answerMillis,
                correctCount: response.today.correctCount,
                matureCorrect: response.today.matureCorrect,
                matureCount: response.today.matureCount,
                learnCount: response.today.learnCount,
                reviewCount: response.today.reviewCount,
                relearnCount: response.today.relearnCount,
                earlyReviewCount: response.today.earlyReviewCount
            ),
            cardStates: SaidCardStateCounts(
                new: cardCounts.newCards,
                learning: cardCounts.learn,
                relearning: cardCounts.relearn,
                young: cardCounts.young,
                mature: cardCounts.mature,
                suspended: cardCounts.suspended,
                buried: cardCounts.buried
            ),
            buttonCounts: buttons.counts,
            buttonPeriodDays: buttons.days,
            rolloverHour: response.rolloverHour,
            fsrsEnabled: response.fsrs,
            stability: sortedBuckets(response.stability.intervals),
            difficulty: difficulty,
            medianDifficulty: difficulty.isEmpty ? nil : Double(response.difficulty.average),
            retrievability: retrievability,
            averageRetrievability: retrievability.isEmpty
                ? nil : Double(response.retrievability.average)
        )
    }

    @discardableResult
    public func addMedia(desiredName: String, data: Data) throws -> String {
        var request = Anki_Media_AddMediaFileRequest()
        request.desiredName = desiredName
        request.data = data
        let response: Anki_Generic_String = try backend.invoke(
            service: RustAnkiBackend.Service.media,
            method: RustAnkiBackend.MediaMethod.addMediaFile,
            request: request
        )
        return response.val
    }

    @discardableResult
    public func importAnkiPackage(path: String) throws -> String {
        var options = Anki_ImportExport_ImportAnkiPackageOptions()
        options.mergeNotetypes = true
        options.withScheduling = true
        options.withDeckConfigs = true
        var request = Anki_ImportExport_ImportAnkiPackageRequest()
        request.packagePath = path
        request.options = options
        let response: Anki_ImportExport_ImportResponse = try backend.invoke(
            service: RustAnkiBackend.Service.importExport,
            method: RustAnkiBackend.ImportExportMethod.importAnkiPackage,
            request: request
        )
        return "new \(response.log.new.count), updated \(response.log.updated.count), duplicates \(response.log.duplicate.count)"
    }

    @discardableResult
    public func createBackup(
        folder: String,
        force: Bool,
        waitForCompletion: Bool
    ) throws -> Bool {
        var request = Anki_Collection_CreateBackupRequest()
        request.backupFolder = folder
        request.force = force
        request.waitForCompletion = waitForCompletion
        let response: Anki_Generic_Bool = try backend.invoke(
            service: RustAnkiBackend.Service.collection,
            method: RustAnkiBackend.CollectionMethod.createBackup,
            request: request
        )
        return response.val
    }

    public func awaitBackupCompletion() throws {
        try backend.callVoid(
            service: RustAnkiBackend.Service.collection,
            method: RustAnkiBackend.CollectionMethod.awaitBackupCompletion
        )
    }

    public func exportCollectionPackage(
        path: String,
        includeMedia: Bool
    ) throws {
        var request = Anki_ImportExport_ExportCollectionPackageRequest()
        request.outPath = path
        request.includeMedia = includeMedia
        request.legacy = false
        do {
            try backend.callVoid(
                service: RustAnkiBackend.Service.importExport,
                method: RustAnkiBackend.ImportExportMethod.exportCollectionPackage,
                request: request
            )
            try backend.reopenAfterFullSync()
        } catch {
            try? backend.reopenAfterFullSync()
            throw error
        }
    }

    public func importCollectionPackage(
        path: String,
        collectionPath: String,
        mediaFolderPath: String,
        mediaDBPath: String
    ) throws {
        try backend.closeCollection()
        var request = Anki_ImportExport_ImportCollectionPackageRequest()
        request.backupPath = path
        request.colPath = collectionPath
        request.mediaFolder = mediaFolderPath
        request.mediaDb = mediaDBPath
        do {
            try backend.callVoid(
                service: RustAnkiBackend.Service.importExport,
                method: RustAnkiBackend.ImportExportMethod.importCollectionPackage,
                request: request
            )
            try backend.reopenAfterFullSync()
        } catch {
            try? backend.reopenAfterFullSync()
            throw error
        }
    }

    @discardableResult
    public func importCsv(path: String) throws -> String {
        var metadataRequest = Anki_ImportExport_CsvMetadataRequest()
        metadataRequest.path = path
        let metadata: Anki_ImportExport_CsvMetadata = try backend.invoke(
            service: RustAnkiBackend.Service.importExport,
            method: RustAnkiBackend.ImportExportMethod.getCsvMetadata,
            request: metadataRequest
        )
        var request = Anki_ImportExport_ImportCsvRequest()
        request.path = path
        request.metadata = metadata
        let response: Anki_ImportExport_ImportResponse = try backend.invoke(
            service: RustAnkiBackend.Service.importExport,
            method: RustAnkiBackend.ImportExportMethod.importCsv,
            request: request
        )
        return "new \(response.log.new.count), updated \(response.log.updated.count), duplicates \(response.log.duplicate.count)"
    }

    @discardableResult
    public func exportNoteCsv(path: String) throws -> UInt32 {
        var limit = Anki_ImportExport_ExportLimit()
        limit.limit = .wholeCollection(Anki_Generic_Empty())
        var request = Anki_ImportExport_ExportNoteCsvRequest()
        request.outPath = path
        request.withHtml = true
        request.withTags = true
        request.withDeck = true
        request.withNotetype = true
        request.withGuid = true
        request.limit = limit
        let response: Anki_Generic_UInt32 = try backend.invoke(
            service: RustAnkiBackend.Service.importExport,
            method: RustAnkiBackend.ImportExportMethod.exportNoteCsv,
            request: request
        )
        return response.val
    }

    @discardableResult
    public func exportCardCsv(path: String) throws -> UInt32 {
        var limit = Anki_ImportExport_ExportLimit()
        limit.limit = .wholeCollection(Anki_Generic_Empty())
        var request = Anki_ImportExport_ExportCardCsvRequest()
        request.outPath = path
        request.withHtml = true
        request.limit = limit
        let response: Anki_Generic_UInt32 = try backend.invoke(
            service: RustAnkiBackend.Service.importExport,
            method: RustAnkiBackend.ImportExportMethod.exportCardCsv,
            request: request
        )
        return response.val
    }

    public func exportAnkiPackage(
        deckID: Int64?,
        path: String,
        includeScheduling: Bool = true
    ) throws {
        var options = Anki_ImportExport_ExportAnkiPackageOptions()
        options.withScheduling = includeScheduling
        options.withDeckConfigs = true
        options.withMedia = true
        options.legacy = false
        var limit = Anki_ImportExport_ExportLimit()
        if let deckID = deckID {
            limit.deckID = deckID
        } else {
            limit.limit = .wholeCollection(Anki_Generic_Empty())
        }
        var request = Anki_ImportExport_ExportAnkiPackageRequest()
        request.outPath = path
        request.options = options
        request.limit = limit
        _ = try backend.call(
            service: RustAnkiBackend.Service.importExport,
            method: RustAnkiBackend.ImportExportMethod.exportAnkiPackage,
            request: request
        )
    }

    public func exportDeck(
        id: Int64,
        path: String,
        includeScheduling: Bool = true
    ) throws {
        try exportAnkiPackage(
            deckID: id,
            path: path,
            includeScheduling: includeScheduling
        )
    }

    public func syncLogin(
        username: String,
        password: String,
        endpoint: String = ""
    ) throws -> String {
        var request = Anki_Sync_SyncLoginRequest()
        request.username = username
        request.password = password
        if !endpoint.isEmpty { request.endpoint = endpoint }
        let response: Anki_Sync_SyncAuth = try backend.invoke(
            service: RustAnkiBackend.Service.sync,
            method: RustAnkiBackend.SyncMethod.syncLogin,
            request: request
        )
        return response.hkey
    }

    public func sync(
        hostKey: String,
        endpoint: String = "",
        includeMedia: Bool = true
    ) throws -> SaidSyncResult {
        var auth = Anki_Sync_SyncAuth()
        auth.hkey = hostKey
        if !endpoint.isEmpty { auth.endpoint = endpoint }
        var request = Anki_Sync_SyncCollectionRequest()
        request.auth = auth
        request.syncMedia = includeMedia
        let response: Anki_Sync_SyncCollectionResponse = try backend.invoke(
            service: RustAnkiBackend.Service.sync,
            method: RustAnkiBackend.SyncMethod.syncCollection,
            request: request
        )
        let requirement: SaidSyncRequirement
        switch response.required {
        case .noChanges: requirement = .noChanges
        case .normalSync: requirement = .normal
        case .fullSync: requirement = .chooseFullSync
        case .fullDownload: requirement = .fullDownload
        case .fullUpload: requirement = .fullUpload
        case .UNRECOGNIZED: requirement = .chooseFullSync
        }
        return SaidSyncResult(
            requirement: requirement,
            serverMessage: response.serverMessage,
            endpoint: response.hasNewEndpoint ? response.newEndpoint : nil,
            serverMediaUSN: response.serverMediaUsn
        )
    }

    public func fullSync(
        hostKey: String,
        endpoint: String = "",
        upload: Bool,
        serverMediaUSN: Int32 = 0
    ) throws {
        var auth = Anki_Sync_SyncAuth()
        auth.hkey = hostKey
        if !endpoint.isEmpty { auth.endpoint = endpoint }
        var request = Anki_Sync_FullUploadOrDownloadRequest()
        request.auth = auth
        request.upload = upload
        request.serverUsn = serverMediaUSN
        try backend.callVoid(
            service: RustAnkiBackend.Service.sync,
            method: RustAnkiBackend.SyncMethod.fullUploadOrDownload,
            request: request
        )
        try backend.reopenAfterFullSync()
    }

    public func abortSync() throws {
        try backend.callVoid(
            service: RustAnkiBackend.Service.sync,
            method: RustAnkiBackend.SyncMethod.abortSync
        )
        try? backend.callVoid(
            service: RustAnkiBackend.Service.sync,
            method: RustAnkiBackend.SyncMethod.abortMediaSync
        )
    }

    public func undo() throws {
        try backend.callVoid(
            service: RustAnkiBackend.Service.collectionOps,
            method: RustAnkiBackend.CollectionOpsMethod.undo
        )
    }

    public func canUndo() throws -> Bool {
        let response: Anki_Collection_UndoStatus = try backend.invoke(
            service: RustAnkiBackend.Service.collectionOps,
            method: RustAnkiBackend.CollectionOpsMethod.getUndoStatus
        )
        return !response.undo.isEmpty
    }

    public func checkDatabase() throws -> [String] {
        let response: Anki_Collection_CheckDatabaseResponse = try backend.invoke(
            service: RustAnkiBackend.Service.collectionOps,
            method: RustAnkiBackend.CollectionOpsMethod.checkDatabase
        )
        return response.problems
    }

    private func mapDeck(_ node: Anki_Decks_DeckTreeNode) -> SaidDeck {
        SaidDeck(
            id: node.deckID,
            name: node.name,
            level: node.level,
            newCount: Int(node.newCount),
            learningCount: Int(node.learnCount),
            reviewCount: Int(node.reviewCount),
            totalInDeck: Int(node.totalInDeck),
            totalIncludingChildren: Int(node.totalIncludingChildren),
            filtered: node.filtered,
            children: node.children.map(mapDeck)
        )
    }

    private func findDeck(id: Int64, in nodes: [SaidDeck]) -> SaidDeck? {
        for node in nodes {
            if node.id == id { return node }
            if let child = findDeck(id: id, in: node.children) { return child }
        }
        return nil
    }

    private func reviewTotal(
        _ reviews: Anki_Stats_GraphsResponse.ReviewCountsAndTimes.Reviews
    ) -> UInt32 {
        reviews.learn + reviews.relearn + reviews.young + reviews.mature + reviews.filtered
    }

    private func retentionFor(
        days: UInt32,
        response: Anki_Stats_GraphsResponse
    ) -> Double? {
        let stats: Anki_Stats_GraphsResponse.TrueRetentionStats.TrueRetention
        if days <= 7 {
            stats = response.trueRetention.week
        } else if days <= 31 {
            stats = response.trueRetention.month
        } else {
            stats = response.trueRetention.year
        }
        let passed = stats.youngPassed + stats.maturePassed
        let total = passed + stats.youngFailed + stats.matureFailed
        return total == 0 ? nil : Double(passed) / Double(total)
    }

    private func buttonsFor(
        days: UInt32,
        response: Anki_Stats_GraphsResponse
    ) -> (counts: [UInt32], days: UInt32) {
        let source: Anki_Stats_GraphsResponse.Buttons.ButtonCounts
        let sourceDays: UInt32
        if days <= 30 {
            source = response.buttons.oneMonth
            sourceDays = 30
        } else if days <= 90 {
            source = response.buttons.threeMonths
            sourceDays = 90
        } else if days <= 365 {
            source = response.buttons.oneYear
            sourceDays = 365
        } else {
            source = response.buttons.allTime
            sourceDays = 0
        }
        var counts = [UInt32](repeating: 0, count: 4)
        for values in [source.learning, source.young, source.mature] {
            for index in 0..<min(values.count, counts.count) {
                counts[index] += values[index]
            }
        }
        return (counts, sourceDays)
    }

    private func sortedBuckets(_ values: [UInt32: UInt32]) -> [SaidCountBucket] {
        values.keys.sorted().map {
            SaidCountBucket(bucket: $0, count: values[$0] ?? 0)
        }
    }

    private func renderNodes(
        _ nodes: [Anki_CardRendering_RenderedTemplateNode]
    ) -> String {
        nodes.map { node in
            switch node.value {
            case .text(let text): return text
            case .replacement(let replacement): return replacement.currentText
            case .none: return ""
            }
        }.joined()
    }

    private func scheduledSeconds(
        _ state: Anki_Scheduler_SchedulingState
    ) -> UInt32 {
        switch state.kind {
        case .normal(let normal):
            return normalSeconds(normal)
        case .filtered(let filtered):
            switch filtered.kind {
            case .rescheduling(let rescheduling):
                return normalSeconds(rescheduling.originalState)
            case .preview(let preview):
                return preview.scheduledSecs
            case .none:
                return 0
            }
        case .none:
            return 0
        }
    }

    private func normalSeconds(
        _ state: Anki_Scheduler_SchedulingState.Normal
    ) -> UInt32 {
        switch state.kind {
        case .new: return 0
        case .learning(let learning): return learning.scheduledSecs
        case .review(let review): return review.scheduledDays * 86_400
        case .relearning(let relearning):
            return relearning.learning.scheduledSecs
        case .none: return 0
        }
    }

    private func formatInterval(_ seconds: UInt32) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 30 { return "\(days)d" }
        let months = days / 30
        if months < 12 { return "\(months)mo" }
        return String(format: "%.1fy", Double(days) / 365)
    }
}
