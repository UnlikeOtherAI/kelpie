import SwiftUI

/// URL bar with text input and navigation buttons. Pill-shaped URL field.
struct URLBarView: View {
    @ObservedObject var browserState: BrowserState
    let onNavigate: (String) -> Void
    let onBack: () -> Void
    let onForward: () -> Void
    let showAI: Bool
    let onAI: () -> Void
    let onSnapshot3D: () -> Void

    @State private var urlText: String = ""
    @FocusState private var isURLFieldFocused: Bool
    private let navigationButtonSize: CGFloat = 44

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: navigationButtonSize, height: navigationButtonSize)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .accessibilityIdentifier("browser.nav.back")
            .disabled(!browserState.canGoBack)

            Button(action: onForward) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: navigationButtonSize, height: navigationButtonSize)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .accessibilityIdentifier("browser.nav.forward")
            .disabled(!browserState.canGoForward)

            addressField

            if showAI {
                Button(action: onAI) {
                    Image(systemName: "brain")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: navigationButtonSize, height: navigationButtonSize)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
                .accessibilityIdentifier("browser.ai.button")
            }

            Button(action: onSnapshot3D) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: navigationButtonSize, height: navigationButtonSize)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .accessibilityIdentifier("browser.snapshot-3d.button")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onAppear { urlText = browserState.currentURL }
        .onChange(of: browserState.currentURL) { newURL in
            guard !isURLFieldFocused else { return }
            urlText = newURL
        }
    }

    private var addressField: some View {
        ZStack(alignment: .leading) {
            if let suffix = inlineCompletionSuffix {
                HStack(spacing: 0) {
                    Text(verbatim: urlText)
                        .hidden()
                    Text(verbatim: suffix)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .allowsHitTesting(false)
            }

            TextField("URL", text: $urlText)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .keyboardType(.URL)
                .focused($isURLFieldFocused)
                .accessibilityIdentifier("browser.url.field")
                .onSubmit { navigate() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .clipShape(Capsule())
    }

    private func navigate() {
        guard let url = AddressInput.resolve(resolvedNavigationText()) else { return }
        onNavigate(url)
    }

    private var inlineCompletionSuffix: String? {
        let trimmedInput = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isURLFieldFocused,
              let display = inlineCompletionDisplay(for: trimmedInput),
              display.count > trimmedInput.count
        else {
            return nil
        }
        return String(display.dropFirst(trimmedInput.count))
    }

    private func resolvedNavigationText() -> String {
        let trimmedInput = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return trimmedInput }
        return HistoryStore.shared.bestURLCompletion(for: trimmedInput) ?? trimmedInput
    }

    private func inlineCompletionDisplay(for input: String) -> String? {
        guard !input.isEmpty,
              let fullCompletion = HistoryStore.shared.bestURLCompletion(for: input)
        else {
            return nil
        }

        return completionDisplayCandidates(for: fullCompletion, input: input)
            .first { candidate in
                candidate.count > input.count &&
                    candidate.lowercased().hasPrefix(input.lowercased())
            }
    }

    private func completionDisplayCandidates(for fullCompletion: String, input: String) -> [String] {
        if startsWithScheme(input) {
            return [fullCompletion]
        }

        let withoutScheme = stripScheme(from: fullCompletion)
        let withoutWww = stripLeadingWww(from: withoutScheme)
        return [withoutWww, withoutScheme, fullCompletion].reduce(into: [String]()) { result, candidate in
            guard !result.contains(candidate) else { return }
            result.append(candidate)
        }
    }

    private func startsWithScheme(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return lowered.hasPrefix("http://") || lowered.hasPrefix("https://")
    }

    private func stripScheme(from value: String) -> String {
        guard let range = value.range(of: "://") else { return value }
        return String(value[range.upperBound...])
    }

    private func stripLeadingWww(from value: String) -> String {
        value.lowercased().hasPrefix("www.") ? String(value.dropFirst(4)) : value
    }
}
