import AppKit
import XCTest
@testable import QuickDict

final class QuickDictServiceProviderTests: XCTestCase {
    func testSelectedTextNormalizesWhitespaceFromServicesPasteboard() {
        let pasteboard = makePasteboard()
        pasteboard.setString("  serendipity\n preserves   context  ", forType: .string)

        XCTAssertEqual(
            QuickDictServiceRequest.selectedText(from: pasteboard),
            "serendipity preserves context"
        )
    }

    func testSelectedTextRejectsMissingAndWhitespaceOnlyContent() {
        let emptyPasteboard = makePasteboard()
        XCTAssertNil(QuickDictServiceRequest.selectedText(from: emptyPasteboard))

        let whitespacePasteboard = makePasteboard()
        whitespacePasteboard.setString(" \n\t ", forType: .string)
        XCTAssertNil(QuickDictServiceRequest.selectedText(from: whitespacePasteboard))
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("QuickDictTests.\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        return pasteboard
    }
}
