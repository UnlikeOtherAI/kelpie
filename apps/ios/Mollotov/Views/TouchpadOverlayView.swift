import SwiftUI
import WebKit

/// Fullscreen landscape overlay acting as a remote touchpad for the TV.
/// Right card: main touchpad (finger position maps to TV cursor, tap to click).
/// Left card: scroll strip (vertical drag scrolls the TV page).
struct TouchpadOverlayView: View {
    let onClose: () -> Void

    private let scrollStripWidth: CGFloat = 60
    private let gap: CGFloat = 12
    private let outerPadding: CGFloat = 16
    private let cornerRadius: CGFloat = 16

    @State private var cursorX: Double = 960
    @State private var cursorY: Double = 540
    @State private var lastScrollDragY: CGFloat = 0

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
                            let tvX = Double(value.location.x / geo.size.width) * 1920
                            let tvY = Double(value.location.y / geo.size.height) * 1080
                            cursorX = min(max(tvX, 0), 1920)
                            cursorY = min(max(tvY, 0), 1080)
                            moveCursor(x: cursorX, y: cursorY)
                        }
                        .onEnded { value in
                            let distance = hypot(value.translation.width, value.translation.height)
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
                        let delta = value.translation.height - lastScrollDragY
                        lastScrollDragY = value.translation.height
                        scrollBy(delta: delta * 4)
                    }
                    .onEnded { _ in
                        lastScrollDragY = 0
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
            var c = document.getElementById('mollotov-cursor');
            if (!c) {
                c = document.createElement('div');
                c.id = 'mollotov-cursor';
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
            "var c=document.getElementById('mollotov-cursor');if(c)c.remove();"
        )
    }

    @MainActor
    private func moveCursor(x: Double, y: Double) {
        tvWebView?.evaluateJavaScript(
            "var c=document.getElementById('mollotov-cursor');if(c){c.style.left='\(Int(x))px';c.style.top='\(Int(y))px';}"
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

    private func closeTouchpad() {
        removeCursor()
        onClose()
    }
}
