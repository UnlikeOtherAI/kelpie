import XCTest
@testable import Kelpie

final class ConnectScreenshotBudgetTests: XCTestCase {
    private func shot(_ format: String, _ size: Int) -> [String: Any] {
        ["success": true, "format": format, "image": String(repeating: "A", count: size)]
    }

    func testSmallScreenshotPassesThroughUnchanged() async {
        var calls: [[String: Any]] = []
        let result = await ConnectScreenshotBudget.fit(["tabId": "t"]) { params in
            calls.append(params)
            return self.shot("png", 10)
        }
        XCTAssertEqual(result["format"] as? String, "png")
        XCTAssertEqual(calls.count, 1)
        XCTAssertNil(calls[0]["format"])
    }

    func testOversizedPngFallsBackToFirstFittingJpeg() async {
        var calls: [[String: Any]] = []
        let result = await ConnectScreenshotBudget.fit(["tabId": "t"]) { params in
            calls.append(params)
            return params["quality"] as? Int == 60 ? self.shot("jpeg", 100) : self.shot("png", 700 * 1024)
        }
        XCTAssertEqual(result["format"] as? String, "jpeg")
        XCTAssertEqual(calls.map { $0["quality"] as? Int }, [nil, 80, 60])
        XCTAssertEqual(calls.last?["tabId"] as? String, "t")
    }

    func testJpegRequestOnlyRetriesLowerQualities() async {
        var qualities: [Int?] = []
        _ = await ConnectScreenshotBudget.fit(["format": "jpeg", "quality": 80]) { params in
            qualities.append(params["quality"] as? Int)
            return self.shot("jpeg", 700 * 1024)
        }
        XCTAssertEqual(qualities, [80, 60, 40])
    }

    func testNothingFittingIsRefusedAsTooLarge() async {
        let result = await ConnectScreenshotBudget.fit([:]) { _ in self.shot("jpeg", 700 * 1024) }
        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual((result["error"] as? [String: Any])?["code"] as? String, "SCREENSHOT_TOO_LARGE")
    }

    func testFenceRefusalDuringRecaptureIsReturned() async {
        var call = 0
        let result = await ConnectScreenshotBudget.fit([:]) { _ in
            call += 1
            return call == 1 ? self.shot("png", 700 * 1024)
                : ["success": false, "error": ["code": "TAB_CHANGED"]]
        }
        XCTAssertEqual((result["error"] as? [String: Any])?["code"] as? String, "TAB_CHANGED")
        XCTAssertEqual(call, 2)
    }
}
