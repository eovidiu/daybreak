import XCTest
@testable import Daybreak

final class DeepLinkTests: XCTestCase {
    func testCaptureLinkParses() {
        XCTAssertEqual(DeepLink.parse(URL(string: "daybreak://capture")!), .capture)
    }

    func testWrongSchemeIsIgnored() {
        XCTAssertNil(DeepLink.parse(URL(string: "https://capture")!))
    }

    func testUnknownHostIsIgnored() {
        XCTAssertNil(DeepLink.parse(URL(string: "daybreak://settings")!))
    }
}
