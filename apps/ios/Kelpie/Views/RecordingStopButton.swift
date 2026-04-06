import SwiftUI

struct RecordingStopButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "stop.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.red.opacity(0.72))
                .clipShape(Circle())
        }
        .accessibilityIdentifier("browser.recording.stop")
    }
}
