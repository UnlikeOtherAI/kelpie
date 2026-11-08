import SwiftUI

/// Sync and Touchpad buttons shown on the opposite edge from the FAB
/// when an external display is connected.
struct TVControlsView: View {
    let fabSide: CGFloat // 1 = right, -1 = left
    @Binding var syncEnabled: Bool
    let onTouchpad: () -> Void

    private let buttonSize: CGFloat = 40
    private let edgePadding: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            // Opposite side from FAB
            let x = fabSide > 0
                ? edgePadding + buttonSize / 2
                : geo.size.width - edgePadding - buttonSize / 2
            let midY = geo.size.height / 2

            VStack(spacing: 12) {
                // Sync button — green when active
                Button { syncEnabled.toggle() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: buttonSize, height: buttonSize)
                        .background(syncEnabled ? Color.green : Color.gray.opacity(0.5))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                }

                // Touchpad button
                Button(action: onTouchpad) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: buttonSize, height: buttonSize)
                        .background(Color.gray.opacity(0.5))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                }
            }
            .position(x: x, y: midY)
        }
    }
}
