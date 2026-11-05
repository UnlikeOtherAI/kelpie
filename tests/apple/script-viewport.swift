import CoreGraphics
import Foundation

@main
struct ScriptViewportAcceptance {
    static func main() {
        func viewport(pageY: CGFloat = 0, offsetY: CGFloat = 0, width: CGFloat = 400, scale: CGFloat = 1) -> ScriptCaptureViewport {
            ScriptCaptureViewport(bounds: CGSize(width: 800, height: 400), layout: CGSize(width: 400, height: 200),
                                  visible: CGRect(x: 0, y: offsetY, width: width, height: 200),
                                  scale: scale, pixelRatio: 2, pageOrigin: CGPoint(x: 0, y: pageY))
        }
        let start = viewport()
        let scrolled = viewport(pageY: 600)
        precondition(start != scrolled)
        precondition(start.sameGeometry(as: scrolled))
        precondition(start.displayPoint(CGPoint(x: 100, y: 50)) == scrolled.displayPoint(CGPoint(x: 100, y: 50)))
        let panned = viewport(pageY: 630, offsetY: 30)
        precondition(scrolled != panned && scrolled.sameGeometry(as: panned))
        precondition(panned.displayPoint(CGPoint(x: 100, y: 80)) == CGPoint(x: 200, y: 100))
        precondition(!start.sameGeometry(as: viewport(width: 200, scale: 2)))
        print("PASS scroll/page-origin coherence, fixed geometry and client-coordinate pointer mapping")
    }
}
