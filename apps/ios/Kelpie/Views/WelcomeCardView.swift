import SwiftUI
import UIKit

private let kelpieOrange = Color(red: 244 / 255, green: 176 / 255, blue: 120 / 255)

struct WelcomeCardView: View {
    let onDismiss: () -> Void
    @AppStorage("hideWelcomeCard") private var hideWelcome = false
    @State private var dontShowAgain = false
    private let modalCardMaxWidth: CGFloat = 540

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 20) {
                appIcon
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                Text("Kelpie")
                    .font(.title.bold())

                Text("A browser built for LLMs. Fully controllable from the command line — just point your model at any task and let it work.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Divider()

                VStack(spacing: 8) {
                    Label("Getting Started", systemImage: "sparkles")
                        .font(.headline)

                    Text("Navigate to any page, then ask your LLM to describe what's on screen. Great for visual debugging, testing flows, or hands-free browsing.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Toggle("Don't show this again", isOn: $dontShowAgain)
                    .font(.subheadline)
                    .tint(kelpieOrange)

                Button(action: dismiss) {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(kelpieOrange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(28)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
            .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? modalCardMaxWidth : .infinity)
            .padding(.horizontal, 32)
        }
    }

    private func dismiss() {
        if dontShowAgain { hideWelcome = true }
        onDismiss()
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = UIImage(named: "AppIcon") {
            Image(uiImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "flame.fill")
                .font(.system(size: 40))
                .foregroundStyle(kelpieOrange)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
        }
    }
}
