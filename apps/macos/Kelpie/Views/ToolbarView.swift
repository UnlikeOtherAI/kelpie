import SwiftUI

/// Native toolbar content for renderer switching and settings access.
struct ToolbarView: View {
    @ObservedObject var rendererState: RendererState
    let onSwitchRenderer: (RendererState.Engine) -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(
                get: { rendererState.activeEngine },
                set: { onSwitchRenderer($0) }
            )) {
                Text("Safari").tag(RendererState.Engine.webkit)
                Text("Chrome").tag(RendererState.Engine.chromium)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .disabled(rendererState.isSwitching)

            Button(action: onSettings) {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
            .disabled(rendererState.isSwitching)
        }
    }
}
