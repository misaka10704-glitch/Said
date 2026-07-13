import AnkiRustLib
import AnkiProto
import Foundation
import SwiftProtobuf

public final class RustAnkiBackend: @unchecked Sendable {
    private let backendPtr: Int64
    private let lock = NSLock()

    /// Stored collection paths for close/reopen after full sync.
    private var collectionPath: String?
    private var mediaFolderPath: String?
    private var mediaDbPath: String?

    /// Absolute path of the open collection's media folder, or nil if no
    /// collection is currently open. Access is serialized with backend calls.
    public var currentMediaFolderPath: String? {
        lock.lock()
        defer { lock.unlock() }
        return mediaFolderPath
    }

    public init(preferredLangs: [String] = ["en"]) throws {
        var initMsg = Anki_Backend_BackendInit()
        initMsg.preferredLangs = preferredLangs
        initMsg.server = false

        let initBytes = try initMsg.serializedData()
        var ptr: Int64 = 0

        let result = initBytes.withUnsafeBytes { buf in
            anki_open_backend(
                buf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                buf.count,
                &ptr
            )
        }

        guard result == 0, ptr != 0 else {
            throw BackendError(kind: .ioError, message: "Failed to initialize Anki backend")
        }
        self.backendPtr = ptr
    }

    deinit {
        anki_close_backend(backendPtr)
    }

    // MARK: - Typed RPC (package — use AnkiServices, not these directly)

    public func invoke<Req: SwiftProtobuf.Message, Resp: SwiftProtobuf.Message>(
        service: UInt32, method: UInt32, request: Req
    ) throws -> Resp {
        let responseBytes = try call(service: service, method: method, request: request)
        return try Resp(serializedBytes: responseBytes)
    }

    public func invoke<Resp: SwiftProtobuf.Message>(
        service: UInt32, method: UInt32
    ) throws -> Resp {
        let responseBytes = try callRaw(service: service, method: method, input: Data())
        return try Resp(serializedBytes: responseBytes)
    }

    public func call(
        service: UInt32, method: UInt32,
        request: some SwiftProtobuf.Message
    ) throws -> Data {
        let inputBytes = try request.serializedData()
        return try callRaw(service: service, method: method, input: inputBytes)
    }

    public func call(service: UInt32, method: UInt32) throws -> Data {
        try callRaw(service: service, method: method, input: Data())
    }

    public func callVoid(
        service: UInt32, method: UInt32,
        request: some SwiftProtobuf.Message
    ) throws {
        _ = try call(service: service, method: method, request: request)
    }

    public func callVoid(service: UInt32, method: UInt32) throws {
        _ = try call(service: service, method: method)
    }

    // MARK: - Collection Lifecycle

    public func openCollection(
        collectionPath: String,
        mediaFolderPath: String,
        mediaDbPath: String
    ) throws {
        // Store paths for reopen after full sync
        lock.lock()
        self.collectionPath = collectionPath
        self.mediaFolderPath = mediaFolderPath
        self.mediaDbPath = mediaDbPath
        lock.unlock()

        var req = Anki_Collection_OpenCollectionRequest()
        req.collectionPath = collectionPath
        req.mediaFolderPath = mediaFolderPath
        req.mediaDbPath = mediaDbPath
        try callVoid(service: Service.collection, method: CollectionMethod.open, request: req)
    }

    /// Reopen the collection after a full sync (which replaces the DB file).
    /// The Rust backend internally reopens, but we call close+open at our layer
    /// to ensure consistency (same pattern as AnkiDroid).
    public func reopenAfterFullSync() throws {
        lock.lock()
        let storedPaths = (collectionPath, mediaFolderPath, mediaDbPath)
        lock.unlock()

        guard let path = storedPaths.0,
              let media = storedPaths.1,
              let mediaDb = storedPaths.2
        else { return }

        // Close our side (Rust may already have reopened internally)
        try? closeCollection()

        // Reopen with the same paths
        try openCollection(
            collectionPath: path,
            mediaFolderPath: media,
            mediaDbPath: mediaDb
        )
    }

    public func closeCollection(downgradeToSchema11: Bool = false) throws {
        var req = Anki_Collection_CloseCollectionRequest()
        req.downgradeToSchema11 = downgradeToSchema11
        try callVoid(service: Service.collection, method: CollectionMethod.close, request: req)

        lock.lock()
        collectionPath = nil
        mediaFolderPath = nil
        mediaDbPath = nil
        lock.unlock()
    }

    // MARK: - Collection Config (typed JSON helpers)

    /// Fetches a JSON-encoded value from the Anki collection config under
    /// `key` and decodes it as `T`. Returns nil if the key has never been
    /// set (`notFoundError` from the backend).
    public func getConfigJSONValue<T: Decodable>(
        for key: String,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T? {
        var req = Anki_Generic_String()
        req.val = key
        do {
            let response: Anki_Generic_Json = try invoke(
                service: Service.config,
                method: ConfigMethod.getConfigJson,
                request: req
            )
            return try decoder.decode(T.self, from: response.json)
        } catch let error as BackendError where error.kind == .notFoundError {
            return nil
        }
    }

    /// Encodes `value` as JSON and writes it under `key` in the collection
    /// config. Uses the no-undo variant — config writes are not part of
    /// the user-visible undo stack.
    public func setConfigJSONValue<T: Encodable>(
        _ value: T,
        for key: String,
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        var req = Anki_Config_SetConfigJsonRequest()
        req.key = key
        req.valueJson = try encoder.encode(value)
        req.undoable = false
        try callVoid(
            service: Service.config,
            method: ConfigMethod.setConfigJsonNoUndo,
            request: req
        )
    }

    /// Removes a collection-config key. No-op if the key was never set.
    public func removeConfigValue(for key: String) throws {
        var req = Anki_Generic_String()
        req.val = key
        try callVoid(service: Service.config, method: ConfigMethod.removeConfig, request: req)
    }

    /// Raw `Data?` accessors for the collection-config store. Used by
    /// abstraction layers that want to shuttle opaque JSON bytes without
    /// committing to a specific Codable type at the boundary.
    public func getConfigRawJSON(for key: String) throws -> Data? {
        var req = Anki_Generic_String()
        req.val = key
        do {
            let response: Anki_Generic_Json = try invoke(
                service: Service.config,
                method: ConfigMethod.getConfigJson,
                request: req
            )
            return response.json
        } catch let error as BackendError where error.kind == .notFoundError {
            return nil
        }
    }

    public func setConfigRawJSON(_ json: Data, for key: String) throws {
        var req = Anki_Config_SetConfigJsonRequest()
        req.key = key
        req.valueJson = json
        req.undoable = false
        try callVoid(
            service: Service.config,
            method: ConfigMethod.setConfigJsonNoUndo,
            request: req
        )
    }

    // MARK: - Raw FFI

    private func callRaw(service: UInt32, method: UInt32, input: Data) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        var outPtr: UnsafeMutablePointer<UInt8>? = nil
        var outLen: Int = 0

        let status: Int32
        if input.isEmpty {
            status = anki_run_method(backendPtr, service, method, nil, 0, &outPtr, &outLen)
        } else {
            status = input.withUnsafeBytes { buf in
                anki_run_method(
                    backendPtr, service, method,
                    buf.baseAddress?.assumingMemoryBound(to: UInt8.self), buf.count,
                    &outPtr, &outLen
                )
            }
        }

        defer {
            if let outPtr { anki_free_response(outPtr, outLen) }
        }

        let responseData: Data
        if let outPtr, outLen > 0 {
            responseData = Data(bytes: outPtr, count: outLen)
        } else {
            responseData = Data()
        }

        switch status {
        case 0: return responseData
        case 1: throw BackendError(errorBytes: responseData)
        default: throw BackendError(kind: .ioError, message: "FFI error (status \(status))")
        }
    }
}

// MARK: - Service Constants (package — implementation detail of AnkiServices)

extension RustAnkiBackend {
    public enum Service {
        public static let sync: UInt32 = 1
        public static let collectionOps: UInt32 = 3
        public static let collection: UInt32 = 3
        public static let cards: UInt32 = 5
        public static let decks: UInt32 = 7
        public static let scheduler: UInt32 = 13
        public static let notetypes: UInt32 = 23
        public static let notes: UInt32 = 25
        public static let config: UInt32 = 9
        public static let deckConfig: UInt32 = 11
        public static let cardRendering: UInt32 = 27
        public static let search: UInt32 = 29
        public static let imageOcclusion: UInt32 = 35
        public static let importExport: UInt32 = 37
        public static let media: UInt32 = 39
        public static let stats: UInt32 = 41
        public static let tags: UInt32 = 43
    }

    public enum CollectionOpsMethod {
        // CollectionService methods follow the five backend-only collection
        // methods (open/close/backup/wait/progress) and setWantsAbort.
        public static let checkDatabase: UInt32 = 6
        public static let getUndoStatus: UInt32 = 7
        public static let undo: UInt32 = 8
    }

    public enum CollectionMethod {
        public static let open: UInt32 = 0
        public static let close: UInt32 = 1
        public static let createBackup: UInt32 = 2
        public static let awaitBackupCompletion: UInt32 = 3
        public static let latestProgress: UInt32 = 4
    }

    // BackendConfigService (service 9). Method indices verified against
    // the DreamAfar fork's AnkiBackend dispatch table.
    public enum ConfigMethod {
        public static let getConfigJson: UInt32 = 0
        public static let setConfigJson: UInt32 = 1
        public static let setConfigJsonNoUndo: UInt32 = 2
        public static let removeConfig: UInt32 = 3
    }

    public enum SyncMethod {
        public static let syncMedia: UInt32 = 0
        public static let abortMediaSync: UInt32 = 1
        public static let mediaSyncStatus: UInt32 = 2
        public static let syncLogin: UInt32 = 3
        public static let syncStatus: UInt32 = 4
        public static let syncCollection: UInt32 = 5
        public static let fullUploadOrDownload: UInt32 = 6
        public static let abortSync: UInt32 = 7
    }

    // Method indices from BackendSchedulerService (service 13) dispatch table.
    // Backend-level has 3 extra methods at start (computeFsrsParams, benchmark, exportDataset)
    // so Collection-level indices are offset by +3.
    public enum SchedulerMethod {
        public static let getQueuedCards: UInt32 = 3
        public static let answerCard: UInt32 = 4
        public static let schedTimingToday: UInt32 = 5
        public static let extendLimits: UInt32 = 9
        public static let countsForDeckToday: UInt32 = 10
        public static let congratsInfo: UInt32 = 11
        public static let buryOrSuspendCards: UInt32 = 14
        public static let emptyFilteredDeck: UInt32 = 15
        public static let rebuildFilteredDeck: UInt32 = 16
        public static let scheduleCardsAsNew: UInt32 = 17
        public static let describeNextStates: UInt32 = 24
        public static let customStudy: UInt32 = 27
        public static let customStudyDefaults: UInt32 = 28
        // Backend-only methods at the front of the dispatch table; verified
        // against ankitects/anki rslib/src/services/scheduler.rs and the
        // DreamAfar fork (matches Collection indices + 3 offset).
        public static let computeFsrsParams: UInt32 = 30
        public static let simulateFsrsReview: UInt32 = 33
        public static let simulateFsrsWorkload: UInt32 = 34
    }

    // BackendDeckConfigService (service 11). Method indices verified against
    // the DreamAfar fork's AnkiBackend dispatch table.
    public enum DeckConfigMethod {
        public static let getDeckConfig: UInt32 = 1
        public static let getDeckConfigsForUpdate: UInt32 = 6
        public static let updateDeckConfigs: UInt32 = 7
        public static let getRetentionWorkload: UInt32 = 11
    }

    public enum NotesMethod {
        public static let newNote: UInt32 = 0
        public static let addNote: UInt32 = 1
        public static let removeNotes: UInt32 = 3  // verified dispatch index
        public static let updateNotes: UInt32 = 5
        public static let getNote: UInt32 = 6
    }

    public enum DecksMethod {
        public static let newDeck: UInt32 = 0
        public static let addDeck: UInt32 = 1
        public static let addOrUpdateDeckLegacy: UInt32 = 3
        public static let getDeckTree: UInt32 = 4
        public static let getDeck: UInt32 = 8
        public static let updateDeck: UInt32 = 9
        public static let getDeckNames: UInt32 = 13
        public static let removeDecks: UInt32 = 16
        public static let reparentDecks: UInt32 = 17
        public static let renameDeck: UInt32 = 18
        public static let setCurrentDeck: UInt32 = 22
        public static let getCurrentDeck: UInt32 = 23
    }

    public enum SearchMethod {
        public static let searchCards: UInt32 = 1
        public static let searchNotes: UInt32 = 2
    }

    public enum TagsMethod {
        public static let clearUnusedTags: UInt32 = 0
        public static let allTags: UInt32 = 1
        public static let removeTags: UInt32 = 2
        public static let setTagCollapsed: UInt32 = 3
        public static let tagTree: UInt32 = 4
        public static let reparentTags: UInt32 = 5
        public static let renameTags: UInt32 = 6
        public static let addNoteTags: UInt32 = 7
        public static let removeNoteTags: UInt32 = 8
        public static let findAndReplaceTag: UInt32 = 9
        public static let completeTag: UInt32 = 10
    }

    public enum ImageOcclusionMethod {
        // BackendImageOcclusionService (service 35) — delegated from upstream
        // ImageOcclusionService method indices.
        public static let getImageForOcclusion: UInt32 = 0
        public static let getImageOcclusionNote: UInt32 = 1
        public static let getImageOcclusionFields: UInt32 = 2
        public static let addImageOcclusionNotetype: UInt32 = 3
        public static let addImageOcclusionNote: UInt32 = 4
        public static let updateImageOcclusionNote: UInt32 = 5
    }

    public enum MediaMethod {
        public static let checkMedia: UInt32 = 0
        public static let addMediaFile: UInt32 = 1
        public static let trashMediaFiles: UInt32 = 2
        public static let emptyTrash: UInt32 = 3
        public static let restoreTrash: UInt32 = 4
    }

    // BackendCardRenderingService (27) has 6 extra methods before renderExistingCard
    public enum CardRenderingMethod {
        public static let getEmptyCards: UInt32 = 5
        public static let renderExistingCard: UInt32 = 6
        public static let renderUncommittedCard: UInt32 = 7
        public static let compareAnswer: UInt32 = 15
        public static let extractClozeForTyping: UInt32 = 16
    }

    public enum CardsMethod {
        public static let getCard: UInt32 = 0
        public static let removeCards: UInt32 = 2
        public static let setDeck: UInt32 = 3
        public static let setFlag: UInt32 = 4
    }

    public enum NotetypesMethod {
        public static let updateNotetype: UInt32 = 1
        public static let getNotetype: UInt32 = 6
        public static let getNotetypeNames: UInt32 = 8
        public static let removeNotetype: UInt32 = 11
    }

    public enum ImportExportMethod {
        public static let importCollectionPackage: UInt32 = 0
        public static let exportCollectionPackage: UInt32 = 1
        public static let importAnkiPackage: UInt32 = 2
        public static let getImportAnkiPackagePresets: UInt32 = 3
        public static let exportAnkiPackage: UInt32 = 4
        public static let getCsvMetadata: UInt32 = 5
        public static let importCsv: UInt32 = 6
        public static let exportNoteCsv: UInt32 = 7
        public static let exportCardCsv: UInt32 = 8
    }

    public enum StatsMethod {
        public static let cardStats: UInt32 = 0
        public static let graphs: UInt32 = 2
    }
}
