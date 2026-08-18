import XCTest
import SQLite3
@testable import QuickDict

final class QuickDictBackupCodecTests: XCTestCase {
    private func execute(_ database: OpaquePointer?, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown SQLite error"
            sqlite3_free(errorMessage)
            throw NSError(domain: "QuickDictBackupCodecTests", code: Int(result), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    func testPortableBackupRoundTripPreservesReviewAndContextFields() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let favorite = FavoriteEntry(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            word: "context",
            sentence: "A useful context.",
            addedAt: now,
            ease: 2.7,
            intervalDays: 8,
            dueAt: now.addingTimeInterval(86_400),
            reviewCount: 4,
            lastReview: now,
            tags: "learning",
            contextSentence: "A useful context.",
            definitionSnapshot: "the circumstances around an event",
            note: "remember this"
        )
        let history = HistoryEntry(
            word: "context",
            lookupCount: 3,
            firstAt: now,
            lastAt: now.addingTimeInterval(60),
            lastContext: "A useful context."
        )
        let backup = QuickDictBackup(
            schemaVersion: 1,
            exportedAt: now,
            favorites: [favorite],
            history: [history],
            settings: .init(dailyReviewLimit: 20, relearnDelayMinutes: 10)
        )

        let encoded = try QuickDictBackupCodec.encode(backup)
        let decoded = try QuickDictBackupCodec.decode(encoded)

        XCTAssertEqual(decoded, backup)
    }

    func testUnsupportedSchemaIsRejected() throws {
        let backup = QuickDictBackup(
            schemaVersion: 99,
            exportedAt: Date(timeIntervalSince1970: 0),
            favorites: [],
            history: [],
            settings: .init(dailyReviewLimit: 20, relearnDelayMinutes: 10)
        )
        let data = try QuickDictBackupCodec.encode(backup)
        XCTAssertThrowsError(try QuickDictBackupCodec.decode(data))
    }

    func testDatabaseFolderImportIncludesRowsStillInWALAndRejectsBareDatabaseFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quickdict-wal-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("quickdict.sqlite")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        guard let database else {
            XCTFail("Failed to open WAL fixture")
            return
        }
        defer { sqlite3_close(database) }

        try execute(database, "PRAGMA journal_mode=WAL;")
        try execute(database, "PRAGMA wal_autocheckpoint=0;")
        try execute(database, """
            CREATE TABLE favorites (
                id TEXT PRIMARY KEY,
                word TEXT NOT NULL COLLATE NOCASE,
                sentence TEXT NOT NULL,
                added_at REAL NOT NULL,
                ease REAL NOT NULL,
                interval_days INTEGER NOT NULL,
                due_at REAL NOT NULL,
                review_count INTEGER NOT NULL,
                last_review REAL,
                tags TEXT,
                context_sentence TEXT,
                definition_snapshot TEXT,
                note TEXT
            );
            CREATE TABLE history (
                word TEXT PRIMARY KEY COLLATE NOCASE,
                lookup_count INTEGER NOT NULL,
                first_at REAL NOT NULL,
                last_at REAL NOT NULL,
                last_context TEXT
            );
            PRAGMA wal_checkpoint(TRUNCATE);
            """)
        try execute(database, """
            INSERT INTO favorites VALUES (
                '11111111-2222-3333-4444-555555555555', 'wal-word', 'A WAL sentence.',
                1700000000, 2.5, 3, 1700086400, 2, 1700000000,
                'fixture', 'A WAL sentence.', 'definition', 'note'
            );
            INSERT INTO history VALUES (
                'wal-word', 4, 1700000000, 1700000060, 'A WAL sentence.'
            );
            """)

        let walURL = URL(fileURLWithPath: databaseURL.path + "-wal")
        XCTAssertTrue(FileManager.default.fileExists(atPath: walURL.path))
        XCTAssertGreaterThan((try FileManager.default.attributesOfItem(atPath: walURL.path)[.size] as? NSNumber)?.intValue ?? 0, 0)

        let imported = try QuickDictDataTransfer.previewImport(from: root)
        XCTAssertEqual(imported.favorites.map(\.word), ["wal-word"])
        XCTAssertEqual(imported.history.map(\.word), ["wal-word"])
        XCTAssertEqual(imported.history.first?.lookupCount, 4)

        XCTAssertThrowsError(try QuickDictDataTransfer.previewImport(from: databaseURL)) { error in
            guard case QuickDictDataTransferError.databaseFolderRequired = error else {
                return XCTFail("Expected databaseFolderRequired, got \(error)")
            }
        }
    }
}
