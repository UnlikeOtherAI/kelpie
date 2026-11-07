import SwiftUI

struct ShellToastCardView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 120 / 255, green: 176 / 255, blue: 244 / 255))

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .padding(.horizontal, 20)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("browser.shell-toast")
    }
}
