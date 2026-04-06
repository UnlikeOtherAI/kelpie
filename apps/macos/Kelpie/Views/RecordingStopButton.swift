import SwiftUI

struct RecordingStopButton: View {
    let action: () -> Void

    var body: some View {
        AppKitToolbarButton(
            systemName: "stop.fill",
            accessibilityID: "browser.recording.stop",
            accessibilityLabel: "Stop script playback",
            action: action
        )
        .frame(width: 40, height: 34)
    }
}
