import CoreImage
import ImageIO
import XCTest

extension WorkflowCaptureUITests {
    @MainActor
    func testScrollReadinessAndCommentaryAppearInTheCorrespondingSteps() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let origin = "http://127.0.0.1:" + String(try XCTUnwrap(fixture.listener.port?.rawValue))
        let steps: [Body] = [
            ["action": "navigate", "url": origin + "/scroll"],
            ["action": "assert", "state": "hidden", "target": ["selector": "#absent"]],
            ["action": "scroll", "deltaY": 16000],
            ["action": "wait-ready", "selector": "#bottom"],
            ["action": "assert", "state": "enabled", "target": ["role": "button", "name": "Bottom"]],
            ["action": "screenshot", "name": "beforeNote"],
            ["action": "commentary", "text": "Reached the bottom", "position": "center", "durationMs": 3000]
        ]
        let result = try await probe.call("kelpie_play_script", [
            "version": 1, "tabId": tab, "actions": steps, "capture": ["formats": ["screenshots"], "maxWidth": 384]
        ])
        XCTAssertEqual(result["success"] as? Bool, true)
        let run = try XCTUnwrap(result["runId"] as? String)
        let manifests = try XCTUnwrap(result["artifacts"] as? [Body])
        XCTAssertEqual(manifests.compactMap { $0["actionIndex"] as? Int }, Array(steps.indices))
        let bare = try XCTUnwrap(manifests.first { $0["actionIndex"] as? Int == 5 })
        let note = try XCTUnwrap(manifests.first { $0["actionIndex"] as? Int == 6 })
        let before = try await probe.bytes(bare, run: run)
        let after = try await probe.bytes(note, run: run)
        XCTAssertGreaterThan(try centerBrightness(before) - centerBrightness(after), 65)
        let attachment = XCTAttachment(data: after, uniformTypeIdentifier: "public.png")
        attachment.name = "Step screenshot with centered commentary after scroll"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func centerBrightness(_ png: Data) throws -> Int {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let extent = CGRect(x: Double(image.width) * 0.45, y: Double(image.height) * 0.495,
                            width: Double(image.width) * 0.1, height: max(1, Double(image.height) * 0.01))
        let area = try XCTUnwrap(CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: CIImage(cgImage: image), kCIInputExtentKey: CIVector(cgRect: extent)
        ])?.outputImage)
        var rgba = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(area, toBitmap: &rgba, rowBytes: 4, bounds: area.extent, format: .RGBA8, colorSpace: nil)
        return (Int(rgba[0]) + Int(rgba[1]) + Int(rgba[2])) / 3
    }
}
