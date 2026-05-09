import Foundation

/// 用户对一个单词的回忆质量评分
enum RecallQuality: Int {
    case forgot = 0     // 完全不记得（重置）
    case hard = 3       // 模糊
    case good = 4       // 记得
    case easy = 5       // 简单
}

/// SM-2 间隔重复算法（Anki 的祖先）
/// 参考: https://en.wikipedia.org/wiki/SuperMemo#Description_of_SM-2_algorithm
enum ReviewScheduler {

    /// 根据当前 entry 状态和用户评分，返回更新后的 (ease, intervalDays, dueAt, lastReview, reviewCount)
    static func schedule(entry: FavoriteEntry, quality: RecallQuality, now: Date = Date()) -> FavoriteEntry {
        let q = Double(quality.rawValue)

        // 1. 计算新的 ease（不低于 1.3）
        var newEase = entry.ease + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
        if newEase < 1.3 { newEase = 1.3 }

        // 2. 计算新间隔
        var newInterval: Int
        var newReviewCount = entry.reviewCount
        if quality == .forgot {
            // 失败：重置到 1 天后再来
            newInterval = 1
            newReviewCount = 0
        } else {
            switch entry.reviewCount {
            case 0:
                newInterval = 1
            case 1:
                newInterval = 6
            default:
                newInterval = max(1, Int((Double(entry.intervalDays) * newEase).rounded()))
            }
            newReviewCount += 1
        }

        // 3. 下次到期时间
        let dueAt = Calendar.current.date(byAdding: .day, value: newInterval, to: now) ?? now.addingTimeInterval(Double(newInterval) * 86400)

        var updated = entry
        updated.ease = newEase
        updated.intervalDays = newInterval
        updated.dueAt = dueAt
        updated.reviewCount = newReviewCount
        updated.lastReview = now
        return updated
    }

    /// 把更新结果写回数据库
    static func apply(_ updated: FavoriteEntry) {
        Database.shared.updateFavoriteSchedule(
            id: updated.id,
            ease: updated.ease,
            intervalDays: updated.intervalDays,
            dueAt: updated.dueAt,
            reviewCount: updated.reviewCount,
            lastReview: updated.lastReview ?? Date()
        )
    }
}
