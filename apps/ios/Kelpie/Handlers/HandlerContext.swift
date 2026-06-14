import WebKit

enum ScreenshotResolution: String {
    case native
    case viewport

    static func parse(_ raw: Any?) -> Self? {
        guard let raw else { return .native }
        guard let value = raw as? String else { return nil }
        return Self(rawValue: value)
    }
}

struct ScreenshotViewportMetrics {
    let viewportWidth: Int
    let viewportHeight: Int
    let devicePixelRatio: Double

    func metadata(
        imageWidth: Int,
        imageHeight: Int,
        format: String,
        resolution: ScreenshotResolution
    ) -> [String: Any] {
        let scaleX = viewportWidth > 0 ? Double(imageWidth) / Double(viewportWidth) : 1
        let scaleY = viewportHeight > 0 ? Double(imageHeight) / Double(viewportHeight) : 1
        return [
            "width": imageWidth,
            "height": imageHeight,
            "format": format,
            "resolution": resolution.rawValue,
            "coordinateSpace": "viewport-css-pixels",
            "viewportWidth": viewportWidth,
            "viewportHeight": viewportHeight,
            "devicePixelRatio": devicePixelRatio,
            "imageScaleX": scaleX,
            "imageScaleY": scaleY
        ]
    }
}

private func imagePixelSize(_ image: UIImage) -> (width: Int, height: Int) {
    if let cgImage = image.cgImage {
        return (cgImage.width, cgImage.height)
    }
    return (
        Int(round(image.size.width * image.scale)),
        Int(round(image.size.height * image.scale))
    )
}

private func scaledImage(
    from image: UIImage,
    to resolution: ScreenshotResolution,
    using viewport: ScreenshotViewportMetrics
) -> UIImage {
    guard resolution == .viewport else { return image }
    let sourceSize = imagePixelSize(image)
    let targetWidth = max(Int(round(Double(sourceSize.width) / max(viewport.devicePixelRatio, 1.0))), 1)
    let targetHeight = max(Int(round(Double(sourceSize.height) / max(viewport.devicePixelRatio, 1.0))), 1)
    guard targetWidth != sourceSize.width || targetHeight != sourceSize.height else {
        return image
    }

    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetWidth, height: targetHeight), format: format)
    return renderer.image { _ in
        image.draw(in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
    }
}

/// Shared context providing access to the WebView for all handlers.
@MainActor
final class HandlerContext: NSObject, WKScriptMessageHandler {
    nonisolated static let defaultOverlayRGB = "59,130,246"

    weak var webView: WKWebView?
    var tabStore: TabStore?
    var consoleMessages: [[String: Any]] = []
    var isIn3DInspector = false
    var scriptPlaybackState: ScriptPlaybackState?
    var annotationSessionId: String?
    var annotationPageURL: String?
    var annotationElementCount: Int?
    let safariAuth = SafariAuthHelper()
    let dialogState = DialogState()
    let keyboardObserver = KeyboardObserver()

    /// Most recent WebView navigation error (cleared on each new navigation).
    var lastNavigationError: String?

    override nonisolated init() { super.init() }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }

        switch message.name {
        case "kelpieConsole":
            let text = body["message"] as? String ?? body["text"] as? String ?? ""
            if text == "__kelpie_3d_exit__" && isIn3DInspector {
                Task { @MainActor in
                    await exit3DInspectorIfNeeded(notify: true)
                }
                return
            }
            consoleMessages.append(body)
            if consoleMessages.count > 5000 { consoleMessages.removeFirst() }

        case "kelpie3DSnapshot":
            if body["action"] as? String == "exit" {
                Task { @MainActor in
                    await exit3DInspectorIfNeeded(notify: true)
                }
            }

        case "kelpieNetwork":
            let entry = NetworkTrafficStore.TrafficEntry(
                id: UUID(),
                method: (body["method"] as? String ?? "GET").uppercased(),
                url: body["url"] as? String ?? "",
                statusCode: body["statusCode"] as? Int ?? 0,
                contentType: body["contentType"] as? String ?? "",
                requestHeaders: body["requestHeaders"] as? [String: String] ?? [:],
                responseHeaders: body["responseHeaders"] as? [String: String] ?? [:],
                requestBody: body["requestBody"] as? String,
                responseBody: body["responseBody"] as? String,
                startTime: Date(),
                duration: body["duration"] as? Int ?? 0,
                size: body["size"] as? Int ?? 0,
                initiator: "js"
            )
            NetworkTrafficStore.shared.append(entry)

        default:
            break
        }
    }

    func evaluateJS(_ script: String) async throws -> Any? {
        guard let webView else { throw HandlerError.noWebView }
        return try await webView.evaluateJavaScript(script)
    }

    func evaluateJSReturningString(_ script: String) async throws -> String {
        let result = try await evaluateJS(script)
        return result as? String ?? String(describing: result ?? "null")
    }

    func evaluateJSReturningArray(_ script: String) async throws -> [[String: Any]] {
        let wrapped = "JSON.stringify((\(script)))"
        let jsonString = try await evaluateJSReturningString(wrapped)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return json
    }

    /// Show a touch indicator at viewport coordinates with a ripple animation.
    func showTouchIndicator(x: Double, y: Double, color: String = HandlerContext.defaultOverlayRGB) async {
        let js = """
        (function() {
            var dot = document.createElement('div');
            dot.style.cssText = 'position:fixed;left:\(x)px;top:\(y)px;width:36px;height:36px;' +
                'margin-left:-18px;margin-top:-18px;border-radius:50%;' +
                'background:rgba(\(JSEscape.string(color)),0.7);pointer-events:none;z-index:2147483647;' +
                'transition:transform 0.5s ease-out, opacity 0.5s ease-out;transform:scale(1);opacity:1;';
            document.body.appendChild(dot);
            var ripple = document.createElement('div');
            ripple.style.cssText = 'position:fixed;left:\(x)px;top:\(y)px;width:36px;height:36px;' +
                'margin-left:-18px;margin-top:-18px;border-radius:50%;' +
                'border:2px solid rgba(\(JSEscape.string(color)),0.7);pointer-events:none;z-index:2147483647;' +
                'transition:transform 0.6s ease-out, opacity 0.6s ease-out;transform:scale(1);opacity:1;';
            document.body.appendChild(ripple);
            requestAnimationFrame(function() {
                ripple.style.transform = 'scale(3)';
                ripple.style.opacity = '0';
            });
            setTimeout(function() {
                dot.style.transform = 'scale(0.5)';
                dot.style.opacity = '0';
            }, 550);
            setTimeout(function() {
                dot.remove();
                ripple.remove();
            }, 1100);
        })();
        """
        _ = try? await evaluateJS(js)
    }

    /// Show touch indicator at an element's center by selector.
    func showTouchIndicatorForElement(_ selector: String, color: String = HandlerContext.defaultOverlayRGB) async {
        let js = """
        (function() {
            var el = document.querySelector('\(JSEscape.string(selector))');
            if (!el) return JSON.stringify(null);
            var r = el.getBoundingClientRect();
            return JSON.stringify({x: r.left + r.width/2, y: r.top + r.height/2});
        })()
        """
        if let result = try? await evaluateJSReturningString(js),
           let data = result.data(using: .utf8),
           let pos = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
           let x = pos["x"], let y = pos["y"] {
            await showTouchIndicator(x: x, y: y, color: color)
        }
    }

    /// Show a toast message overlay at the bottom of the viewport.
    func showToast(_ message: String) async {
        let js = """
        (function() {
            var existing = document.getElementById('__kelpie_toast');
            if (existing) existing.remove();
            var toast = document.createElement('div');
            toast.id = '__kelpie_toast';
            toast.textContent = '\(JSEscape.string(message))';
            toast.style.cssText = 'position:fixed;bottom:24px;left:50%;transform:translateX(-50%);' +
                'max-width:390px;width:calc(100% - 32px);padding:14px 22px;border-radius:16px;' +
                'background:rgba(0,0,0,0.5);color:#fff;font:15px/1.4 -apple-system,system-ui,sans-serif;' +
                'text-align:center;pointer-events:none;z-index:2147483647;' +
                'backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);' +
                'transition:opacity 0.3s ease-out;opacity:0;';
            document.body.appendChild(toast);
            requestAnimationFrame(function() { toast.style.opacity = '1'; });
            setTimeout(function() {
                toast.style.opacity = '0';
                setTimeout(function() { toast.remove(); }, 300);
            }, 3000);
        })();
        """
        _ = try? await evaluateJS(js)
    }

    func evaluateJSReturningJSON(_ script: String) async throws -> [String: Any] {
        let wrapped = "JSON.stringify((\(script)))"
        let jsonString = try await evaluateJSReturningString(wrapped)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    func screenshotViewportMetrics() async throws -> ScreenshotViewportMetrics {
        let result = try await evaluateJSReturningJSON("""
        (function() {
            return {
                viewportWidth: Math.max(window.innerWidth || 0, 1),
                viewportHeight: Math.max(window.innerHeight || 0, 1),
                devicePixelRatio: window.devicePixelRatio || 1
            };
        })()
        """)
        return ScreenshotViewportMetrics(
            viewportWidth: (result["viewportWidth"] as? NSNumber)?.intValue ?? 1,
            viewportHeight: (result["viewportHeight"] as? NSNumber)?.intValue ?? 1,
            devicePixelRatio: (result["devicePixelRatio"] as? NSNumber)?.doubleValue ?? 1
        )
    }

    func screenshotPayload(
        from image: UIImage,
        format: String,
        quality: Double,
        resolution: ScreenshotResolution
    ) async throws -> [String: Any] {
        let viewport = try await screenshotViewportMetrics()
        let normalizedFormat = format == "jpeg" ? "jpeg" : "png"
        let rendered = scaledImage(from: image, to: resolution, using: viewport)
        let imageData: Data?
        if normalizedFormat == "jpeg" {
            imageData = rendered.jpegData(compressionQuality: quality)
        } else {
            imageData = rendered.pngData()
        }
        guard let encoded = imageData else {
            throw HandlerError.screenshotFailed
        }
        let pixelSize = imagePixelSize(rendered)
        return [
            "image": encoded.base64EncodedString()
        ].merging(
            viewport.metadata(
                imageWidth: pixelSize.width,
                imageHeight: pixelSize.height,
                format: normalizedFormat,
                resolution: resolution
            )
        ) { _, new in new }
    }

    func mark3DInspectorInactive(notify: Bool) {
        isIn3DInspector = false
        if notify {
            NotificationCenter.default.post(name: .snapshot3DExited, object: nil)
        }
    }

    func exit3DInspectorIfNeeded(notify: Bool) async {
        guard isIn3DInspector else { return }
        _ = try? await evaluateJS(Snapshot3DBridge.exitScript)
        mark3DInspectorInactive(notify: notify)
    }

    nonisolated static func hexToRGB(_ hex: String) -> String {
        let normalized = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard normalized.count == 6,
              let red = UInt8(normalized.prefix(2), radix: 16),
              let green = UInt8(normalized.dropFirst(2).prefix(2), radix: 16),
              let blue = UInt8(normalized.dropFirst(4).prefix(2), radix: 16) else {
            return defaultOverlayRGB
        }
        return "\(red),\(green),\(blue)"
    }
}

enum HandlerError: Error {
    case noWebView
    case elementNotFound(String)
    case screenshotFailed
    case timeout
    case platformNotSupported(String)
}

func errorResponse(code: String, message: String) -> [String: Any] {
    errorResponse(code: code, message: message, diagnostics: nil)
}

func errorResponse(code: String, message: String, diagnostics: [String: Any]?) -> [String: Any] {
    var error: [String: Any] = ["code": code, "message": message]
    if let diagnostics, !diagnostics.isEmpty {
        error["diagnostics"] = diagnostics
    }
    return ["success": false, "error": error]
}

func successResponse(_ data: [String: Any] = [:]) -> [String: Any] {
    var result: [String: Any] = ["success": true]
    for (key, value) in data { result[key] = value }
    return result
}

extension Notification.Name {
    static let snapshot3DExited = Notification.Name("kelpie.snapshot3DExited")
}
