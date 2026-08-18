import XCTest
@testable import QuickDict

final class AppDelegateRuntimeTests: XCTestCase {
    func testHostedTestDetectionHappensFromInjectedEnvironmentBeforeRuntimeStartup() {
        XCTAssertTrue(
            AppDelegate.isHostedUnitTest(
                environment: ["XCTestConfigurationFilePath": "/tmp/QuickDictTests.xctestconfiguration"],
                xctestClassPresent: false
            )
        )
        XCTAssertTrue(
            AppDelegate.isHostedUnitTest(
                environment: ["XCInjectBundleInto": "/tmp/QuickDict.app/Contents/MacOS/QuickDict"],
                xctestClassPresent: false
            )
        )
        XCTAssertFalse(
            AppDelegate.isHostedUnitTest(environment: [:], xctestClassPresent: false)
        )
    }

}
