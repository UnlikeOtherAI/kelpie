import AVFoundation
import CoreImage
import ImageIO
import XCTest

extension WorkflowCaptureUITests {
    private struct Frame {
        let time: Double
        let duration: Double
        let marker: Bool
        let landed: Bool

        init(_ image: CGImage, time: Double, duration: Double) {
            self.time = time
            self.duration = duration
            marker = WorkflowCaptureProbe.containsMarker(image)
            var pixel = [UInt8](repeating: 0, count: 4)
            landed = pixel.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                              bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                return buffer[2] > 145 && buffer[0] < 100 && buffer[1] < 125
            }
        }
    }

    @MainActor
    func testOneFPSMoviesRetainOldDocumentMarkerBeforeLinkNavigation() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let result = try await probe.call("kelpie_play_script", [
            "version": 1, "tabId": tab,
            "actions": [
                ["action": "tap", "target": ["role": "link", "name": "Continue"]],
                ["action": "wait-ready", "selector": "#landed"],
                ["action": "output", "source": "title", "name": "page"]
            ],
            "tapIndicator": ["color": "#00FF00", "radius": 24, "durationMs": 300],
            "capture": ["formats": ["gif", "video"], "fps": 1, "maxWidth": 384]
        ])
        XCTAssertEqual(result["success"] as? Bool, true, "\(result["error"] ?? "")")
        XCTAssertEqual((result["outputs"] as? Body)?["page"] as? String, "Landed")
        let manifests = try XCTUnwrap(result["artifacts"] as? [Body])
        XCTAssertEqual(Set(manifests.compactMap { $0["mimeType"] as? String }), ["image/gif", "video/mp4"])
        let run = try XCTUnwrap(result["runId"] as? String)
        for manifest in manifests {
            let type = try XCTUnwrap(manifest["mimeType"] as? String)
            let bytes = try await probe.bytes(manifest, run: run)
            let frames = type == "image/gif" ? try gifFrames(bytes) : try await videoFrames(bytes)
            let firstMarker = try XCTUnwrap(frames.firstIndex { $0.marker })
            let arrival = try XCTUnwrap(frames.firstIndex { $0.landed })
            XCTAssertLessThan(firstMarker, arrival)
            XCTAssertTrue(frames[arrival...].allSatisfy { !$0.marker && $0.landed })
            XCTAssertGreaterThanOrEqual(frames[arrival].time - frames[firstMarker].time, 0.98)
            for (first, second) in zip(frames, frames.dropFirst()) {
                XCTAssertGreaterThanOrEqual(second.time - first.time, 0.98, "FPS limit violated for \(type)")
            }
            let report = frames.map { "\($0.time)\t\($0.duration)\t\($0.marker)\t\($0.landed)" }.joined(separator: "\n")
            let timing = XCTAttachment(string: "PTS seconds\tduration seconds\tgreen marker\tblue destination\n" + report)
            timing.name = "\(type) navigation timing"
            timing.lifetime = .keepAlways
            add(timing)
            let movie = XCTAttachment(data: bytes, uniformTypeIdentifier: type == "image/gif" ? "com.compuserve.gif" : "public.mpeg-4")
            movie.name = "\(type) one FPS link navigation"
            movie.lifetime = .keepAlways
            add(movie)
        }
    }

    private func gifFrames(_ data: Data) throws -> [Frame] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        var elapsed = 0.0
        return try (0..<CGImageSourceGetCount(source)).map { index in
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, index, nil))
            let info = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? Body)
            let gif = try XCTUnwrap(info[kCGImagePropertyGIFDictionary as String] as? Body)
            let duration = try XCTUnwrap((gif[kCGImagePropertyGIFUnclampedDelayTime as String] ??
                gif[kCGImagePropertyGIFDelayTime as String]) as? Double)
            defer { elapsed += duration }
            return Frame(image, time: elapsed, duration: duration)
        }
    }

    private func videoFrames(_ bytes: Data) async throws -> [Frame] {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try bytes.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let asset = AVURLAsset(url: file)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        let context = CIContext(options: [.useSoftwareRenderer: true])
        var frames: [Frame] = []
        while let sample = output.copyNextSampleBuffer() {
            let buffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
            let source = CIImage(cvPixelBuffer: buffer)
            let image = try XCTUnwrap(context.createCGImage(source, from: source.extent))
            frames.append(Frame(image, time: CMSampleBufferGetPresentationTimeStamp(sample).seconds,
                                duration: CMSampleBufferGetDuration(sample).seconds))
        }
        XCTAssertEqual(reader.status, .completed)
        return frames
    }
}
