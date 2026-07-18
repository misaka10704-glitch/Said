import Foundation

enum BackupBundleHelper {
    static func temporaryFolder(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    }

    static func removeIfExists(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func copyItem(at source: URL, to destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fm.copyItem(at: source, to: destination)
    }

    static func copyDirectory(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return }
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fm.copyItem(at: source, to: destination)
    }

    static func exportUserDefaults(keys: [String], to url: URL) throws {
        var values: [String: Any] = [:]
        for key in keys {
            guard let value = UserDefaults.standard.object(forKey: key) else { continue }
            values[key] = value
        }
        let data = try PropertyListSerialization.data(
            fromPropertyList: values,
            format: .binary,
            options: 0
        )
        try data.write(to: url)
    }

    static func importUserDefaults(from url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let values = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw SaidAppBackupError.invalidPreferences
        }
        for (key, value) in values {
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    static func exportUserDefaults(prefix: String, to url: URL) throws {
        var values: [String: Any] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix(prefix) {
            values[key] = value
        }
        let data = try PropertyListSerialization.data(
            fromPropertyList: values,
            format: .binary,
            options: 0
        )
        try data.write(to: url)
    }
}
