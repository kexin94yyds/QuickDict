import AppKit
import XCTest
@testable import QuickDict

final class ECDICTDownloadProgressUITests: XCTestCase {
    @MainActor
    func testProgressWindowUsesARCManagedCloseLifetime() {
        let progressUI = ECDICTDownloadProgressUI()

        XCTAssertFalse(progressUI.window.isReleasedWhenClosed)
        progressUI.close()
        XCTAssertNotNil(progressUI.window.contentView)
    }

    @MainActor
    func testProgressValueIsClampedToWindowRange() {
        let progressUI = ECDICTDownloadProgressUI()

        progressUI.updateProgress(1.5)

        XCTAssertEqual(progressUI.progressIndicator.doubleValue, 1)
        XCTAssertEqual(progressUI.label.stringValue, "正在下载词典… 100%")
    }

    func testPublishedECDICTAssetSizesMatchReleaseEvidence() {
        XCTAssertEqual(ECDictionary.expectedArchiveBytes, 216_765_132)
        XCTAssertEqual(ECDictionary.expectedDatabaseBytes, 851_288_064)
        XCTAssertEqual(ECDictionary.downloadSizeDescription, "下载约 217 MB，解压后约 851 MB")
    }

    func testTemporaryDownloadedArchiveIsRemovedAfterSuccess() throws {
        let archiveURL = try makeTemporaryArchive()

        let returnedName = ECDictionary.withTemporaryDownloadedArchive(at: archiveURL) { url in
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            return url.lastPathComponent
        }

        XCTAssertEqual(returnedName, archiveURL.lastPathComponent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))
    }

    func testTemporaryDownloadedArchiveIsRemovedAfterFailure() throws {
        struct ExpectedFailure: Error {}
        let archiveURL = try makeTemporaryArchive()

        XCTAssertThrowsError(
            try ECDictionary.withTemporaryDownloadedArchive(at: archiveURL) { _ in
                throw ExpectedFailure()
            }
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))
    }

    private func makeTemporaryArchive() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickDict_test_\(UUID().uuidString).zip")
        try Data("archive".utf8).write(to: url, options: .atomic)
        return url
    }
}
