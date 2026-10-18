import CoreData
import CryptoKit
import Foundation
import SQLite3
import SwiftData

@Model
final class PersistenceForeignEntity {
    var name: String

    init(name: String) {
        self.name = name
    }
}

private struct RegressionFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
@main
private struct PersistenceRegression {
    private static let profileID = "regression-custom-dns"
    private static let profileName = "WAL-only custom DNS 4c169f98"
    private static let profileTimestamp = Date(timeIntervalSince1970: 1_700_000_001)
    private static let settingsTimestamp = Date(timeIntervalSince1970: 1_700_000_002)

    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("clean installation persists in the dedicated directory", testCleanInstallation),
            ("legacy migration includes WAL data and preserves every field and source byte", testLegacyWALMigration),
            ("later foreign writes to the legacy store cannot change dedicated profiles", testLegacyIsolation),
            ("deleted profiles are not resurrected from the legacy store", testDeletedProfiles),
            ("foreign-only legacy store is left untouched and starts with no DNS profiles", testForeignLegacy),
            ("corrupt legacy store fails visibly without publishing a destination", testCorruptLegacy),
            ("corrupt dedicated store fails without replacing it from legacy", testCorruptDedicated),
        ]

        var failures = 0
        for (name, test) in tests {
            do {
                try test()
                print("PASS: \(name)")
            } catch {
                failures += 1
                fputs("FAIL: \(name): \(error)\n", stderr)
            }
        }
        print("\(tests.count - failures)/\(tests.count) persistence regression tests passed.")
        if failures != 0 {
            exit(EXIT_FAILURE)
        }
    }

    private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() {
            throw RegressionFailure(description: message)
        }
    }

    private static func withRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dns-persistence-regression-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try autoreleasepool { try body(root) }
    }

    private static func makeLegacy(at root: URL) throws -> ModelContainer {
        let schema = Schema([DNSSettings.self, CustomDNSServer.self])
        let configuration = ModelConfiguration(schema: schema, url: root.appendingPathComponent("default.store"))
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func addFixture(to container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(CustomDNSServer(
            id: profileID,
            name: profileName,
            primaryDNS: "192.168.1.101, 192.168.1.102",
            secondaryDNS: "",
            tertiaryDNS: "2001:db8::53",
            quaternaryDNS: "9.9.9.9",
            timestamp: profileTimestamp
        ))
        context.insert(CustomDNSServer(
            id: "regression-optional-fields",
            name: "Optional fields",
            primaryDNS: "1.1.1.1",
            secondaryDNS: "1.0.0.1",
            timestamp: profileTimestamp
        ))
        let settings = DNSSettings(
            id: "regression-settings",
            isCloudflareEnabled: false,
            isQuad9Enabled: true,
            activeCustomDNSID: profileID,
            timestamp: settingsTimestamp,
            isAdGuardEnabled: true
        )
        // Assign explicitly: the existing model initializer does not set this argument.
        settings.activeGetFlixLocation = "Paris"
        context.insert(settings)
        try context.save()
    }

    private static func assertFixture(in container: ModelContainer) throws {
        let context = ModelContext(container)
        let profiles = try context.fetch(FetchDescriptor<CustomDNSServer>())
        try require(profiles.count == 2, "Expected both saved custom profiles, got \(profiles.count)")
        guard let profile = profiles.first(where: { $0.id == profileID }),
              let optional = profiles.first(where: { $0.id == "regression-optional-fields" }) else {
            throw RegressionFailure(description: "Custom profile identifiers changed during migration")
        }
        try require(profile.name == profileName, "Custom DNS name changed")
        try require(profile.primaryDNS == "192.168.1.101, 192.168.1.102", "Primary DNS changed")
        try require(profile.secondaryDNS == "", "An empty secondary DNS was not preserved")
        try require(profile.tertiaryDNS == "2001:db8::53", "Tertiary IPv6 DNS changed")
        try require(profile.quaternaryDNS == "9.9.9.9", "Quaternary DNS changed")
        try require(profile.timestamp == profileTimestamp, "Custom DNS timestamp changed")
        try require(optional.tertiaryDNS == nil && optional.quaternaryDNS == nil, "Nil DNS fields changed")

        let settings = try context.fetch(FetchDescriptor<DNSSettings>())
        try require(settings.count == 1, "Expected one settings row, got \(settings.count)")
        let saved = settings[0]
        try require(saved.id == "regression-settings", "Settings identifier changed")
        try require(saved.activeCustomDNSID == profileID, "Active custom DNS selection was lost")
        try require(!saved.isCloudflareEnabled && saved.isQuad9Enabled, "Provider selection changed")
        try require(saved.isAdGuardEnabled == true, "Optional AdGuard preference changed")
        try require(saved.activeGetFlixLocation == "Paris", "Optional location preference changed")
        try require(saved.timestamp == settingsTimestamp, "Settings timestamp changed")
    }

    private static func sourceFingerprint(at root: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        for filename in ["default.store", "default.store-wal"] {
            let url = root.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) {
                let digest = SHA256.hash(data: try Data(contentsOf: url))
                result[filename] = digest.map { String(format: "%02x", $0) }.joined()
            }
        }
        return result
    }

    private static func sqlite(_ url: URL, flags: Int32 = SQLITE_OPEN_READWRITE,
                               _ body: (OpaquePointer) throws -> Void) throws {
        var database: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &database, flags, nil)
        guard status == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "No SQLite connection"
            if let database { sqlite3_close(database) }
            throw RegressionFailure(description: "Could not open test database: \(message)")
        }
        defer { sqlite3_close(database) }
        try body(database)
    }

    private static func execute(_ sql: String, database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw RegressionFailure(description: "SQLite fixture operation failed: \(String(cString: sqlite3_errmsg(database)))")
        }
    }

    private static func makeForeignLegacy(at root: URL) throws -> ModelContainer {
        let schema = Schema([PersistenceForeignEntity.self])
        let configuration = ModelConfiguration(schema: schema, url: root.appendingPathComponent("default.store"))
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(PersistenceForeignEntity(name: "Unrelated application data"))
        try context.save()
        return container
    }

    private static func expectFailure(_ message: String, _ operation: () throws -> Void) throws {
        do {
            try operation()
        } catch {
            return
        }
        throw RegressionFailure(description: message)
    }

    private static func testCleanInstallation() throws {
        try withRoot { root in
            let expected = root.appendingPathComponent("com.linfordsoftware.dnseasyswitcher/default.store")
            try require(DNSPersistence.storeURL(applicationSupportDirectory: root) == expected,
                        "Persistent store does not use the application-specific directory")
            let container = try DNSPersistence.makeContainer(applicationSupportDirectory: root)
            try addFixture(to: container)
            try require(FileManager.default.fileExists(atPath: expected.path), "Dedicated database was not created")
            try require(!FileManager.default.fileExists(atPath: root.appendingPathComponent("default.store").path),
                        "A clean installation created the shared legacy database")
            let reopened = try DNSPersistence.makeContainer(applicationSupportDirectory: root)
            try assertFixture(in: reopened)
        }
    }

    private static func testLegacyWALMigration() throws {
        try withRoot { root in
            let legacy = try makeLegacy(at: root)
            let source = root.appendingPathComponent("default.store")
            try sqlite(source) { database in
                try execute("PRAGMA wal_checkpoint(TRUNCATE);", database: database)
            }
            try addFixture(to: legacy)
            let wal = try Data(contentsOf: root.appendingPathComponent("default.store-wal"))
            let main = try Data(contentsOf: source)
            let marker = Data(profileName.utf8)
            try require(wal.range(of: marker) != nil, "Fixture profile must actually be committed in the WAL")
            try require(main.range(of: marker) == nil, "Fixture profile was already checkpointed; WAL regression would be ineffective")
            let before = try sourceFingerprint(at: root)
            let migrated = try DNSPersistence.makeContainer(applicationSupportDirectory: root)
            try assertFixture(in: migrated)
            try require(try sourceFingerprint(at: root) == before, "Migration modified the legacy main database or WAL")
            withExtendedLifetime(legacy) {}
        }
    }

    private static func testLegacyIsolation() throws {
        try withRoot { root in
            try autoreleasepool {
                let legacy = try makeLegacy(at: root)
                try addFixture(to: legacy)
                let migrated = try DNSPersistence.makeContainer(applicationSupportDirectory: root)
                try assertFixture(in: migrated)
            }
            for suffix in ["", "-wal", "-shm"] {
                let url = root.appendingPathComponent("default.store\(suffix)")
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            }
            let foreign = try makeForeignLegacy(at: root)
            let before = try sourceFingerprint(at: root)
            let reopened = try DNSPersistence.makeContainer(applicationSupportDirectory: root)
            try assertFixture(in: reopened)
            try require(try sourceFingerprint(at: root) == before, "A later launch touched the unrelated legacy database")
            withExtendedLifetime(foreign) {}
        }
    }

    private static func testDeletedProfiles() throws {
        try withRoot { root in
            let legacy = try makeLegacy(at: root)
            try addFixture(to: legacy)
            let migrated = try DNSPersistence.makeContainer(applicationSupportDirectory: root)
            let context = ModelContext(migrated)
            context.autosaveEnabled = false
            for profile in try context.fetch(FetchDescriptor<CustomDNSServer>()) {
                context.delete(profile)
            }
            try context.save()
            let reopened = try DNSPersistence.makeContainer(applicationSupportDirectory: root)
            try require(try ModelContext(reopened).fetchCount(FetchDescriptor<CustomDNSServer>()) == 0,
                        "A deliberately deleted profile was restored from the old shared database")
            withExtendedLifetime(legacy) {}
        }
    }

    private static func testForeignLegacy() throws {
        try withRoot { root in
            let foreign = try makeForeignLegacy(at: root)
            let before = try sourceFingerprint(at: root)
            let container = try DNSPersistence.makeContainer(applicationSupportDirectory: root)
            let context = ModelContext(container)
            try require(try context.fetchCount(FetchDescriptor<CustomDNSServer>()) == 0, "Imported data from an unrelated application")
            try require(try context.fetchCount(FetchDescriptor<DNSSettings>()) == 0, "Invented DNS settings from an unrelated database")
            try require(try sourceFingerprint(at: root) == before, "Foreign legacy store was modified")
            withExtendedLifetime(foreign) {}
        }
    }

    private static func testCorruptLegacy() throws {
        try withRoot { root in
            try Data("corrupt legacy database\n".utf8).write(to: root.appendingPathComponent("default.store"))
            let before = try sourceFingerprint(at: root)
            try expectFailure("Corrupt legacy database silently opened or fell back to memory") {
                _ = try DNSPersistence.makeContainer(applicationSupportDirectory: root)
            }
            let targetDirectory = DNSPersistence.storeURL(applicationSupportDirectory: root).deletingLastPathComponent()
            try require(!FileManager.default.fileExists(atPath: targetDirectory.path), "Failed migration published a partial destination")
            try require(try sourceFingerprint(at: root) == before, "Failed migration modified the corrupt source")
        }
    }

    private static func testCorruptDedicated() throws {
        try withRoot { root in
            let legacy = try makeLegacy(at: root)
            try addFixture(to: legacy)
            let destination = DNSPersistence.storeURL(applicationSupportDirectory: root)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let corruptData = Data("corrupt dedicated database\n".utf8)
            try corruptData.write(to: destination)
            let before = try sourceFingerprint(at: root)
            try expectFailure("Corrupt dedicated database was replaced or fell back to memory") {
                _ = try DNSPersistence.makeContainer(applicationSupportDirectory: root)
            }
            try require(try Data(contentsOf: destination) == corruptData, "Corrupt dedicated database was replaced")
            try require(try sourceFingerprint(at: root) == before, "Opening corrupt dedicated database touched the legacy source")
            withExtendedLifetime(legacy) {}
        }
    }
}
