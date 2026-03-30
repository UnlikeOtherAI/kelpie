import SwiftUI

/// App icon background color — warm peach/orange.
private let mollotovOrange = Color(red: 244/255, green: 176/255, blue: 120/255)

/// Floating action button that expands into a fan menu.
/// - 44pt circular FAB with flame icon, vertically centered on the right edge.
/// - Horizontally draggable between left and right sides of the screen.
/// - Opens a subtle blur overlay + fan-out menu items.
struct FloatingMenuView: View {
    let onReload: () -> Void
    let onSafariAuth: () -> Void
    let onSettings: () -> Void

    @State private var isOpen = false
    /// Horizontal side: 1 = right (default), -1 = left.
    @State private var side: CGFloat = 1
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    private let fabSize: CGFloat = 44
    private let menuItemSize: CGFloat = 44
    private let spreadRadius: CGFloat = 70
    private let edgePadding: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let midY = geo.size.height / 2
            let rightX = geo.size.width - edgePadding - fabSize / 2
            let leftX = edgePadding + fabSize / 2
            let baseX = side > 0 ? rightX : leftX
            let clampedX = min(max(baseX + dragOffset, leftX), rightX)

            ZStack {
                // Blur + dim overlay when menu is open
                if isOpen {
                    Color.clear
                        .background(.ultraThinMaterial)
                        .opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35)) { isOpen = false }
                        }
                }

                // Menu items + FAB
                ZStack {
                    // Fan-out menu items — spread away from the current edge
                    let fanDirection: CGFloat = side > 0 ? -1 : 1
                    menuItem(icon: "arrow.clockwise", label: "Reload",
                             angle: fanAngle(base: 180, direction: fanDirection, index: 0),
                             action: onReload)
                    menuItem(icon: "safari", label: "Safari Login",
                             angle: fanAngle(base: 180, direction: fanDirection, index: 1),
                             action: onSafariAuth)
                    menuItem(icon: "gear", label: "Settings",
                             angle: fanAngle(base: 180, direction: fanDirection, index: 2),
                             action: onSettings)

                    // Main FAB — flame icon
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            isOpen.toggle()
                        }
                    } label: {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: fabSize, height: fabSize)
                            .background(mollotovOrange)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDragging = true
                                dragOffset = value.translation.width
                            }
                            .onEnded { value in
                                isDragging = false
                                let finalX = clampedX
                                let mid = geo.size.width / 2
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    side = finalX < mid ? -1 : 1
                                    dragOffset = 0
                                }
                            }
                    )
                }
                .position(x: clampedX, y: midY)
            }
        }
    }

    /// Compute fan angle: when on right side, items fan upward-left; on left side, upward-right.
    private func fanAngle(base: Double, direction: CGFloat, index: Int) -> Angle {
        let step: Double = 35
        if direction < 0 {
            // Right side: fan left and up (180°, 215°, 250°)
            return .degrees(base + step * Double(index))
        } else {
            // Left side: fan right and up (0°, -35°, -70° → 360°, 325°, 290°)
            return .degrees(360 - step * Double(index))
        }
    }

    @ViewBuilder
    private func menuItem(icon: String, label: String, angle: Angle, action: @escaping () -> Void) -> some View {
        let dx: CGFloat = isOpen ? CGFloat(cos(angle.radians)) * spreadRadius : 0
        let dy: CGFloat = isOpen ? CGFloat(sin(angle.radians)) * spreadRadius : 0
        let offset = CGSize(width: dx, height: dy)

        Button {
            action()
            withAnimation(.spring(response: 0.35)) { isOpen = false }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: menuItemSize, height: menuItemSize)
                    .background(mollotovOrange)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                if isOpen {
                    Text(label)
                        .font(.caption2)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                }
            }
        }
        .offset(offset)
        .opacity(isOpen ? 1 : 0)
        .scaleEffect(isOpen ? 1 : 0.3)
    }
}
