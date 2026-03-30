import SwiftUI

/// App icon background color — warm peach/orange.
private let mollotovOrange = Color(red: 244/255, green: 176/255, blue: 120/255)

/// Floating action button that expands into a Pinterest-style fan menu.
struct FloatingMenuView: View {
    let onReload: () -> Void
    let onSafariAuth: () -> Void
    let onSettings: () -> Void

    @State private var isOpen = false

    private let buttonSize: CGFloat = 36
    private let menuItemSize: CGFloat = 44
    private let spreadRadius: CGFloat = 70

    var body: some View {
        ZStack {
            // Dim overlay when menu is open
            if isOpen {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.spring(response: 0.35)) { isOpen = false } }
            }

            // Menu items + FAB positioned at bottom-right
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack(alignment: .bottomTrailing) {
                        // Fan-out menu items — spread upward and to the left
                        menuItem(icon: "arrow.clockwise", label: "Reload", angle: .degrees(180), action: onReload)
                        menuItem(icon: "safari", label: "Safari Login", angle: .degrees(215), action: onSafariAuth)
                        menuItem(icon: "gear", label: "Settings", angle: .degrees(250), action: onSettings)

                        // Main FAB
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                isOpen.toggle()
                            }
                        } label: {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: buttonSize, height: buttonSize)
                                .background(mollotovOrange)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                                .rotationEffect(isOpen ? .degrees(45) : .degrees(0))
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 24)
                }
            }
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
