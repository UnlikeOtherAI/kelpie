import SwiftUI

struct Inspector3DControlsView: View {
    let mode: String
    let onSelectMode: (String) -> Void
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void
    let onReset: () -> Void
    let onExit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Picker("3D mode", selection: Binding(
                get: { mode },
                set: onSelectMode
            )) {
                Image(systemName: "hand.draw")
                    .tag("rotate")
                Image(systemName: "arrow.up.and.down")
                    .tag("scroll")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 120)
            .accessibilityIdentifier("browser.snapshot3d.mode")

            controlButton(
                systemName: "minus.magnifyingglass",
                accessibilityID: "browser.snapshot3d.zoom-out",
                accessibilityLabel: "Zoom out 3D view",
                action: onZoomOut
            )

            controlButton(
                systemName: "plus.magnifyingglass",
                accessibilityID: "browser.snapshot3d.zoom-in",
                accessibilityLabel: "Zoom in 3D view",
                action: onZoomIn
            )

            controlButton(
                systemName: "arrow.counterclockwise",
                accessibilityID: "browser.snapshot3d.reset",
                accessibilityLabel: "Reset 3D view",
                action: onReset
            )

            controlButton(
                systemName: "xmark",
                accessibilityID: "browser.snapshot3d.exit",
                accessibilityLabel: "Exit 3D view",
                action: onExit
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .padding(.horizontal, 12)
    }

    private func controlButton(
        systemName: String,
        accessibilityID: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Color(.systemGray6))
                .clipShape(Circle())
        }
        .accessibilityIdentifier(accessibilityID)
        .accessibilityLabel(accessibilityLabel)
    }
}
