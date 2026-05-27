import Foundation

enum ReviewSettings {
    private static let dailyReviewLimitKey = "QuickDict.Review.dailyReviewLimit"
    private static let relearnDelayMinutesKey = "QuickDict.Review.relearnDelayMinutes"

    static var dailyReviewLimit: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: dailyReviewLimitKey)
            return clamp(stored == 0 ? 20 : stored, min: 1, max: 100)
        }
        set {
            UserDefaults.standard.set(clamp(newValue, min: 1, max: 100), forKey: dailyReviewLimitKey)
        }
    }

    static var relearnDelayMinutes: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: relearnDelayMinutesKey)
            return clamp(stored == 0 ? 10 : stored, min: 1, max: 240)
        }
        set {
            UserDefaults.standard.set(clamp(newValue, min: 1, max: 240), forKey: relearnDelayMinutesKey)
        }
    }

    static var relearnDelay: TimeInterval {
        TimeInterval(relearnDelayMinutes * 60)
    }

    private static func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(max, value))
    }
}
