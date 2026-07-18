import Foundation

enum SaidAppBackupError: LocalizedError {
    case invalidArchive
    case invalidManifest
    case missingCollection
    case invalidPreferences

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "不是有效的 Said 备份文件。"
        case .invalidManifest: return "备份清单无效或版本不兼容。"
        case .missingCollection: return "备份中缺少集合数据。"
        case .invalidPreferences: return "备份中的偏好设置无法读取。"
        }
    }
}

struct SaidAppBackupSummary: Equatable {
    let createdAt: Date
    let includesCollection: Bool
    let includesPreferences: Bool
    let includesKeychain: Bool
    let includesAppSupport: Bool
}

enum SaidAppBackupService {
    static let formatID = "said-backup"
    static let formatVersion = 1
    static let fileExtension = "saidbackup"

    private static let preferenceKeys = [
        "said_sidebar_collapsed",
        "said_result_panel_collapsed",
        "said_appearance_mode",
        "said_interface_scale",
        "said_deck_practice_preferences_v1",
        "said_deck_list_collapsed_v1",
        "said_speaking_result_history_v1",
    ]

    static func export(to archiveURL: URL) throws -> SaidAppBackupSummary {
        let staging = BackupBundleHelper.temporaryFolder(prefix: "said-backup-export")
        defer { BackupBundleHelper.removeIfExists(staging) }

        let collection = try AnkiStore.shared.requireCollection()
        let colpkgURL = staging.appendingPathComponent("collection.colpkg")
        try collection.exportCollectionPackage(to: colpkgURL, includeMedia: true)

        try BackupBundleHelper.exportUserDefaults(
            keys: preferenceKeys,
            to: staging.appendingPathComponent("preferences.plist")
        )

        let keychainURL = staging.appendingPathComponent("keychain.json")
        let keychainData = try JSONSerialization.data(
            withJSONObject: KeychainStore.exportSnapshot(),
            options: [.prettyPrinted, .sortedKeys]
        )
        try keychainData.write(to: keychainURL)

        let appSupportRoot = staging.appendingPathComponent("app_support", isDirectory: true)
        let supportBase = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        for name in ["EdgeTTS", "Pronounce"] {
            let source = supportBase.appendingPathComponent(name, isDirectory: true)
            try BackupBundleHelper.copyDirectory(
                from: source,
                to: appSupportRoot.appendingPathComponent(name, isDirectory: true)
            )
        }

        let manifest: [String: Any] = [
            "format": formatID,
            "version": formatVersion,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "includesCollection": true,
            "includesPreferences": true,
            "includesKeychain": true,
            "includesAppSupport": true,
        ]
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try manifestData.write(to: staging.appendingPathComponent("manifest.json"))

        BackupBundleHelper.removeIfExists(archiveURL)
        try SimpleZip.zip(directory: staging, to: archiveURL)

        return SaidAppBackupSummary(
            createdAt: Date(),
            includesCollection: true,
            includesPreferences: true,
            includesKeychain: true,
            includesAppSupport: true
        )
    }

    static func importBackup(from archiveURL: URL) throws -> SaidAppBackupSummary {
        let staging = BackupBundleHelper.temporaryFolder(prefix: "said-backup-import")
        defer { BackupBundleHelper.removeIfExists(staging) }

        try SimpleZip.unzip(archiveURL: archiveURL, to: staging)
        let manifest = try readManifest(in: staging)

        let preferencesURL = staging.appendingPathComponent("preferences.plist")
        if FileManager.default.fileExists(atPath: preferencesURL.path) {
            try BackupBundleHelper.importUserDefaults(from: preferencesURL)
        }

        let keychainURL = staging.appendingPathComponent("keychain.json")
        if FileManager.default.fileExists(atPath: keychainURL.path),
           let object = try JSONSerialization.jsonObject(with: Data(contentsOf: keychainURL)) as? [String: String] {
            KeychainStore.importSnapshot(object)
        }

        let appSupportRoot = staging.appendingPathComponent("app_support", isDirectory: true)
        if FileManager.default.fileExists(atPath: appSupportRoot.path) {
            let supportBase = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            for name in ["EdgeTTS", "Pronounce"] {
                let source = appSupportRoot.appendingPathComponent(name, isDirectory: true)
                try BackupBundleHelper.copyDirectory(
                    from: source,
                    to: supportBase.appendingPathComponent(name, isDirectory: true)
                )
            }
        }

        let colpkgURL = staging.appendingPathComponent("collection.colpkg")
        guard FileManager.default.fileExists(atPath: colpkgURL.path) else {
            throw SaidAppBackupError.missingCollection
        }
        let collection = try AnkiStore.shared.requireCollection()
        _ = try collection.createBackup(force: true)
        try collection.restoreCollectionPackage(from: colpkgURL)

        let createdAt = (manifest["createdAt"] as? String)
            .flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()

        return SaidAppBackupSummary(
            createdAt: createdAt,
            includesCollection: manifest["includesCollection"] as? Bool ?? true,
            includesPreferences: FileManager.default.fileExists(atPath: preferencesURL.path),
            includesKeychain: FileManager.default.fileExists(atPath: keychainURL.path),
            includesAppSupport: FileManager.default.fileExists(atPath: appSupportRoot.path)
        )
    }

    private static func readManifest(in folder: URL) throws -> [String: Any] {
        let manifestURL = folder.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw SaidAppBackupError.invalidManifest
        }
        let data = try Data(contentsOf: manifestURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["format"] as? String == formatID,
              let version = object["version"] as? Int,
              version <= formatVersion else {
            throw SaidAppBackupError.invalidManifest
        }
        return object
    }
}
