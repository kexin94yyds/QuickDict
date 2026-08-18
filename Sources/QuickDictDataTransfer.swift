import Foundation
import SQLite3

struct QuickDictBackup: Codable, Equatable {
    struct Settings: Codable, Equatable {
        let dailyReviewLimit: Int
        let relearnDelayMinutes: Int
    }

    let schemaVersion: Int
    let exportedAt: Date
    let favorites: [FavoriteEntry]
    let history: [HistoryEntry]
    let settings: Settings

    static func current(exportedAt: Date = Date()) -> QuickDictBackup {
        QuickDictBackup(
            schemaVersion: 1,
            exportedAt: exportedAt,
            favorites: WordBook.shared.getAllFavorites(),
            history: WordBook.shared.getHistory(limit: Int(Int32.max)),
            settings: Settings(
                dailyReviewLimit: ReviewSettings.dailyReviewLimit,
                relearnDelayMinutes: ReviewSettings.relearnDelayMinutes
            )
        )
    }
}

struct QuickDictImportSummary: Equatable {
    let sourceFavorites: Int
    let sourceHistory: Int
    let insertedFavorites: Int
    let insertedHistory: Int
}

enum QuickDictBackupCodec {
    static func encode(_ backup: QuickDictBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data) throws -> QuickDictBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(QuickDictBackup.self, from: data)
        guard backup.schemaVersion == 1 else {
            throw QuickDictDataTransferError.unsupportedSchema(backup.schemaVersion)
        }
        return backup
    }
}

enum QuickDictDataTransferError: LocalizedError {
    case unsupportedSchema(Int)
    case unsupportedFile
    case databaseFolderRequired
    case missingDatabaseInFolder
    case invalidDatabase(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "不支持的数据备份版本：\(version)"
        case .unsupportedFile:
            return "请选择快捷查词 JSON 备份，或包含 quickdict.sqlite 的 QuickDict 数据文件夹。"
        case .databaseFolderRequired:
            return "不能单独导入 quickdict.sqlite。请改选包含它及 WAL/SHM 文件的 QuickDict 数据文件夹，避免遗漏近期数据。"
        case .missingDatabaseInFolder:
            return "所选文件夹中没有 quickdict.sqlite。请选择旧版 Application Support 中的 QuickDict 数据文件夹。"
        case .invalidDatabase(let message):
            return "无法读取快捷查词数据库：\(message)"
        }
    }
}

enum QuickDictDataTransfer {
    static func exportBackup(to url: URL) throws {
        let data = try QuickDictBackupCodec.encode(.current())
        try data.write(to: url, options: .atomic)
    }

    static func previewImport(from url: URL) throws -> QuickDictBackup {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let databaseURL = url.appendingPathComponent("quickdict.sqlite", isDirectory: false)
            guard FileManager.default.fileExists(atPath: databaseURL.path) else {
                throw QuickDictDataTransferError.missingDatabaseInFolder
            }
            return try QuickDictSQLiteBackupReader.read(from: databaseURL)
        }

        if url.pathExtension.lowercased() == "json" {
            let data = try Data(contentsOf: url)
            return try QuickDictBackupCodec.decode(data)
        }
        if url.pathExtension.lowercased() == "sqlite" {
            throw QuickDictDataTransferError.databaseFolderRequired
        }
        throw QuickDictDataTransferError.unsupportedFile
    }

    static func merge(_ backup: QuickDictBackup) -> QuickDictImportSummary {
        let favoritesBefore = WordBook.shared.favoriteCount()
        let historyBefore = WordBook.shared.historyCount()

        for favorite in backup.favorites {
            Database.shared.addFavorite(favorite)
        }
        for entry in backup.history {
            Database.shared.mergeImportedHistory(entry)
        }

        ReviewSettings.dailyReviewLimit = backup.settings.dailyReviewLimit
        ReviewSettings.relearnDelayMinutes = backup.settings.relearnDelayMinutes

        let favoritesAfter = WordBook.shared.favoriteCount()
        let historyAfter = WordBook.shared.historyCount()
        return QuickDictImportSummary(
            sourceFavorites: backup.favorites.count,
            sourceHistory: backup.history.count,
            insertedFavorites: max(0, favoritesAfter - favoritesBefore),
            insertedHistory: max(0, historyAfter - historyBefore)
        )
    }
}

private enum QuickDictSQLiteBackupReader {
    static func read(from url: URL) throws -> QuickDictBackup {
        var database: OpaquePointer?
        let openFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(url.path, &database, openFlags, nil)
        guard openResult == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "打开失败"
            if let database { sqlite3_close(database) }
            throw QuickDictDataTransferError.invalidDatabase(message)
        }
        defer { sqlite3_close(database) }

        guard sqlite3_exec(database, "BEGIN", nil, nil, nil) == SQLITE_OK else {
            throw QuickDictDataTransferError.invalidDatabase(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_exec(database, "ROLLBACK", nil, nil, nil) }

        let favorites = try readFavorites(database)
        let history = try readHistory(database)
        return QuickDictBackup(
            schemaVersion: 1,
            exportedAt: Date(),
            favorites: favorites,
            history: history,
            settings: .init(
                dailyReviewLimit: ReviewSettings.dailyReviewLimit,
                relearnDelayMinutes: ReviewSettings.relearnDelayMinutes
            )
        )
    }

    private static func readFavorites(_ database: OpaquePointer) throws -> [FavoriteEntry] {
        let sql = """
            SELECT id, word, sentence, added_at, ease, interval_days, due_at, review_count,
                   last_review, tags, context_sentence, definition_snapshot, note
            FROM favorites ORDER BY added_at ASC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw QuickDictDataTransferError.invalidDatabase(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        var entries: [FavoriteEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = text(statement, 0),
                  let id = UUID(uuidString: idText),
                  let word = text(statement, 1),
                  let sentence = text(statement, 2) else {
                continue
            }
            entries.append(FavoriteEntry(
                id: id,
                word: word,
                sentence: sentence,
                addedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                ease: sqlite3_column_double(statement, 4),
                intervalDays: Int(sqlite3_column_int(statement, 5)),
                dueAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                reviewCount: Int(sqlite3_column_int(statement, 7)),
                lastReview: date(statement, 8),
                tags: text(statement, 9),
                contextSentence: text(statement, 10),
                definitionSnapshot: text(statement, 11),
                note: text(statement, 12)
            ))
        }
        return entries
    }

    private static func readHistory(_ database: OpaquePointer) throws -> [HistoryEntry] {
        let sql = "SELECT word, lookup_count, first_at, last_at, last_context FROM history ORDER BY last_at DESC"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw QuickDictDataTransferError.invalidDatabase(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        var entries: [HistoryEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let word = text(statement, 0) else { continue }
            entries.append(HistoryEntry(
                word: word,
                lookupCount: Int(sqlite3_column_int(statement, 1)),
                firstAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                lastAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                lastContext: text(statement, 4)
            ))
        }
        return entries
    }

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: pointer)
    }

    private static func date(_ statement: OpaquePointer?, _ column: Int32) -> Date? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, column))
    }
}
