import Foundation
import XCTest
@testable import Kelpie

final class IOSWorkflowReceiptTests: XCTestCase {
    @MainActor
    func testCanonicalMutationReceiptMatrix() throws {
        let fixture = try XCTUnwrap(Bundle(for: IOSWorkflowReceiptTests.self).url(
            forResource: "ack-receipt-cases", withExtension: "json"
        ))
        let decoded = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture))
        let matrix = try XCTUnwrap(decoded as? [String: Any])
        let token = try XCTUnwrap(matrix["expectedToken"] as? String)
        let cases = try XCTUnwrap(matrix["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 52)
        for item in cases {
            let name = try XCTUnwrap(item["name"] as? String)
            let body = item["result"] as? [String: Any] ?? [:]
            let receipt = IOSPacedTypingExecutor.isAcknowledgement(body, token: token) ? "ack" :
                IOSPacedTypingExecutor.isRefusal(body) ? "refusal" : "malformed"
            let latch = IOSPacedTypingExecutor.needsPrivacyLatch(body, token: token)
            let privacy = IOSPacedTypingExecutor.jsonBoolean(body["sensitive"]) == true ? "known-positive" :
                latch ? "unknown" : "known-negative"
            XCTAssertEqual(receipt, item["expectedReceipt"] as? String, name)
            XCTAssertEqual(privacy, item["expectedPrivacy"] as? String, name)
            XCTAssertEqual(latch, privacy != "known-negative", name)
        }
    }
}
