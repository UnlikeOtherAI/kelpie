import SwiftUI
import WebKit

/// Fullscreen landscape overlay acting as a remote touchpad for the TV.
/// Right card: main touchpad (finger position maps to TV cursor, tap to click).
/// Left card: scroll strip (vertical drag scrolls the TV page).
struct TouchpadOverlayView: View {
    let onClose: () -> Void

    private let tvViewport = CGSize(width: 1920, height: 1080)
    private let scrollStripWidth: CGFloat = 60
    private let gap: CGFloat = 12
    private let outerPadding: CGFloat = 16
    private let cornerRadius: CGFloat = 16
    private let cursorGain = 1.35
    private let scrollGain = 5.5
    private let momentumDecay = 0.9
    private let momentumThreshold = 0.75
    private let momentumTick = 1.0 / 60.0

    @State private var cursorX: Double = 960
    @State private var cursorY: Double = 540
    @State private var lastCursorDragLocation: CGPoint?
    @State private var lastScrollDragY: CGFloat = 0
    @State private var scrollVelocity: Double = 0
    @State private var scrollMomentumTimer: Timer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            HStack(spacing: gap) {
                scrollStrip
                    .frame(width: scrollStripWidth)
                mainTouchpad
            }
            .padding(outerPadding)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: closeTouchpad) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(20)
        }
        .ignoresSafeArea()
        .onAppear { injectCursor() }
        .onDisappear { stopScrollMomentum() }
    }

    // MARK: - Main Touchpad

    private var mainTouchpad: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard let previousLocation = lastCursorDragLocation else {
                                lastCursorDragLocation = value.location
                                return
                            }

                            let deltaX = value.location.x - previousLocation.x
                            let deltaY = value.location.y - previousLocation.y
                            lastCursorDragLocation = value.location
                            moveCursor(byX: deltaX, byY: deltaY, touchpadSize: geo.size)
                        }
                        .onEnded { value in
                            let distance = hypot(value.translation.width, value.translation.height)
                            lastCursorDragLocation = nil
                            if distance < 10 {
                                clickAt(x: cursorX, y: cursorY)
                            }
                        }
                )
        }
    }

    // MARK: - Scroll Strip

    private var scrollStrip: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        stopScrollMomentum()
                        let delta = value.translation.height - lastScrollDragY
                        lastScrollDragY = value.translation.height
                        let scrollDelta = Double(delta) * scrollGain
                        scrollVelocity = scrollDelta
                        scrollBy(delta: scrollDelta)
                    }
                    .onEnded { value in
                        let predictedTail = value.predictedEndTranslation.height - value.translation.height
                        let releaseVelocity = scrollVelocity + (Double(predictedTail) * scrollGain * 0.12)
                        lastScrollDragY = 0
                        startScrollMomentum(with: releaseVelocity)
                    }
            )
    }

    // MARK: - TV WebView Interaction

    @MainActor
    private var tvWebView: WKWebView? {
        ExternalDisplayManager.shared.serverState?.handlerContext.webView
    }

    @MainActor
    private func injectCursor() {
        guard let wv = tvWebView else { return }
        wv.evaluateJavaScript("""
        (function(){
            var c = document.getElementById('kelpie-cursor');
            if (!c) {
                c = document.createElement('div');
                c.id = 'kelpie-cursor';
                c.style.cssText = 'position:fixed;width:24px;height:24px;border-radius:50%;' +
                    'background:rgba(255,255,255,0.9);border:2px solid rgba(0,0,0,0.3);' +
                    'pointer-events:none;z-index:2147483647;transform:translate(-50%,-50%);' +
                    'box-shadow:0 2px 8px rgba(0,0,0,0.3);left:960px;top:540px;';
                document.body.appendChild(c);
            }
        })();
        """)
    }

    @MainActor
    private func removeCursor() {
        tvWebView?.evaluateJavaScript(
            "var c=document.getElementById('kelpie-cursor');if(c)c.remove();"
        )
    }

    @MainActor
    private func moveCursor(byX deltaX: CGFloat, byY deltaY: CGFloat, touchpadSize: CGSize) {
        guard touchpadSize.width > 0, touchpadSize.height > 0 else { return }

        let scaledX = Double(deltaX / touchpadSize.width) * tvViewport.width * cursorGain
        let scaledY = Double(deltaY / touchpadSize.height) * tvViewport.height * cursorGain

        cursorX = min(max(cursorX + scaledX, 0), tvViewport.width)
        cursorY = min(max(cursorY + scaledY, 0), tvViewport.height)

        renderCursor(x: cursorX, y: cursorY)
    }

    @MainActor
    private func renderCursor(x: Double, y: Double) {
        tvWebView?.evaluateJavaScript(
            "var c=document.getElementById('kelpie-cursor');if(c){c.style.left='\(Int(x))px';c.style.top='\(Int(y))px';}"
        )
    }

    @MainActor
    private func clickAt(x: Double, y: Double) {
        tvWebView?.evaluateJavaScript("""
        (function(){
            var el = document.elementFromPoint(\(Int(x)),\(Int(y)));
            if(el){
                ['pointerdown','pointerup','mousedown','mouseup','click'].forEach(function(t){
                    el.dispatchEvent(new PointerEvent(t,{bubbles:true,cancelable:true,
                        clientX:\(Int(x)),clientY:\(Int(y)),view:window,pointerId:1,pointerType:'mouse'}));
                });
            }
        })();
        """)
    }

    @MainActor
    private func scrollBy(delta: Double) {
        tvWebView?.evaluateJavaScript("window.scrollBy(0,\(delta))")
    }

    private func startScrollMomentum(with velocity: Double) {
        scrollVelocity = velocity
        guard abs(scrollVelocity) >= momentumThreshold else {
            scrollVelocity = 0
            return
        }

        stopScrollMomentum()

        let timer = Timer(timeInterval: momentumTick, repeats: true) { _ in
            Task { @MainActor in
                guard abs(scrollVelocity) >= momentumThreshold else {
                    stopScrollMomentum()
                    return
                }

                scrollBy(delta: scrollVelocity)
                scrollVelocity *= momentumDecay
            }
        }

        scrollMomentumTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopScrollMomentum() {
        scrollMomentumTimer?.invalidate()
        scrollMomentumTimer = nil
    }

    private func closeTouchpad() {
        stopScrollMomentum()
        removeCursor()
        onClose()
    }
}
