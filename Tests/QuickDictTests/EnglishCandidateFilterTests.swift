import XCTest
@testable import QuickDict

final class EnglishCandidateFilterTests: XCTestCase {
    func testShortCandidatesOnlyAllowKnownAbbreviations() {
        let filtered = EnglishCandidateFilter.usefulUnique(["zh", "su", "AI", "db", "noun"])

        XCTAssertFalse(filtered.contains("zh"))
        XCTAssertFalse(filtered.contains("su"))
        XCTAssertFalse(filtered.contains("noun"))
        XCTAssertTrue(filtered.contains("ai"))
        XCTAssertTrue(filtered.contains("db"))
    }

    func testDictionaryBackedDropsLookupMisses() {
        let filtered = EnglishCandidateFilter.dictionaryBacked(
            ["execute", "zh", "phantomword"],
            lookup: { word in
                word == "execute"
                    ? LookupResult(word: word, definition: "to carry out", source: .ecdict)
                    : nil
            }
        )

        XCTAssertEqual(filtered, ["execute"])
    }
}
