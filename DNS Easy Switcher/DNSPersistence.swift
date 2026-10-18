import CoreData
import Foundation
import SQLite3
import SwiftData

enum DNSPersistence {
    private static let directoryName = "com.linfordsoftware.dnseasyswitcher"

    static func storeURL(applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("default.store")
    }

    static func makeContainer(applicationSupportDirectory: URL? = nil) throws -> ModelContainer {
        let fileManager = FileManager.default
        let supportDirectory = try applicationSupportDirectory ?? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let destination = storeURL(applicationSupportDirectory: supportDirectory)
        let directory = destination.deletingLastPathComponent()

        // Once a dedicated store exists, never import the shared store again.
        // This also prevents deleted profiles from being resurrected on launch.
        if !fileManager.fileExists(atPath: directory.path) {
            try prepareStore(in: supportDirectory, destinationDirectory: directory)
        }

        let schema = Schema([DNSSettings.self, CustomDNSServer.self])
        let configuration = ModelConfiguration(
            schema: schema,
            url: destination,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func prepareStore(in supportDirectory: URL, destinationDirectory: URL) throws {
        let fileManager = FileManager.default
        let stagingDirectory = supportDirectory.appendingPathComponent(
            ".\(directoryName)-migration-\(UUID().uuidString)", isDirectory: true
        )
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingDirectory) }

        let legacyURL = supportDirectory.appendingPathComponent("default.store")
        if fileManager.fileExists(atPath: legacyURL.path) {
            let snapshotURL = stagingDirectory.appendingPathComponent("default.store")
            try snapshotStore(from: legacyURL, to: snapshotURL)

            // Inspect only our snapshot. Opening the live legacy store with a
            // SwiftData schema could migrate another application's database.
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType,
                at: snapshotURL,
                options: [NSReadOnlyPersistentStoreOption: true]
            )
            let entities = metadata[NSStoreModelVersionHashesKey] as? [String: Any] ?? [:]
            if entities["CustomDNSServer"] == nil && entities["DNSSettings"] == nil {
                // A fresh installation can encounter another app's default.store.
                // Its data is unrelated and must not become our persistent store.
                try fileManager.removeItem(at: stagingDirectory)
                try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
            }
        }

        do {
            // Publish the whole snapshot, including any SQLite sidecars, with a
            // same-volume directory rename. Failed imports never publish a store.
            try fileManager.moveItem(at: stagingDirectory, to: destinationDirectory)
        } catch {
            // Another instance may have finished its first launch concurrently.
            guard fileManager.fileExists(atPath: destinationDirectory.path) else { throw error }
        }
    }

    private static func snapshotStore(from sourceURL: URL, to destinationURL: URL) throws {
        var source: OpaquePointer?
        var destination: OpaquePointer?
        defer {
            if let destination { sqlite3_close(destination) }
            if let source { sqlite3_close(source) }
        }

        guard sqlite3_open_v2(sourceURL.path, &source, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw sqliteError(source, url: sourceURL)
        }
        sqlite3_busy_timeout(source, 5_000)

        guard sqlite3_open_v2(
            destinationURL.path, &destination, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil
        ) == SQLITE_OK else {
            throw sqliteError(destination, url: destinationURL)
        }
        sqlite3_busy_timeout(destination, 5_000)
        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw sqliteError(destination, url: destinationURL)
        }

        // SQLite's backup API includes committed WAL data in a consistent snapshot.
        let result = sqlite3_backup_step(backup, -1)
        let finishResult = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw sqliteError(
                destination, url: sourceURL, code: result == SQLITE_DONE ? finishResult : result
            )
        }
    }

    private static func sqliteError(_ database: OpaquePointer?, url: URL, code: Int32? = nil) -> NSError {
        let errorCode = code ?? sqlite3_errcode(database)
        let reason: String
        if let database, sqlite3_errcode(database) == errorCode {
            reason = String(cString: sqlite3_errmsg(database))
        } else {
            reason = String(cString: sqlite3_errstr(errorCode))
        }
        return NSError(
            domain: "DNSPersistence",
            code: Int(errorCode),
            userInfo: [NSLocalizedDescriptionKey: "Could not import saved DNS profiles from \(url.path): \(reason)"]
        )
    }
}
