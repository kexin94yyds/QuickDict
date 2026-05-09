import Foundation

/// 兼容旧 JSON 格式
private struct LegacyWordEntry: Codable {
    let id: UUID
    let word: String
    let sentence: String
    let date: Date
    var reviewCount: Int
    var lastReview: Date?
}

/// 单词本 / 历史的统一门面
final class WordBook {
    static let shared = WordBook()

    private init() {
        migrateLegacyJSONIfNeeded()
    }

    // MARK: - 历史记录（每次查词都调用）

    func recordLookup(word: String, context: String?) {
        Database.shared.recordLookup(word: word, context: context)
    }

    func getHistory(search: String? = nil, limit: Int = 500) -> [HistoryEntry] {
        Database.shared.getHistory(limit: limit, search: search)
    }

    func deleteHistory(word: String) {
        Database.shared.deleteHistory(word: word)
    }

    func historyCount() -> Int {
        Database.shared.historyCount()
    }

    // MARK: - 收藏（句子 / 标记重要词）

    func addFavorite(word: String, sentence: String, tags: String? = nil) -> FavoriteEntry {
        let entry = FavoriteEntry.newFavorite(word: word, sentence: sentence, tags: tags)
        Database.shared.addFavorite(entry)
        return entry
    }

    func getAllFavorites(search: String? = nil) -> [FavoriteEntry] {
        Database.shared.getAllFavorites(search: search)
    }

    func favoriteCount() -> Int {
        Database.shared.favoriteCount()
    }

    func dueFavoriteCount() -> Int {
        Database.shared.dueFavoriteCount()
    }

    func getDueFavorites() -> [FavoriteEntry] {
        Database.shared.getDueFavorites()
    }

    func deleteFavorite(id: UUID) {
        Database.shared.deleteFavorite(id: id)
    }

    // MARK: - 旧 JSON 迁移

    /// 把 ~/Documents/QuickDict_WordBook.json 迁移到 SQLite favorites 表
    /// 迁移后把 JSON 重命名为 .bak.json
    private func migrateLegacyJSONIfNeeded() {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let legacyURL = documents.appendingPathComponent("QuickDict_WordBook.json")

        guard fm.fileExists(atPath: legacyURL.path) else { return }

        do {
            let data = try Data(contentsOf: legacyURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let legacy = try decoder.decode([LegacyWordEntry].self, from: data)

            for old in legacy {
                let entry = FavoriteEntry(
                    id: old.id,
                    word: old.word,
                    sentence: old.sentence,
                    addedAt: old.date,
                    ease: 2.5,
                    intervalDays: 0,
                    dueAt: old.date,
                    reviewCount: old.reviewCount,
                    lastReview: old.lastReview,
                    tags: nil
                )
                Database.shared.addFavorite(entry)
            }

            // 重命名为 .bak
            let backupURL = documents.appendingPathComponent("QuickDict_WordBook.bak.json")
            if fm.fileExists(atPath: backupURL.path) {
                try? fm.removeItem(at: backupURL)
            }
            try fm.moveItem(at: legacyURL, to: backupURL)
            NSLog("已迁移 \(legacy.count) 条旧 JSON 单词到 SQLite")
        } catch {
            NSLog("迁移旧 JSON 失败: \(error)")
        }
    }
}
