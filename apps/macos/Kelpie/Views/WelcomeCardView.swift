import SwiftUI
import AppKit

private let kelpieOrange = Color(red: 244 / 255, green: 176 / 255, blue: 120 / 255)

struct WelcomeCardView: View {
    let onDismiss: () -> Void
    @AppStorage("hideWelcomeCard") private var hideWelcome = false
    @State private var dontShowAgain = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            VStack(spacing: 20) {
                appIcon
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                Text("Kelpie")
                    .font(.title.bold())

                Text("A browser built for LLMs. Fully controllable from the command line -- just point your model at any task and let it work.")
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

                AppKitCheckboxRow(
                    title: "Don't show this again",
                    isOn: $dontShowAgain
                )
                .frame(height: 22)

                AppKitPrimaryButton(title: "Get Started", action: dismiss)
                    .frame(height: 48)
            }
            .padding(28)
            .frame(width: 420)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
            .padding(.horizontal, 32)
        }
    }

    private func dismiss() {
        if dontShowAgain {
            hideWelcome = true
        }
        onDismiss()
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = NSImage(named: "WelcomeIcon") {
            Image(nsImage: icon)
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

private struct AppKitCheckboxRow: NSViewRepresentable {
    let title: String
    @Binding var isOn: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isOn: $isOn)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: context.coordinator, action: #selector(Coordinator.handleToggle(_:)))
        button.font = .systemFont(ofSize: 13)
        button.setButtonType(.switch)
        button.focusRingType = .none
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.title = title
        nsView.state = isOn ? .on : .off
    }

    final class Coordinator: NSObject {
        @Binding private var isOn: Bool

        init(isOn: Binding<Bool>) {
            _isOn = isOn
        }

        @objc
        func handleToggle(_ sender: NSButton) {
            isOn = sender.state == .on
        }
    }
}

private struct AppKitPrimaryButton: NSViewRepresentable {
    let title: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.handlePress))
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 12
        button.layer?.backgroundColor = NSColor(
            red: 244 / 255,
            green: 176 / 255,
            blue: 120 / 255,
            alpha: 1
        ).cgColor
        button.contentTintColor = .white
        button.font = .systemFont(ofSize: 15, weight: .semibold)
        button.focusRingType = .none
        button.setAccessibilityIdentifier("welcome-card.get-started")
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.title = title
    }

    final class Coordinator: NSObject {
        let action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc
        func handlePress() {
            action()
        }
    }
}
