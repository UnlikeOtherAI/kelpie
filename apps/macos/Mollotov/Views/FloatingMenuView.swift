import SwiftUI
import AppKit

/// App icon background color — warm peach/orange.
private let mollotovOrange = Color(red: 244/255, green: 176/255, blue: 120/255)
/// Richer menu item color — more red/saturated for contrast against the FAB.
private let menuItemOrange = Color(red: 240/255, green: 148/255, blue: 90/255)

/// AppKit blur that works over NSView content (SwiftUI materials cannot blur NSView).
private struct NativeBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Floating action button that expands into a fan menu.
/// Ported from the iOS FloatingMenuView — same layout/behavior, adapted for AppKit.
struct FloatingMenuView: View {
    let onReload: () -> Void
    let onSafariAuth: () -> Void
    let onSettings: () -> Void
    let onBookmarks: () -> Void
    let onHistory: () -> Void
    let onNetworkInspector: () -> Void

    @State private var isOpen = false
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
            let fanDirection: CGFloat = side > 0 ? -1 : 1

            ZStack {
                // Blur overlay when menu is open
                if isOpen {
                    NativeBlur()
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35)) { isOpen = false }
                        }
                }

                // Menu items — each positioned independently for correct hit testing
                menuItemView(icon: "arrow.clockwise", index: 0, fanDirection: fanDirection,
                             action: onReload, fabX: clampedX, fabY: midY, geo: geo)
                menuItemView(icon: "safari", index: 1, fanDirection: fanDirection,
                             action: onSafariAuth, fabX: clampedX, fabY: midY, geo: geo)
                menuItemView(icon: "bookmark.fill", index: 2, fanDirection: fanDirection,
                             action: onBookmarks, fabX: clampedX, fabY: midY, geo: geo)
                menuItemView(icon: "clock.arrow.circlepath", index: 3, fanDirection: fanDirection,
                             action: onHistory, fabX: clampedX, fabY: midY, geo: geo)
                menuItemView(icon: "antenna.radiowaves.left.and.right", index: 4, fanDirection: fanDirection,
                             action: onNetworkInspector, fabX: clampedX, fabY: midY, geo: geo)
                menuItemView(icon: "gear", index: 5, fanDirection: fanDirection,
                             action: onSettings, fabX: clampedX, fabY: midY, geo: geo)

                // Main FAB — flame icon
                Image(systemName: "flame.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: fabSize, height: fabSize)
                    .background(mollotovOrange)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .opacity(isOpen ? 0.8 : 1.0)
                    .contentShape(Circle())
                    .position(x: clampedX, y: midY)
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
        }
    }

    /// Distribute 6 items in a semicircle centered on the axis away from the docked edge.
    private func fanAngle(direction: CGFloat, index: Int) -> Angle {
        let step: Double = 30
        let halfArc: Double = step * 2.5
        let center: Double = direction < 0 ? 180 : 0
        return .degrees(center - halfArc + step * Double(index))
    }

    @ViewBuilder
    private func menuItemView(icon: String, index: Int, fanDirection: CGFloat,
                              action: @escaping () -> Void,
                              fabX: CGFloat, fabY: CGFloat, geo: GeometryProxy) -> some View {
        let angle = fanAngle(direction: fanDirection, index: index)
        let rawDx: CGFloat = isOpen ? CGFloat(cos(angle.radians)) * spreadRadius : 0
        let rawDy: CGFloat = isOpen ? CGFloat(sin(angle.radians)) * spreadRadius : 0

        let margin = menuItemSize / 2 + edgePadding
        let dx = min(max(rawDx, margin - fabX), geo.size.width - margin - fabX)
        let dy = min(max(rawDy, margin - fabY), geo.size.height - margin - fabY)

        Button {
            action()
            withAnimation(.spring(response: 0.35)) { isOpen = false }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(width: menuItemSize, height: menuItemSize)
                .background(menuItemOrange)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .position(x: fabX + dx, y: fabY + dy)
        .opacity(isOpen ? 1 : 0)
        .scaleEffect(isOpen ? 1 : 0.3)
        .allowsHitTesting(isOpen)
    }
}
