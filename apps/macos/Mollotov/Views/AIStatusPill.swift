import SwiftUI

struct AIStatusPill: View {
    @ObservedObject var aiState: AIState
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .font(.system(size: 12, weight: .semibold))

                if let activeModel = aiState.activeModel {
                    if activeModel.capabilities.contains("vision") {
                        Image(systemName: "eye")
                            .font(.system(size: 11, weight: .semibold))
                    }

                    Text(shortName(for: activeModel.name))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .opacity(aiState.isAvailable ? 1 : 0.65)
        .accessibilityIdentifier("browser.ai.status-pill")
        .help(helpText)
    }

    private var helpText: String {
        if aiState.activeModel == nil {
            return "Open AI models"
        }
        return isOpen ? "Close AI panel" : "Open AI panel"
    }

    private var foregroundColor: Color {
        if aiState.activeModel != nil && isOpen {
            return .white
        }
        return .primary
    }

    private var backgroundColor: Color {
        if aiState.activeModel != nil && isOpen {
            return Color.accentColor.opacity(0.95)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        if aiState.activeModel != nil && isOpen {
            return Color.accentColor.opacity(0.6)
        }
        return Color(nsColor: .separatorColor)
    }

    private func shortName(for name: String) -> String {
        name
            .replacingOccurrences(of: " E2B", with: "")
            .replacingOccurrences(of: "Gemma 4 ", with: "Gemma 4 ")
    }
}
