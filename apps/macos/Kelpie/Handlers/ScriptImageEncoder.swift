import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ScriptImageEncoder {
    static func png(_ image: CGImage, to url: URL, budget: ScriptCaptureBudget) throws {
        try budget.withConsumer(url: url) { consumer in
            guard let destination = CGImageDestinationCreateWithDataConsumer(consumer, UTType.png.identifier as CFString, 1, nil) else {
                throw ScriptCaptureError.image
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw ScriptCaptureError.budget }
        }
        try budget.check()
    }

    static func gif(
        frames: [(URL, Double)],
        fps: Int,
        endSeconds: Double,
        to url: URL,
        budget: ScriptCaptureBudget,
        shouldContinue: @Sendable () -> Bool = { true }
    ) throws -> ScriptGIFEncoder.Result {
        try ScriptGIFEncoder.encode(frames: frames, fps: fps, endSeconds: endSeconds, to: url, budget: budget, shouldContinue: shouldContinue)
    }
}
