import Foundation

/// 用户对一个单词的回忆质量评分
enum RecallQuality: Int {
    case forgot = 0     // 完全不记得（重置）
    case hard = 3       // 模糊
    case good = 4       // 记得
    case easy = 5       // 简单
}

struct ReviewQueuePreparation {
    let reviewNow: [FavoriteEntry]
    let deferred: [(entry: FavoriteEntry, dueAt: Date)]
}

/// 轻量复习调度。
/// 基础间隔：1 / 2 / 3 / 5 / 8 / 14 / 30 天；forgot 进入 10 分钟再学。
enum ReviewScheduler {
    private static let intervals = [1, 2, 3, 5, 8, 14, 30]
    static let dailyReviewLimit = 20
    static let relearnDelay: TimeInterval = 10 * 60

    /// 根据当前 entry 状态和用户评分，返回更新后的间隔与下次到期时间
    static func schedule(entry: FavoriteEntry, quality: RecallQuality, now: Date = Date()) -> FavoriteEntry {
        let currentStep = max(0, min(entry.reviewCount, Self.intervals.count - 1))
        let currentEase = clamp(entry.ease, min: 1.3, max: 3.2)
        let nextStep: Int
        let newEase: Double
        let newInterval: Int
        let dueAt: Date

        switch quality {
        case .forgot:
            nextStep = 0
            newEase = clamp(currentEase - 0.25, min: 1.3, max: 3.2)
            newInterval = 0
            dueAt = now.addingTimeInterval(Self.relearnDelay)
        case .hard:
            nextStep = currentStep
            newEase = clamp(currentEase - 0.15, min: 1.3, max: 3.2)
            newInterval = max(1, min(entry.intervalDays, Self.intervals[currentStep]))
            dueAt = dayDueDate(days: newInterval, from: now)
        case .good:
            nextStep = min(currentStep + 1, Self.intervals.count - 1)
            newEase = clamp(currentEase + 0.05, min: 1.3, max: 3.2)
            newInterval = adjustedInterval(base: Self.intervals[nextStep], ease: newEase, multiplier: 1.0)
            dueAt = dayDueDate(days: newInterval, from: now)
        case .easy:
            nextStep = min(currentStep + 2, Self.intervals.count - 1)
            newEase = clamp(currentEase + 0.15, min: 1.3, max: 3.2)
            newInterval = adjustedInterval(base: Self.intervals[nextStep], ease: newEase, multiplier: 1.15)
            dueAt = dayDueDate(days: newInterval, from: now)
        }

        var updated = entry
        updated.ease = newEase
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

    static func prepareReviewQueue(
        _ dueEntries: [FavoriteEntry],
        now: Date = Date(),
        dailyLimit: Int = Self.dailyReviewLimit
    ) -> ReviewQueuePreparation {
        let sorted = dueEntries.sorted {
            if $0.dueAt == $1.dueAt { return $0.addedAt < $1.addedAt }
            return $0.dueAt < $1.dueAt
        }
        let limit = max(1, dailyLimit)
        let reviewNow = Array(sorted.prefix(limit))
        let overflow = sorted.dropFirst(limit).enumerated().map { offset, entry in
            (entry: entry, dueAt: deferredDueDate(now: now, overflowOffset: offset, dailyLimit: limit))
        }
        return ReviewQueuePreparation(reviewNow: reviewNow, deferred: overflow)
    }

    private static func adjustedInterval(base: Int, ease: Double, multiplier: Double) -> Int {
        let easeScale = ease / 2.5
        return max(1, Int((Double(base) * easeScale * multiplier).rounded()))
    }

    private static func dayDueDate(days: Int, from now: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: now) ?? now.addingTimeInterval(Double(days) * 86400)
    }

    private static func deferredDueDate(now: Date, overflowOffset: Int, dailyLimit: Int) -> Date {
        let dayOffset = 1 + overflowOffset / max(1, dailyLimit)
        let calendar = Calendar.current
        let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(Double(dayOffset) * 86400)
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: targetDay) ?? targetDay
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value.isFinite ? value : 2.5))
    }
}
