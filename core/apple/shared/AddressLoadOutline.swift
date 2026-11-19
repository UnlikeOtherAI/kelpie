import SwiftUI

/// A single stroke runs around the capsule from right to right. Trimming it
/// symmetrically around its midpoint reveals both sides from the left edge.
private struct AddressLoadOutline: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: 1.5, dy: 1.5)
        let radius = min(bounds.height, bounds.width) / 2
        guard radius > 0 else { return Path() }
        let right = CGPoint(x: bounds.maxX - radius, y: bounds.midY)
        let left = CGPoint(x: bounds.minX + radius, y: bounds.midY)
        var path = Path()
        path.addRelativeArc(center: right, radius: radius, startAngle: .zero, delta: .degrees(-90))
        path.addRelativeArc(center: left, radius: radius, startAngle: .degrees(-90), delta: .degrees(-180))
        path.addRelativeArc(center: right, radius: radius, startAngle: .degrees(90), delta: .degrees(-90))
        let half = min(max(progress, 0), 1) / 2
        return path.trimmedPath(from: 0.5 - half, to: 0.5 + half)
    }
}

struct AddressLoadIndicator: View {
    let isLoading: Bool
    let progress: Double

    @State private var shownProgress: Double = 0
    @State private var opacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Load: Equatable {
        let isLoading: Bool
        let progress: Double
    }

    var body: some View {
        AddressLoadOutline(progress: shownProgress)
            .stroke(Color(red: 0, green: 122.0 / 255, blue: 1), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: Load(isLoading: isLoading, progress: progress)) {
                if isLoading {
                    if opacity == 0 || progress < shownProgress - 0.15 {
                        shownProgress = 0.005
                    }
                    opacity = 1
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                        shownProgress = min(1, max(0.005, progress))
                    }
                } else if opacity > 0 {
                    if progress >= 1 && !reduceMotion {
                        withAnimation(.easeOut(duration: 0.12)) { shownProgress = 1 }
                        do {
                            try await Task.sleep(nanoseconds: 120_000_000)
                        } catch {
                            return
                        }
                    }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { opacity = 0 }
                }
            }
    }
}
