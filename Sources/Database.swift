import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 用户数据库（history / favorites / dict_cache）
final class Database {
    static let shared = Database()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "QuickDict.Database", qos: .userInitiated)

    let fileURL: URL

    private init() {
        let appSupport = Database.appSupportDir()
        fileURL = appSupport.appendingPathComponent("quickdict.sqlite")
        open()
        migrate()
    }

    static func appSupportDir() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("QuickDict", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func open() {
        let path = fileURL.path
        if sqlite3_open(path, &db) != SQLITE_OK {
            NSLog("无法打开数据库: \(String(cString: sqlite3_errmsg(db)))")
        }
        // 性能与稳定性
        exec("PRAGMA journal_mode=WAL;")
        exec("PRAGMA synchronous=NORMAL;")
        exec("PRAGMA foreign_keys=ON;")
    }

    private func migrate() {
        exec("""
            CREATE TABLE IF NOT EXISTS history (
                word TEXT PRIMARY KEY COLLATE NOCASE,
                lookup_count INTEGER NOT NULL DEFAULT 1,
                first_at REAL NOT NULL,
                last_at REAL NOT NULL,
                last_context TEXT
            );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_history_last_at ON history(last_at DESC);")

        exec("""
            CREATE TABLE IF NOT EXISTS favorites (
                id TEXT PRIMARY KEY,
                word TEXT NOT NULL COLLATE NOCASE,
                sentence TEXT NOT NULL,
                added_at REAL NOT NULL,
                ease REAL NOT NULL DEFAULT 2.5,
                interval_days INTEGER NOT NULL DEFAULT 0,
                due_at REAL NOT NULL,
                review_count INTEGER NOT NULL DEFAULT 0,
                last_review REAL,
                tags TEXT
            );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_favorites_due ON favorites(due_at);")
        exec("CREATE INDEX IF NOT EXISTS idx_favorites_word ON favorites(word);")
        dedupeFavoriteRows()
        exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_favorites_word_sentence_unique ON favorites(word COLLATE NOCASE, sentence);")

        exec("""
            CREATE TABLE IF NOT EXISTS dict_cache (
                word TEXT PRIMARY KEY COLLATE NOCASE,
                source TEXT NOT NULL,
                definition TEXT NOT NULL,
                cached_at REAL NOT NULL
            );
        """)
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            NSLog("SQL exec 失败: \(msg) -- SQL: \(sql)")
            sqlite3_free(err)
            return false
        }
        return true
    }

    private func dedupeFavoriteRows() {
        exec("""
            DELETE FROM favorites
            WHERE id IN (
                SELECT id FROM (
                    SELECT
                        id,
                        ROW_NUMBER() OVER (
                            PARTITION BY lower(word), sentence
                            ORDER BY
                                review_count DESC,
                                interval_days DESC,
                                due_at ASC,
                                COALESCE(last_review, 0) DESC,
                                added_at ASC
                        ) AS row_num
                    FROM favorites
                )
                WHERE row_num > 1
            );
        """)
    }

    // MARK: - History

    /// 记录一次查词。同一单词累加 lookup_count、更新 last_at/last_context。
    func recordLookup(word: String, context: String?) {
        queue.sync {
            let now = Date().timeIntervalSince1970
            let sql = """
                INSERT INTO history(word, lookup_count, first_at, last_at, last_context)
                VALUES(?, 1, ?, ?, ?)
                ON CONFLICT(word) DO UPDATE SET
                    lookup_count = lookup_count + 1,
                    last_at = excluded.last_at,
                    last_context = excluded.last_context;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                NSLog("recordLookup prepare 失败: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, word, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, now)
            sqlite3_bind_double(stmt, 3, now)
            if let context, !context.isEmpty {
                sqlite3_bind_text(stmt, 4, context, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            if sqlite3_step(stmt) != SQLITE_DONE {
                NSLog("recordLookup step 失败: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }

    func getHistory(limit: Int = 500, search: String? = nil) -> [HistoryEntry] {
        queue.sync {
            var sql = "SELECT word, lookup_count, first_at, last_at, last_context FROM history"
            if let s = search, !s.isEmpty {
                sql += " WHERE word LIKE ? ESCAPE '\\'"
            }
            sql += " ORDER BY last_at DESC LIMIT ?"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            var idx: Int32 = 1
            if let s = search, !s.isEmpty {
                let pattern = "%" + s.replacingOccurrences(of: "%", with: "\\%") + "%"
                sqlite3_bind_text(stmt, idx, pattern, -1, SQLITE_TRANSIENT)
                idx += 1
            }
            sqlite3_bind_int(stmt, idx, Int32(limit))

            var out: [HistoryEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let word = String(cString: sqlite3_column_text(stmt, 0))
                let count = Int(sqlite3_column_int(stmt, 1))
                let first = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
                let last = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
                let context: String? = {
                    if let p = sqlite3_column_text(stmt, 4) { return String(cString: p) }
                    return nil
                }()
                out.append(HistoryEntry(word: word, lookupCount: count, firstAt: first, lastAt: last, lastContext: context))
            }
            return out
        }
    }

    func deleteHistory(word: String) {
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "DELETE FROM history WHERE word = ?", -1, &stmt, nil)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, word, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
    }

    func historyCount() -> Int {
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM history", -1, &stmt, nil)
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW {
                return Int(sqlite3_column_int(stmt, 0))
            }
            return 0
        }
    }

    // MARK: - Favorites

    func addFavorite(_ entry: FavoriteEntry) {
        queue.sync {
            let sql = """
                INSERT OR IGNORE INTO favorites
                    (id, word, sentence, added_at, ease, interval_days, due_at, review_count, last_review, tags)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, entry.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, entry.word, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, entry.sentence, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 4, entry.addedAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 5, entry.ease)
            sqlite3_bind_int(stmt, 6, Int32(entry.intervalDays))
            sqlite3_bind_double(stmt, 7, entry.dueAt.timeIntervalSince1970)
            sqlite3_bind_int(stmt, 8, Int32(entry.reviewCount))
            if let lr = entry.lastReview {
                sqlite3_bind_double(stmt, 9, lr.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(stmt, 9)
            }
            if let tags = entry.tags, !tags.isEmpty {
                sqlite3_bind_text(stmt, 10, tags, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 10)
            }
            sqlite3_step(stmt)
        }
    }

    func updateFavoriteSchedule(id: UUID, ease: Double, intervalDays: Int, dueAt: Date, reviewCount: Int, lastReview: Date) {
        queue.sync {
            let sql = """
                UPDATE favorites SET ease=?, interval_days=?, due_at=?, review_count=?, last_review=?
                WHERE id = ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, ease)
            sqlite3_bind_int(stmt, 2, Int32(intervalDays))
            sqlite3_bind_double(stmt, 3, dueAt.timeIntervalSince1970)
            sqlite3_bind_int(stmt, 4, Int32(reviewCount))
            sqlite3_bind_double(stmt, 5, lastReview.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 6, id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
    }

    func deleteFavorite(id: UUID) {
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "DELETE FROM favorites WHERE id = ?", -1, &stmt, nil)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
    }

    func getFavorite(word: String, sentence: String) -> FavoriteEntry? {
        queue.sync {
            let sql = """
                SELECT id, word, sentence, added_at, ease, interval_days, due_at, review_count, last_review, tags
                FROM favorites
                WHERE word = ? AND sentence = ?
                LIMIT 1
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, word, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, sentence, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return readFavoriteRow(stmt: stmt)
        }
    }

    func getAllFavorites(search: String? = nil) -> [FavoriteEntry] {
        queue.sync {
            var sql = "SELECT id, word, sentence, added_at, ease, interval_days, due_at, review_count, last_review, tags FROM favorites"
            if let s = search, !s.isEmpty {
                sql += " WHERE word LIKE ? OR sentence LIKE ?"
            }
            sql += " ORDER BY added_at DESC"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            if let s = search, !s.isEmpty {
                let pattern = "%" + s + "%"
                sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, pattern, -1, SQLITE_TRANSIENT)
            }
            return readFavorites(stmt: stmt)
        }
    }

    /// 到期需要复习的收藏（due_at <= now）
    func getDueFavorites(now: Date = Date(), limit: Int = 200) -> [FavoriteEntry] {
        queue.sync {
            let sql = "SELECT id, word, sentence, added_at, ease, interval_days, due_at, review_count, last_review, tags FROM favorites WHERE due_at <= ? ORDER BY due_at ASC LIMIT ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, now.timeIntervalSince1970)
            sqlite3_bind_int(stmt, 2, Int32(limit))
            return readFavorites(stmt: stmt)
        }
    }

    func favoriteCount() -> Int {
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM favorites", -1, &stmt, nil)
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW {
                return Int(sqlite3_column_int(stmt, 0))
            }
            return 0
        }
    }

    func dueFavoriteCount(now: Date = Date()) -> Int {
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM favorites WHERE due_at <= ?", -1, &stmt, nil)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, now.timeIntervalSince1970)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return Int(sqlite3_column_int(stmt, 0))
            }
            return 0
        }
    }

    private func readFavoriteRow(stmt: OpaquePointer?) -> FavoriteEntry? {
        guard let stmt else { return nil }

        guard
            let idPtr = sqlite3_column_text(stmt, 0),
            let wordPtr = sqlite3_column_text(stmt, 1),
            let sentencePtr = sqlite3_column_text(stmt, 2)
        else { return nil }

        let idStr = String(cString: idPtr)
        guard let id = UUID(uuidString: idStr) else { return nil }

        let word = String(cString: wordPtr)
        let sentence = String(cString: sentencePtr)
        let addedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
        let ease = sqlite3_column_double(stmt, 4)
        let intervalDays = Int(sqlite3_column_int(stmt, 5))
        let dueAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
        let reviewCount = Int(sqlite3_column_int(stmt, 7))
        let lastReview: Date? = {
            if sqlite3_column_type(stmt, 8) == SQLITE_NULL { return nil }
            return Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8))
        }()
        let tags: String? = {
            if let p = sqlite3_column_text(stmt, 9) { return String(cString: p) }
            return nil
        }()

        return FavoriteEntry(
            id: id, word: word, sentence: sentence, addedAt: addedAt,
            ease: ease, intervalDays: intervalDays, dueAt: dueAt,
            reviewCount: reviewCount, lastReview: lastReview, tags: tags
        )
    }

    private func readFavorites(stmt: OpaquePointer?) -> [FavoriteEntry] {
        var out: [FavoriteEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let entry = readFavoriteRow(stmt: stmt) {
                out.append(entry)
            }
        }
        return out
    }

    /// 在收藏的 sentence 里搜索包含此词的句子（用作 cross-ref）
    func searchFavoriteSentences(word: String, excludingID: UUID? = nil, limit: Int = 5) -> [OwnContext] {
        queue.sync {
            // 整词匹配（前后是空白/标点/句首句尾）
            let sql = """
                SELECT id, sentence, added_at FROM favorites
                WHERE (' ' || lower(sentence) || ' ') LIKE ('%' || ? || '%')
                ORDER BY added_at DESC
                LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            let key = " \(word.lowercased()) "
            sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(limit + 1)) // +1 防止 excludingID 占位

            var out: [OwnContext] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let idStr = String(cString: sqlite3_column_text(stmt, 0))
                guard let id = UUID(uuidString: idStr) else { continue }
                if let exclude = excludingID, id == exclude { continue }
                let sentence = String(cString: sqlite3_column_text(stmt, 1))
                let savedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
                out.append(OwnContext(sentence: sentence, savedAt: savedAt, id: id))
                if out.count >= limit { break }
            }
            return out
        }
    }

    // MARK: - Dict cache

    func cacheDefinition(word: String, source: String, definition: String) {
        queue.sync {
            let sql = "INSERT OR REPLACE INTO dict_cache(word, source, definition, cached_at) VALUES (?, ?, ?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, word, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, source, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, definition, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
            sqlite3_step(stmt)
        }
    }

    func cachedDefinition(word: String) -> (source: String, definition: String)? {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT source, definition FROM dict_cache WHERE word = ?", -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, word, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                let source = String(cString: sqlite3_column_text(stmt, 0))
                let def = String(cString: sqlite3_column_text(stmt, 1))
                return (source, def)
            }
            return nil
        }
    }
}

// MARK: - Models

struct HistoryEntry {
    let word: String
    let lookupCount: Int
    let firstAt: Date
    let lastAt: Date
    let lastContext: String?
}

struct FavoriteEntry {
    let id: UUID
    let word: String
    let sentence: String
    let addedAt: Date
    var ease: Double           // 历史兼容字段，保留旧数据
    var intervalDays: Int      // 当前间隔（天）
    var dueAt: Date            // 下次复习时间
    var reviewCount: Int       // 当前复习阶段
    var lastReview: Date?
    var tags: String?

    static func newFavorite(word: String, sentence: String, tags: String? = nil) -> FavoriteEntry {
        let now = Date()
        let firstDueAt = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400)
        return FavoriteEntry(
            id: UUID(),
            word: word,
            sentence: sentence,
            addedAt: now,
            ease: 2.5,
            intervalDays: 1,
            dueAt: firstDueAt, // 首次复习从明天开始
            reviewCount: 0,
            lastReview: nil,
            tags: tags
        )
    }
}
