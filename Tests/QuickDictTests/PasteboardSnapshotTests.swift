import AppKit
import XCTest
@testable import QuickDict

final class PasteboardSnapshotTests: XCTestCase {
    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("com.kexin.quickdict.tests.\(UUID().uuidString)"))
    }

    func testPlainTextRoundTripRestoresExactSnapshot() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("original sentinel", forType: .string))
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("copied word", forType: .string))
        let result = snapshot.restore(to: pasteboard)

        XCTAssertTrue(result.attempted)
        XCTAssertTrue(result.representationsAccepted)
        XCTAssertTrue(result.writeSucceeded)
        XCTAssertTrue(result.exactMatch)
        XCTAssertEqual(pasteboard.string(forType: .string), "original sentinel")
    }

    func testMultipleRepresentationsRoundTripWithoutDroppingData() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        let customType = NSPasteboard.PasteboardType("com.kexin.quickdict.test-data")
        let originalItem = NSPasteboardItem()
        XCTAssertTrue(originalItem.setString("rich sentinel", forType: .string))
        XCTAssertTrue(originalItem.setData(Data([0x00, 0x01, 0xFE, 0xFF]), forType: customType))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([originalItem]))
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("copied word", forType: .string))
        let result = snapshot.restore(to: pasteboard)

        XCTAssertTrue(result.writeSucceeded)
        XCTAssertTrue(result.exactMatch)
        XCTAssertEqual(pasteboard.string(forType: .string), "rich sentinel")
        XCTAssertEqual(pasteboard.data(forType: customType), Data([0x00, 0x01, 0xFE, 0xFF]))
    }

    func testIncompleteSnapshotDoesNotClearCurrentPasteboard() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("keep current content", forType: .string))
        let incomplete = PasteboardSnapshot(
            items: [.init(representations: [:])],
            missingRepresentationCount: 1
        )

        let result = incomplete.restore(to: pasteboard)

        XCTAssertFalse(result.attempted)
        XCTAssertFalse(result.writeSucceeded)
        XCTAssertEqual(pasteboard.string(forType: .string), "keep current content")
    }

    func testEmptySnapshotRestoresAnEmptyPasteboard() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        let emptySnapshot = PasteboardSnapshot.capture(from: pasteboard)
        XCTAssertTrue(pasteboard.setString("copied word", forType: .string))

        let result = emptySnapshot.restore(to: pasteboard)

        XCTAssertTrue(result.attempted)
        XCTAssertTrue(result.writeSucceeded)
        XCTAssertTrue(result.exactMatch)
        XCTAssertNil(pasteboard.string(forType: .string))
    }
}
