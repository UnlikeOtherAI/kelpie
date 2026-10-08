import XCTest
@testable import Kelpie

final class AddressInputTests: XCTestCase {
    func testSearchAndNavigationAcrossNativeBridge() {
        XCTAssertEqual(AddressInput.resolve("GitHub"), "https://www.google.com/search?q=GitHub")
        XCTAssertEqual(AddressInput.resolve("cats & dogs"), "https://www.google.com/search?q=cats%20%26%20dogs")
        XCTAssertEqual(AddressInput.resolve("café 🐕"), "https://www.google.com/search?q=caf%C3%A9%20%F0%9F%90%95")
        XCTAssertEqual(AddressInput.resolve("github.com"), "https://github.com")
        XCTAssertEqual(AddressInput.resolve("http://minis.local:8420"), "http://minis.local:8420")
        XCTAssertEqual(AddressInput.resolve("about:blank"), "about:blank")
        XCTAssertNil(AddressInput.resolve(" \n\t"))
    }
}
