import Foundation
import SaidAnkiBackend

struct BrowserCardRow: Equatable {
    let cardID: Int64
    let noteID: Int64
    let front: String
    let back: String
    let deckName: String
    let templateName: String
    let dueText: String
    let isSuspended: Bool
    let isBuried: Bool
    let flag: Int
    let tags: [String]
}

struct BrowserCardPage {
    let cards: [BrowserCardRow]
    let nextCursor: String?
    let totalCount: Int
}

enum BrowserCardAction {
    case suspend
    case bury
    case flag(Int)
    case delete
    case move(deckID: Int64)
    case addTags([String])
}

struct BrowserDeckChoice {
    let id: Int64
    let name: String
}

protocol BrowserDataProviding: AnyObject {
    func fetchCards(matching query: String, cursor: String?, pageSize: Int,
                    completion: @escaping (Result<BrowserCardPage, Error>) -> Void)
    func perform(action: BrowserCardAction, cardIDs: [Int64],
                 completion: @escaping (Result<Void, Error>) -> Void)
    func fetchDeckChoices(completion: @escaping (Result<[BrowserDeckChoice], Error>) -> Void)
}

struct EditableNoteField: Equatable {
    let name: String
    var value: String
}

struct EditableNote: Equatable {
    let noteID: Int64
    let modelName: String
    var fields: [EditableNoteField]
    var tags: [String]
}

enum NoteEditorMediaKind {
    case attachment
    case recording
}

struct NoteEditorMediaInsertion {
    let fieldIndex: Int
    let markup: String
}

protocol NoteEditorDataProviding: AnyObject {
    func loadNote(noteID: Int64, completion: @escaping (Result<EditableNote, Error>) -> Void)
    func saveNote(_ note: EditableNote, completion: @escaping (Result<Void, Error>) -> Void)
    func createMedia(kind: NoteEditorMediaKind, for note: EditableNote, preferredFieldIndex: Int,
                     completion: @escaping (Result<NoteEditorMediaInsertion, Error>) -> Void)
    func storeMedia(data: Data, suggestedName: String, fieldIndex: Int,
                    completion: @escaping (Result<NoteEditorMediaInsertion, Error>) -> Void)
}

enum StatisticsPeriod: Int {
    case week
    case month
    case year
}

struct StatisticsSummary {
    let reviewed: Int
    let minutesStudied: Int
    let retention: Double?
    let streakDays: Int
}

struct StatisticsPoint {
    let label: String
    let value: Double
}

enum StatisticsChartStyle {
    case bars
    case line
}

struct StatisticsChart {
    let title: String
    let style: StatisticsChartStyle
    let points: [StatisticsPoint]
}

struct StatisticsFact {
    let title: String
    let value: String
}

struct StatisticsDeckChoice: Equatable {
    let id: Int64
    let name: String
}

struct StatisticsSnapshot {
    let summary: StatisticsSummary
    let facts: [StatisticsFact]
    let charts: [StatisticsChart]
    let isEmpty: Bool
}

protocol StatisticsDataProviding: AnyObject {
    func loadStatistics(period: StatisticsPeriod, deckID: Int64?,
                        completion: @escaping (Result<StatisticsSnapshot, Error>) -> Void)
    func loadStatisticsDecks(
        completion: @escaping (Result<[StatisticsDeckChoice], Error>) -> Void
    )
}

struct DeckOptions {
    let deckID: Int64
    let deckName: String
    var desiredRetention: Double
    var newCardsPerDay: Int
    var reviewsPerDay: Int
    var buryNewSiblings: Bool
    var buryReviewSiblings: Bool
    var buryInterdayLearningSiblings: Bool
}

protocol DeckOptionsDataProviding: AnyObject {
    func loadOptions(deckID: Int64, completion: @escaping (Result<DeckOptions, Error>) -> Void)
    func saveOptions(_ options: DeckOptions, completion: @escaping (Result<Void, Error>) -> Void)
}

struct DeckManagementNode: Equatable {
    let id: Int64
    let name: String
    let level: UInt32
    let filtered: Bool
    let newCount: Int
    let learningCount: Int
    let reviewCount: Int
    let totalInDeck: Int
    let totalIncludingChildren: Int
    let children: [DeckManagementNode]
}

struct DeckManagementDetail: Equatable {
    let id: Int64
    let name: String
    let level: UInt32
    let filtered: Bool
    let description: String
    let configID: Int64?
    let newCount: Int
    let learningCount: Int
    let reviewCount: Int
    let totalInDeck: Int
    let totalIncludingChildren: Int
}

struct DeckDeletionPreview: Equatable {
    let requestedDeckIDs: [Int64]
    let affectedDeckCount: Int
    let estimatedDeletedCardCount: Int
}

struct DeckDeletionResult: Equatable {
    let preview: DeckDeletionPreview
    let deletedCardCount: Int
    let backupCreated: Bool
}

struct DeckCustomStudyTag: Equatable {
    let name: String
    let included: Bool
    let excluded: Bool
}

struct DeckCustomStudyDefaults: Equatable {
    let tags: [DeckCustomStudyTag]
    let extendNew: Int
    let extendReview: Int
    let availableNew: Int
    let availableReview: Int
    let availableNewInChildren: Int
    let availableReviewInChildren: Int
}

enum DeckCustomStudyCramKind {
    case due
    case newCards
    case review
    case all
}

enum DeckCustomStudyAction {
    case increaseNewLimit(Int32)
    case increaseReviewLimit(Int32)
    case forgotten(days: UInt32)
    case reviewAhead(days: UInt32)
    case previewNew(days: UInt32)
    case cram(
        kind: DeckCustomStudyCramKind,
        cardLimit: UInt32,
        includeTags: [String],
        excludeTags: [String]
    )
}

protocol DeckManagementDataProviding: AnyObject {
    func loadDeckTree(completion: @escaping (Result<[DeckManagementNode], Error>) -> Void)
    func loadDeckDetail(
        deckID: Int64,
        completion: @escaping (Result<DeckManagementDetail, Error>) -> Void
    )
    func createDeck(
        name: String,
        completion: @escaping (Result<DeckManagementDetail, Error>) -> Void
    )
    func renameDeck(
        deckID: Int64,
        newName: String,
        completion: @escaping (Result<Void, Error>) -> Void
    )
    func reparentDecks(
        deckIDs: [Int64],
        newParentID: Int64?,
        completion: @escaping (Result<Int, Error>) -> Void
    )
    func previewDeletion(
        deckIDs: [Int64],
        completion: @escaping (Result<DeckDeletionPreview, Error>) -> Void
    )
    func deleteDecks(
        deckIDs: [Int64],
        completion: @escaping (Result<DeckDeletionResult, Error>) -> Void
    )
    func undoLastOperation(completion: @escaping (Result<Void, Error>) -> Void)
    func exportDeck(
        deckID: Int64,
        to url: URL,
        includeScheduling: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    )
    func loadCustomStudyDefaults(
        deckID: Int64,
        completion: @escaping (Result<DeckCustomStudyDefaults, Error>) -> Void
    )
    func extendLimits(
        deckID: Int64,
        newDelta: Int32,
        reviewDelta: Int32,
        completion: @escaping (Result<Void, Error>) -> Void
    )
    func startCustomStudy(
        deckID: Int64,
        action: DeckCustomStudyAction,
        completion: @escaping (Result<Void, Error>) -> Void
    )
}

/// Serializes every rslib access off the main thread. This provider is kept
/// separate from DeckListViewController so later UI work can adopt it without
/// changing the existing deck-list behavior.
final class OfficialDeckManagementProvider: DeckManagementDataProviding {
    private let queue = DispatchQueue(label: "com.said.anki.deck-management")

    private func collection() throws -> OfficialAnkiCollection {
        try AnkiStore.shared.requireCollection()
    }

    func loadDeckTree(completion: @escaping (Result<[DeckManagementNode], Error>) -> Void) {
        perform(completion: completion) {
            try self.collection().deckTree().map(self.mapDeck)
        }
    }

    func loadDeckDetail(
        deckID: Int64,
        completion: @escaping (Result<DeckManagementDetail, Error>) -> Void
    ) {
        perform(completion: completion) {
            self.mapDetail(try self.collection().deckDetail(id: deckID))
        }
    }

    func createDeck(
        name: String,
        completion: @escaping (Result<DeckManagementDetail, Error>) -> Void
    ) {
        perform(completion: completion) {
            self.mapDetail(try self.collection().createDeck(name: name))
        }
    }

    func renameDeck(
        deckID: Int64,
        newName: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        perform(completion: completion) {
            try self.collection().renameDeck(id: deckID, newName: newName)
        }
    }

    func reparentDecks(
        deckIDs: [Int64],
        newParentID: Int64?,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        perform(completion: completion) {
            try self.collection().reparentDecks(ids: deckIDs, newParentID: newParentID)
        }
    }

    func previewDeletion(
        deckIDs: [Int64],
        completion: @escaping (Result<DeckDeletionPreview, Error>) -> Void
    ) {
        perform(completion: completion) {
            self.mapDeletionPreview(try self.collection().deckDeletionPreview(ids: deckIDs))
        }
    }

    func deleteDecks(
        deckIDs: [Int64],
        completion: @escaping (Result<DeckDeletionResult, Error>) -> Void
    ) {
        perform(completion: completion) {
            let result = try self.collection().deleteDecks(ids: deckIDs)
            return DeckDeletionResult(
                preview: self.mapDeletionPreview(result.preview),
                deletedCardCount: result.deletedCardCount,
                backupCreated: result.backupCreated
            )
        }
    }

    func undoLastOperation(completion: @escaping (Result<Void, Error>) -> Void) {
        perform(completion: completion) {
            try self.collection().undo()
        }
    }

    func exportDeck(
        deckID: Int64,
        to url: URL,
        includeScheduling: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        perform(completion: completion) {
            try self.collection().exportDeck(
                id: deckID,
                to: url,
                includeScheduling: includeScheduling
            )
        }
    }

    func loadCustomStudyDefaults(
        deckID: Int64,
        completion: @escaping (Result<DeckCustomStudyDefaults, Error>) -> Void
    ) {
        perform(completion: completion) {
            let defaults = try self.collection().customStudyDefaults(deckID: deckID)
            return DeckCustomStudyDefaults(
                tags: defaults.tags.map {
                    DeckCustomStudyTag(
                        name: $0.name,
                        included: $0.included,
                        excluded: $0.excluded
                    )
                },
                extendNew: defaults.extendNew,
                extendReview: defaults.extendReview,
                availableNew: defaults.availableNew,
                availableReview: defaults.availableReview,
                availableNewInChildren: defaults.availableNewInChildren,
                availableReviewInChildren: defaults.availableReviewInChildren
            )
        }
    }

    func extendLimits(
        deckID: Int64,
        newDelta: Int32,
        reviewDelta: Int32,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        perform(completion: completion) {
            try self.collection().extendDeckLimits(
                deckID: deckID,
                newDelta: newDelta,
                reviewDelta: reviewDelta
            )
        }
    }

    func startCustomStudy(
        deckID: Int64,
        action: DeckCustomStudyAction,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        perform(completion: completion) {
            try self.collection().startCustomStudy(
                deckID: deckID,
                mode: self.mapCustomStudy(action)
            )
        }
    }

    private func perform<T>(
        completion: @escaping (Result<T, Error>) -> Void,
        operation: @escaping () throws -> T
    ) {
        queue.async {
            do { completion(.success(try operation())) }
            catch { completion(.failure(error)) }
        }
    }

    private func mapDeck(_ deck: SaidDeck) -> DeckManagementNode {
        DeckManagementNode(
            id: deck.id,
            name: deck.name,
            level: deck.level,
            filtered: deck.filtered,
            newCount: deck.newCount,
            learningCount: deck.learningCount,
            reviewCount: deck.reviewCount,
            totalInDeck: deck.totalInDeck,
            totalIncludingChildren: deck.totalIncludingChildren,
            children: deck.children.map(mapDeck)
        )
    }

    private func mapDetail(_ detail: SaidDeckDetail) -> DeckManagementDetail {
        DeckManagementDetail(
            id: detail.id,
            name: detail.name,
            level: detail.level,
            filtered: detail.filtered,
            description: detail.description,
            configID: detail.configID,
            newCount: detail.newCount,
            learningCount: detail.learningCount,
            reviewCount: detail.reviewCount,
            totalInDeck: detail.totalInDeck,
            totalIncludingChildren: detail.totalIncludingChildren
        )
    }

    private func mapDeletionPreview(
        _ preview: OfficialDeckDeletionPreview
    ) -> DeckDeletionPreview {
        DeckDeletionPreview(
            requestedDeckIDs: preview.requestedDeckIDs,
            affectedDeckCount: preview.affectedDeckCount,
            estimatedDeletedCardCount: preview.estimatedDeletedCardCount
        )
    }

    private func mapCustomStudy(_ action: DeckCustomStudyAction) -> SaidCustomStudy {
        switch action {
        case .increaseNewLimit(let delta):
            return .increaseNewLimit(delta)
        case .increaseReviewLimit(let delta):
            return .increaseReviewLimit(delta)
        case .forgotten(let days):
            return .forgotten(days: days)
        case .reviewAhead(let days):
            return .reviewAhead(days: days)
        case .previewNew(let days):
            return .previewNew(days: days)
        case .cram(let kind, let cardLimit, let includeTags, let excludeTags):
            let backendKind: SaidCustomStudyCramKind
            switch kind {
            case .due: backendKind = .due
            case .newCards: backendKind = .newCards
            case .review: backendKind = .review
            case .all: backendKind = .all
            }
            return .cram(
                kind: backendKind,
                cardLimit: cardLimit,
                includeTags: includeTags,
                excludeTags: excludeTags
            )
        }
    }
}

struct SyncCredentials {
    let username: String
    let password: String
}

enum SyncConflictResolution {
    case uploadLocal
    case downloadRemote
}

enum SyncPhase {
    case signedOut
    case authenticating
    case ready(accountName: String)
    case syncing(progress: Float, message: String)
    case conflict(localDescription: String, remoteDescription: String)
    case completed(message: String)
    case failed(message: String)
}

protocol SyncDataProviding: AnyObject {
    var stateDidChange: ((SyncPhase) -> Void)? { get set }
    func currentState(completion: @escaping (SyncPhase) -> Void)
    func logIn(credentials: SyncCredentials)
    func logOut()
    func startSync()
    func cancelSync()
    func resolveConflict(_ resolution: SyncConflictResolution)
}

private enum OfficialProviderError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        }
    }
}

final class OfficialBrowserProvider: BrowserDataProviding, NoteEditorDataProviding,
    StatisticsDataProviding, DeckOptionsDataProviding {
    private let queue = DispatchQueue(label: "com.said.anki.management")

    private func collection() throws -> OfficialAnkiCollection {
        try AnkiStore.shared.requireCollection()
    }

    func fetchCards(matching query: String, cursor: String?, pageSize: Int,
                    completion: @escaping (Result<BrowserCardPage, Error>) -> Void) {
        queue.async {
            do {
                let offset = Int(cursor ?? "") ?? 0
                let page = try self.collection().browserPage(
                    query: query,
                    offset: offset,
                    limit: pageSize
                )
                let next = offset + page.rows.count < page.total
                    ? String(offset + page.rows.count) : nil
                completion(.success(BrowserCardPage(
                    cards: page.rows,
                    nextCursor: next,
                    totalCount: page.total
                )))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func perform(action: BrowserCardAction, cardIDs: [Int64],
                 completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            do {
                try self.collection().performBrowserAction(action, cardIDs: cardIDs)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func fetchDeckChoices(completion: @escaping (Result<[BrowserDeckChoice], Error>) -> Void) {
        queue.async {
            do {
                completion(.success(try self.collection().listDecks().map {
                    BrowserDeckChoice(id: $0.id, name: $0.name)
                }))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func loadNote(noteID: Int64, completion: @escaping (Result<EditableNote, Error>) -> Void) {
        queue.async {
            do { completion(.success(try self.collection().editableNote(id: noteID))) }
            catch { completion(.failure(error)) }
        }
    }

    func saveNote(_ note: EditableNote, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            do {
                try self.collection().saveEditableNote(note)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func createMedia(kind: NoteEditorMediaKind, for note: EditableNote, preferredFieldIndex: Int,
                     completion: @escaping (Result<NoteEditorMediaInsertion, Error>) -> Void) {
        completion(.failure(OfficialProviderError.unavailable(
            "The official protobuf API can store media, but this editor does not yet provide an iOS file picker or recorder."
        )))
    }

    func storeMedia(data: Data, suggestedName: String, fieldIndex: Int,
                    completion: @escaping (Result<NoteEditorMediaInsertion, Error>) -> Void) {
        queue.async {
            do {
                let name = try self.collection().storeMedia(data: data, suggestedName: suggestedName)
                let ext = (name as NSString).pathExtension.lowercased()
                let images = Set(["png", "jpg", "jpeg", "gif", "webp", "svg"])
                let markup = images.contains(ext) ? "<img src=\"\(name)\">" : "[sound:\(name)]"
                completion(.success(NoteEditorMediaInsertion(fieldIndex: fieldIndex, markup: markup)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func loadStatistics(period: StatisticsPeriod, deckID: Int64?,
                        completion: @escaping (Result<StatisticsSnapshot, Error>) -> Void) {
        queue.async {
            do {
                let days: UInt32 = period == .week ? 7 : (period == .month ? 30 : 365)
                let stats = try self.collection().statistics(days: days, deckID: deckID)
                completion(.success(self.makeStatisticsSnapshot(stats, days: days)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func loadStatisticsDecks(
        completion: @escaping (Result<[StatisticsDeckChoice], Error>) -> Void
    ) {
        queue.async {
            do {
                let choices = try self.collection().listDecks().map {
                    StatisticsDeckChoice(id: $0.id, name: $0.name)
                }
                completion(.success(choices))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func makeStatisticsSnapshot(_ stats: SaidStatistics, days: UInt32) -> StatisticsSnapshot {
        let calendar = Calendar.current
        let now = Date()
        var anchor = calendar.startOfDay(for: now)
        if calendar.component(.hour, from: now) < Int(stats.rolloverHour),
           let previousDay = calendar.date(byAdding: .day, value: -1, to: anchor) {
            anchor = previousDay
        }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = days <= 30 ? "M/d" : "MMM"

        let historyByDay = Dictionary(
            uniqueKeysWithValues: stats.reviewHistory.map { ($0.day, $0) }
        )
        let firstHistoryDay = -Int32(days) + 1
        let reviewPoints = (firstHistoryDay...0).map { day -> StatisticsPoint in
            let date = calendar.date(byAdding: .day, value: Int(day), to: anchor) ?? anchor
            return StatisticsPoint(
                label: formatter.string(from: date),
                value: Double(historyByDay[day]?.count ?? 0)
            )
        }
        let duePoints = (0..<Int32(days)).map {
            StatisticsPoint(label: "+\($0)d", value: Double(stats.futureDue[$0] ?? 0))
        }

        let activeDays = Set(stats.reviewHistory.filter { $0.count > 0 }.map(\.day))
        var streak = 0
        var streakDay: Int32 = activeDays.contains(0) ? 0 : -1
        while activeDays.contains(streakDay) {
            streak += 1
            streakDay -= 1
        }

        let cardStateValues: [(String, UInt32)] = [
            ("新卡", stats.cardStates.new),
            ("学习", stats.cardStates.learning),
            ("重学", stats.cardStates.relearning),
            ("年轻", stats.cardStates.young),
            ("成熟", stats.cardStates.mature),
            ("暂停", stats.cardStates.suspended),
            ("埋藏", stats.cardStates.buried),
        ]
        let cardCount = cardStateValues.reduce(UInt32(0)) { $0 + $1.1 }
        let dueCount = duePoints.reduce(0) { $0 + Int($1.value) }
        let isEmpty = stats.reviewed == 0 && cardCount == 0 && dueCount == 0

        var charts: [StatisticsChart] = []
        if stats.reviewed > 0 {
            charts.append(StatisticsChart(title: "复习历史", style: .bars, points: reviewPoints))
        }
        if dueCount > 0 {
            charts.append(StatisticsChart(title: "未来到期", style: .line, points: duePoints))
        }
        if cardCount > 0 {
            charts.append(StatisticsChart(
                title: "卡片状态",
                style: .bars,
                points: cardStateValues.map {
                    StatisticsPoint(label: $0.0, value: Double($0.1))
                }
            ))
        }
        if stats.buttonCounts.reduce(0, +) > 0 {
            let periodText = stats.buttonPeriodDays == 0 ? "全部" : "近 \(stats.buttonPeriodDays) 天"
            charts.append(StatisticsChart(
                title: "按键分布（\(periodText)）",
                style: .bars,
                points: zip(["重来", "困难", "良好", "简单"], stats.buttonCounts).map {
                    StatisticsPoint(label: $0.0, value: Double($0.1))
                }
            ))
        }
        if stats.fsrsEnabled {
            appendFSRSCharts(stats, to: &charts)
        }

        var facts: [StatisticsFact] = []
        if !isEmpty {
            let todayAccuracy = stats.today.answerCount == 0 ? "—" : String(
                format: "%.1f%%",
                Double(stats.today.correctCount) * 100 / Double(stats.today.answerCount)
            )
            facts = [
                StatisticsFact(title: "今日作答", value: "\(stats.today.answerCount)"),
                StatisticsFact(
                    title: "今日用时",
                    value: "\(Int(stats.today.answerMilliseconds) / 60_000) 分钟"
                ),
                StatisticsFact(title: "今日正确率", value: todayAccuracy),
                StatisticsFact(
                    title: "今日类型",
                    value: "学 \(stats.today.learnCount) · 复 \(stats.today.reviewCount) · 重 \(stats.today.relearnCount)"
                ),
                StatisticsFact(
                    title: "未来负荷",
                    value: "\(stats.futureDueDailyLoad)/天\(stats.futureDueHasBacklog ? " · 有积压" : "")"
                ),
            ]
            if stats.fsrsEnabled {
                facts.append(StatisticsFact(
                    title: "FSRS 难度中位数",
                    value: stats.medianDifficulty.map { String(format: "%.1f%%", $0) } ?? "—"
                ))
                facts.append(StatisticsFact(
                    title: "FSRS 平均可提取性",
                    value: stats.averageRetrievability.map { String(format: "%.1f%%", $0) } ?? "—"
                ))
            }
        }

        return StatisticsSnapshot(
            summary: StatisticsSummary(
                reviewed: stats.reviewed,
                minutesStudied: stats.secondsStudied / 60,
                retention: stats.retention,
                streakDays: streak
            ),
            facts: facts,
            charts: charts,
            isEmpty: isEmpty
        )
    }

    private func appendFSRSCharts(_ stats: SaidStatistics, to charts: inout [StatisticsChart]) {
        if !stats.stability.isEmpty {
            charts.append(StatisticsChart(
                title: "FSRS 稳定性（天）",
                style: .line,
                points: stats.stability.map {
                    StatisticsPoint(label: "\($0.bucket)", value: Double($0.count))
                }
            ))
        }
        if !stats.difficulty.isEmpty {
            charts.append(StatisticsChart(
                title: "FSRS 难度",
                style: .bars,
                points: stats.difficulty.map {
                    StatisticsPoint(label: "\($0.bucket)%", value: Double($0.count))
                }
            ))
        }
        if !stats.retrievability.isEmpty {
            charts.append(StatisticsChart(
                title: "FSRS 可提取性",
                style: .bars,
                points: stats.retrievability.map {
                    StatisticsPoint(label: "\($0.bucket)%", value: Double($0.count))
                }
            ))
        }
    }

    func loadOptions(deckID: Int64, completion: @escaping (Result<DeckOptions, Error>) -> Void) {
        queue.async {
            do { completion(.success(try self.collection().deckOptions(id: deckID))) }
            catch { completion(.failure(error)) }
        }
    }

    func saveOptions(_ options: DeckOptions, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            do {
                try self.collection().saveDeckOptions(options)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }
}

final class OfficialSyncProvider: SyncDataProviding {
    var stateDidChange: ((SyncPhase) -> Void)?
    private let queue = DispatchQueue(label: "com.said.anki.sync")
    private var phase: SyncPhase
    private var hostKey: String?
    private var endpoint: String
    private var serverMediaUSN: Int32 = 0
    private var accountName: String

    init() {
        let savedKey = KeychainStore.get(.ankiWebHostKey)
        endpoint = KeychainStore.get(.ankiWebEndpoint)
        accountName = KeychainStore.get(.ankiWebAccount)
        hostKey = savedKey.isEmpty ? nil : savedKey
        phase = savedKey.isEmpty
            ? .signedOut
            : .ready(accountName: accountName.isEmpty ? "AnkiWeb" : accountName)
    }

    func currentState(completion: @escaping (SyncPhase) -> Void) {
        completion(phase)
    }

    func logIn(credentials: SyncCredentials) {
        setPhase(.authenticating)
        queue.async {
            do {
                let collection = try AnkiStore.shared.requireCollection()
                let key = try collection.syncLogin(
                    username: credentials.username,
                    password: credentials.password
                )
                self.hostKey = key
                self.accountName = credentials.username
                KeychainStore.set(key, for: .ankiWebHostKey)
                KeychainStore.set(credentials.username, for: .ankiWebAccount)
                self.setPhase(.ready(accountName: credentials.username))
            } catch {
                self.setPhase(.failed(message: error.localizedDescription))
            }
        }
    }

    func logOut() {
        hostKey = nil
        endpoint = ""
        serverMediaUSN = 0
        accountName = ""
        KeychainStore.delete(.ankiWebHostKey)
        KeychainStore.delete(.ankiWebEndpoint)
        KeychainStore.delete(.ankiWebAccount)
        setPhase(.signedOut)
    }

    func startSync() {
        guard let hostKey = hostKey else {
            setPhase(.failed(message: "Sign in before syncing."))
            return
        }
        setPhase(.syncing(progress: 0.15, message: "Synchronizing collection and media…"))
        queue.async {
            do {
                let result = try AnkiStore.shared.requireCollection().sync(
                    hostKey: hostKey,
                    endpoint: self.endpoint
                )
                if let newEndpoint = result.endpoint {
                    self.endpoint = newEndpoint
                    KeychainStore.set(newEndpoint, for: .ankiWebEndpoint)
                }
                self.serverMediaUSN = result.serverMediaUSN
                switch result.requirement {
                case .noChanges, .normal:
                    self.setPhase(.completed(message:
                        result.serverMessage.isEmpty ? "Sync complete." : result.serverMessage
                    ))
                case .chooseFullSync:
                    self.setPhase(.conflict(
                        localDescription: "Upload the collection currently on this device.",
                        remoteDescription: "Replace it with the AnkiWeb collection."
                    ))
                case .fullDownload:
                    try self.runFullSync(upload: false)
                case .fullUpload:
                    try self.runFullSync(upload: true)
                }
            } catch {
                self.setPhase(.failed(message: error.localizedDescription))
            }
        }
    }

    func cancelSync() {
        queue.async {
            do {
                try AnkiStore.shared.requireCollection().abortSync()
                self.setPhase(.ready(accountName: self.accountName))
            } catch {
                self.setPhase(.failed(message: error.localizedDescription))
            }
        }
    }

    func resolveConflict(_ resolution: SyncConflictResolution) {
        queue.async {
            do { try self.runFullSync(upload: resolution == .uploadLocal) }
            catch { self.setPhase(.failed(message: error.localizedDescription)) }
        }
    }

    private func runFullSync(upload: Bool) throws {
        guard let hostKey = hostKey else {
            throw OfficialProviderError.unavailable("The AnkiWeb session has expired.")
        }
        setPhase(.syncing(progress: 0.5, message:
            upload ? "Uploading full collection…" : "Downloading full collection…"
        ))
        try AnkiStore.shared.requireCollection().fullSync(
            hostKey: hostKey,
            endpoint: endpoint,
            upload: upload,
            serverMediaUSN: serverMediaUSN
        )
        setPhase(.completed(message: "Full sync complete."))
    }

    private func setPhase(_ value: SyncPhase) {
        phase = value
        stateDidChange?(value)
    }
}
