import Foundation

/// 用户对一个单词的回忆质量评分
enum RecallQuality: Int {
    case forgot = 0     // 完全不记得（重置）
    case hard = 3       // 模糊
    case good = 4       // 记得
    case easy = 5       // 简单
}

/// 固定艾宾浩斯间隔（更密版）
/// 规则：1 / 2 / 3 / 5 / 8 / 14 / 30 天
enum ReviewScheduler {
    private static let intervals = [1, 2, 3, 5, 8, 14, 30]

    /// 根据当前 entry 状态和用户评分，返回更新后的间隔与下次到期时间
    static func schedule(entry: FavoriteEntry, quality: RecallQuality, now: Date = Date()) -> FavoriteEntry {
        let currentStep = max(0, min(entry.reviewCount, Self.intervals.count - 1))
        let nextStep: Int
        switch quality {
        case .forgot:
            nextStep = 0
        case .hard:
            nextStep = currentStep
        case .good:
            nextStep = min(currentStep + 1, Self.intervals.count - 1)
        case .easy:
            nextStep = min(currentStep + 2, Self.intervals.count - 1)
        }
        let newInterval = Self.intervals[nextStep]
        let dueAt = Calendar.current.date(byAdding: .day, value: newInterval, to: now) ?? now.addingTimeInterval(Double(newInterval) * 86400)

        var updated = entry
        updated.intervalDays = newInterval
        updated.dueAt = dueAt
        updated.reviewCount = nextStep
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
