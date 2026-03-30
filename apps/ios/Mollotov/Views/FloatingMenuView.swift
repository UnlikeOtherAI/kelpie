import SwiftUI
import UIKit

/// App icon background color — warm peach/orange.
private let mollotovOrange = Color(red: 244/255, green: 176/255, blue: 120/255)

/// UIKit blur that works over WKWebView content (SwiftUI materials cannot blur UIKit views).
private struct NativeBlur: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemThinMaterial

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

/// Floating action button that expands into a fan menu.
/// - 44pt circular FAB with flame icon, vertically centered on the right edge.
/// - Horizontally draggable between left and right sides of the screen.
/// - Opens a blur overlay + fan-out menu items (no labels, wider spread).
/// - Menu items are clamped to stay within screen bounds.
struct FloatingMenuView: View {
    let onReload: () -> Void
    let onSafariAuth: () -> Void
    let onSettings: () -> Void
    let onBookmarks: () -> Void
    let onHistory: () -> Void
    let onNetworkInspector: () -> Void

    @State private var isOpen = false
    /// Horizontal side: 1 = right (default), -1 = left.
    @State private var side: CGFloat = 1
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    private let fabSize: CGFloat = 44
    private let menuItemSize: CGFloat = 44
    private let spreadRadius: CGFloat = 120
    private let edgePadding: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let midY = geo.size.height / 2
            let rightX = geo.size.width - edgePadding - fabSize / 2
            let leftX = edgePadding + fabSize / 2
            let baseX = side > 0 ? rightX : leftX
            let clampedX = min(max(baseX + dragOffset, leftX), rightX)

            ZStack {
                // Blur overlay when menu is open — uses UIKit blur to work over WKWebView
                if isOpen {
                    NativeBlur(style: .systemThinMaterial)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35)) { isOpen = false }
                        }
                }

                // Menu items + FAB
                ZStack {
                    let fanDirection: CGFloat = side > 0 ? -1 : 1
                    menuItem(icon: "arrow.clockwise",
                             angle: fanAngle(direction: fanDirection, index: 0),
                             action: onReload,
                             fabX: clampedX, fabY: midY, geo: geo)
                    menuItem(icon: "safari",
                             angle: fanAngle(direction: fanDirection, index: 1),
                             action: onSafariAuth,
                             fabX: clampedX, fabY: midY, geo: geo)
                    menuItem(icon: "bookmark.fill",
                             angle: fanAngle(direction: fanDirection, index: 2),
                             action: onBookmarks,
                             fabX: clampedX, fabY: midY, geo: geo)
                    menuItem(icon: "clock.arrow.circlepath",
                             angle: fanAngle(direction: fanDirection, index: 3),
                             action: onHistory,
                             fabX: clampedX, fabY: midY, geo: geo)
                    menuItem(icon: "antenna.radiowaves.left.and.right",
                             angle: fanAngle(direction: fanDirection, index: 4),
                             action: onNetworkInspector,
                             fabX: clampedX, fabY: midY, geo: geo)
                    menuItem(icon: "gear",
                             angle: fanAngle(direction: fanDirection, index: 5),
                             action: onSettings,
                             fabX: clampedX, fabY: midY, geo: geo)

                    // Main FAB — flame icon, handles both tap and drag via single gesture
                    Image(systemName: "flame.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: fabSize, height: fabSize)
                        .background(mollotovOrange)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                        .contentShape(Circle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let distance = abs(value.translation.width)
                                    if distance > 10 {
                                        isDragging = true
                                        dragOffset = value.translation.width
                                    }
                                }
                                .onEnded { _ in
                                    if isDragging {
                                        let finalX = min(max(baseX + dragOffset, leftX), rightX)
                                        let mid = geo.size.width / 2
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            side = finalX < mid ? -1 : 1
                                            dragOffset = 0
                                        }
                                        isDragging = false
                                    } else {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                            isOpen.toggle()
                                        }
                                    }
                                }
                        )
                }
                .position(x: clampedX, y: midY)
            }
        }
    }

    /// Compute fan angle for 6 items spread in a semicircle away from the current edge.
    private func fanAngle(direction: CGFloat, index: Int) -> Angle {
        let step: Double = 30
        if direction < 0 {
            // Right side: fan left and up (150deg -> 300deg)
            return .degrees(150 + step * Double(index))
        } else {
            // Left side: fan right and up (30deg -> 390deg, 360deg, 330deg...)
            return .degrees(390 - step * Double(index))
        }
    }

    @ViewBuilder
    private func menuItem(icon: String, angle: Angle, action: @escaping () -> Void,
                          fabX: CGFloat, fabY: CGFloat, geo: GeometryProxy) -> some View {
        let rawDx: CGFloat = isOpen ? CGFloat(cos(angle.radians)) * spreadRadius : 0
        let rawDy: CGFloat = isOpen ? CGFloat(sin(angle.radians)) * spreadRadius : 0

        // Clamp offsets so items never leave the screen
        let margin = menuItemSize / 2 + edgePadding
        let minDx = margin - fabX
        let maxDx = geo.size.width - margin - fabX
        let minDy = margin - fabY
        let maxDy = geo.size.height - margin - fabY
        let dx = min(max(rawDx, minDx), maxDx)
        let dy = min(max(rawDy, minDy), maxDy)

        Button {
            action()
            withAnimation(.spring(response: 0.35)) { isOpen = false }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(width: menuItemSize, height: menuItemSize)
                .background(mollotovOrange)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        }
        .offset(CGSize(width: dx, height: dy))
        .opacity(isOpen ? 1 : 0)
        .scaleEffect(isOpen ? 1 : 0.3)
    }
}
