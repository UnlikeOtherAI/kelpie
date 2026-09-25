#if os(macOS)
import AppKit
typealias ChromeSampleImage = NSImage
#else
import UIKit
typealias ChromeSampleImage = UIImage
#endif
import WebKit

/// Samples only a tiny visible page strip, on demand. No page scripts or idle polling.
@MainActor
final class BrowserChromeSampler {
    private weak var webView: WKWebView?
    private var loadingObservation: NSKeyValueObservation?
    private var pending: Task<Void, Never>?
    private var settledSample: Task<Void, Never>?
    private var generation = 0
    private var sampling = false
    private var needsSample = false
    private var currentURL: URL?
    private var onSample: (ChromeRGB?) -> Void = { _ in }

    func navigationStarted() {
        generation += 1
        settledSample?.cancel()
        pending?.cancel()
        pending = nil
    }

    func update(webView: WKWebView?, onSample: @escaping (ChromeRGB?) -> Void) {
        self.onSample = onSample
        if webView == nil { onSample(nil) }
        if self.webView !== webView {
            generation += 1
            settledSample?.cancel()
            pending?.cancel()
            pending = nil
            loadingObservation = nil
            self.webView = webView
            currentURL = webView?.url
            loadingObservation = webView?.observe(\.isLoading, options: [.new]) { [weak self] _, change in
                guard change.newValue == false else { return }
                Task { @MainActor in self?.requestSample() }
            }
            if webView != nil { requestSample() }
        } else if currentURL != webView?.url {
            generation += 1
            currentURL = webView?.url
            requestSample()
        }
    }

    /// A final sample catches sticky-header CSS transitions after the last wheel event.
    /// This is bounded to one trailing capture, never an idle timer.
    func sampleAfterScroll() {
        requestSample()
        settledSample?.cancel()
        settledSample = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            self?.requestSample()
        }
    }

    func requestSample() {
        guard webView != nil else { return }
        needsSample = true
        guard pending == nil, !sampling else { return }
        pending = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
            guard let self else { return }
            self.pending = nil
            self.capture()
        }
    }

    private func capture() {
        guard let webView, !webView.isHidden, webView.bounds.width > 0, webView.bounds.height > 0 else { return }
        needsSample = false
        sampling = true
        let request = generation
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: webView.bounds.width, height: min(12, webView.bounds.height))
        configuration.snapshotWidth = 64
        webView.takeSnapshot(with: configuration) { [weak self, weak webView] image, _ in
            guard let self else { return }
            self.sampling = false
            if request == self.generation, webView === self.webView,
               let image, let sample = Self.backgroundColor(image) {
                self.onSample(sample)
            }
            if self.needsSample { self.requestSample() }
        }
    }

    static func backgroundColor(_ image: ChromeSampleImage) -> ChromeRGB? {
        // Draw into explicit sRGB: TIFF round-tripping loses the drawing image's
        // colour profile and skews dark page colours on wide-gamut displays.
        let width = 64, height = 4
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        #if os(macOS)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        #else
        guard let cgImage = image.cgImage else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        #endif
        var red: [Double] = [], green: [Double] = [], blue: [Double] = []
        for offset in stride(from: 0, to: width * height * 4, by: 4) where pixels[offset + 3] > 127 {
            let alpha = Double(pixels[offset + 3])
            red.append(Double(pixels[offset]) / alpha)
            green.append(Double(pixels[offset + 1]) / alpha)
            blue.append(Double(pixels[offset + 2]) / alpha)
        }
        guard !red.isEmpty else { return nil }
        // The median follows the background instead of whitening dark headers
        // when bright text, logos or a scrollbar enter the sampled strip.
        let middle = red.count / 2
        return ChromeRGB(red: red.sorted()[middle], green: green.sorted()[middle], blue: blue.sorted()[middle])

    }

    deinit { pending?.cancel(); settledSample?.cancel() }
}
