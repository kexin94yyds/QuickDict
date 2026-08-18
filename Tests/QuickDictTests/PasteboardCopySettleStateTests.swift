import XCTest
@testable import QuickDict

final class PasteboardCopySettleStateTests: XCTestCase {
    func testWaitsForTwoStableObservationsBeforeRestoring() {
        var state = PasteboardCopySettleState()

        XCTAssertEqual(
            state.observe(
                originalChangeCount: 10,
                currentChangeCount: 11,
                currentText: "serendipity",
                requiredStableObservations: 2
            ),
            .waiting
        )
        XCTAssertEqual(
            state.observe(
                originalChangeCount: 10,
                currentChangeCount: 11,
                currentText: "serendipity",
                requiredStableObservations: 2
            ),
            .waiting
        )
        XCTAssertEqual(
            state.observe(
                originalChangeCount: 10,
                currentChangeCount: 11,
                currentText: "serendipity",
                requiredStableObservations: 2
            ),
            .ready(text: "serendipity", expectedChangeCount: 11)
        )
    }

    func testAdditionalSourceWriteRestartsStabilityWindow() {
        var state = PasteboardCopySettleState()

        _ = state.observe(
            originalChangeCount: 20,
            currentChangeCount: 21,
            currentText: "serendipity",
            requiredStableObservations: 2
        )
        _ = state.observe(
            originalChangeCount: 20,
            currentChangeCount: 21,
            currentText: "serendipity",
            requiredStableObservations: 2
        )

        XCTAssertEqual(
            state.observe(
                originalChangeCount: 20,
                currentChangeCount: 22,
                currentText: "serendipity",
                requiredStableObservations: 2
            ),
            .waiting
        )
        XCTAssertEqual(
            state.observe(
                originalChangeCount: 20,
                currentChangeCount: 22,
                currentText: "serendipity",
                requiredStableObservations: 2
            ),
            .waiting
        )
        XCTAssertEqual(
            state.observe(
                originalChangeCount: 20,
                currentChangeCount: 22,
                currentText: "serendipity",
                requiredStableObservations: 2
            ),
            .ready(text: "serendipity", expectedChangeCount: 22)
        )
    }

    func testDifferentClipboardTextPreservesUserCopy() {
        var state = PasteboardCopySettleState()

        _ = state.observe(
            originalChangeCount: 30,
            currentChangeCount: 31,
            currentText: "serendipity",
            requiredStableObservations: 2
        )

        XCTAssertEqual(
            state.observe(
                originalChangeCount: 30,
                currentChangeCount: 32,
                currentText: "user copied something else",
                requiredStableObservations: 2
            ),
            .preserveCurrentClipboard(text: "serendipity")
        )
    }

    func testTimeoutWithoutCopiedTextIsUnavailable() {
        var state = PasteboardCopySettleState()

        _ = state.observe(
            originalChangeCount: 40,
            currentChangeCount: 40,
            currentText: "old clipboard",
            requiredStableObservations: 2
        )

        XCTAssertEqual(state.timeoutDecision(), .unavailable)
    }
}
