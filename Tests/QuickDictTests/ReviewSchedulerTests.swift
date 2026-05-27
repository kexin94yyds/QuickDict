import XCTest
@testable import QuickDict

final class ReviewSchedulerTests: XCTestCase {
    func testForgotSchedulesTenMinuteRelearn() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entry = makeEntry(ease: 2.5, intervalDays: 1, reviewCount: 0, dueAt: now)
        let oldDelay = ReviewSettings.relearnDelayMinutes
        ReviewSettings.relearnDelayMinutes = 10
        defer { ReviewSettings.relearnDelayMinutes = oldDelay }

        let updated = ReviewScheduler.schedule(entry: entry, quality: .forgot, now: now)

        XCTAssertEqual(updated.intervalDays, 0)
        XCTAssertEqual(updated.reviewCount, 0)
        XCTAssertEqual(updated.dueAt.timeIntervalSince(now), 10 * 60, accuracy: 0.5)
        XCTAssertEqual(updated.ease, 2.25, accuracy: 0.001)
        XCTAssertEqual(updated.lastReview, now)
    }

    func testEasyOnNewCardDoesNotJumpToLongInterval() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entry = makeEntry(ease: 2.5, intervalDays: 1, reviewCount: 0, dueAt: now)

        let updated = ReviewScheduler.schedule(entry: entry, quality: .easy, now: now)

        XCTAssertEqual(updated.reviewCount, 2)
        XCTAssertEqual(updated.intervalDays, 4)
        XCTAssertEqual(updated.ease, 2.65, accuracy: 0.001)
    }

    func testPrepareReviewQueueDefersOverflowBeyondDailyLimit() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = (0..<22).map { offset in
            makeEntry(word: "word\(offset)", dueAt: now.addingTimeInterval(Double(offset)))
        }

        let prepared = ReviewScheduler.prepareReviewQueue(entries, now: now, dailyLimit: 20)

        XCTAssertEqual(prepared.reviewNow.count, 20)
        XCTAssertEqual(prepared.deferred.count, 2)
        XCTAssertTrue(prepared.deferred.allSatisfy { $0.dueAt > now })
    }

    private func makeEntry(
        word: String = "test",
        ease: Double = 2.5,
        intervalDays: Int = 1,
        reviewCount: Int = 0,
        dueAt: Date
    ) -> FavoriteEntry {
        FavoriteEntry(
            id: UUID(),
            word: word,
            sentence: word,
            addedAt: dueAt.addingTimeInterval(-86400),
            ease: ease,
            intervalDays: intervalDays,
            dueAt: dueAt,
            reviewCount: reviewCount,
            lastReview: nil,
            tags: nil,
            contextSentence: nil,
            definitionSnapshot: nil,
            note: nil
        )
    }
}
