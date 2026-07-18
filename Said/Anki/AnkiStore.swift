import Foundation

/// App-wide collection singleton + Documents paths.
final class AnkiStore {
    static let shared = AnkiStore()

    let documentsURL: URL
    let collectionRoot: URL
    private(set) var collection: OfficialAnkiCollection?

    private init() {
        documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        collectionRoot = documentsURL.appendingPathComponent("AnkiCollection", isDirectory: true)
    }

    func bootstrapIfNeeded() {
        try? FileManager.default.createDirectory(at: collectionRoot, withIntermediateDirectories: true)
        collection = try? OfficialAnkiCollection(rootURL: collectionRoot)
    }

    @discardableResult
    func importApkg(_ url: URL) throws -> SaidApkgImportResult {
        let col = try requireCollection()
        let result = try col.importApkg(from: url)
        collection = col
        return result
    }

    func exportApkg(to url: URL, options: SaidApkgExportOptions) throws {
        guard let col = collection else { throw AnkiError.exportFailed("尚无集合") }
        try col.exportApkg(to: url, options: options)
    }

    func exportApkg(to url: URL) throws {
        try exportApkg(to: url, options: .deviceMigration())
    }

    func requireCollection() throws -> OfficialAnkiCollection {
        if let c = collection { return c }
        bootstrapIfNeeded()
        guard let c = collection else { throw AnkiError.openFailed("请先导入 .apkg") }
        return c
    }
}
