import SwiftUI

/// Small text button for the AI panel. The visible label is SwiftUI; the hit
/// target is an AppKit `NSButton` so WebView focus cannot swallow clicks.
struct AIPanelActionButton: View {
    let title: String
    let accessibilityID: String
    var prominent = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : (isEnabled ? Color.primary : Color.secondary))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(prominent ? Color.accentColor.opacity(isEnabled ? 1 : 0.4) : Color.secondary.opacity(0.15))
            )
            .overlay(
                AppKitInvisibleButton(
                    accessibilityID: accessibilityID,
                    accessibilityLabel: title,
                    isEnabled: isEnabled,
                    action: action
                )
            )
    }
}

/// "OpenAI-compatible" section of the AI panel's Models tab.
struct AIEndpointsSection: View {
    @ObservedObject var state: AIEndpointState
    @State private var editing: AIEndpointForm?

    static let loopbackExplanation =
        "localhost and 127.0.0.1 mean this Mac — the computer running Kelpie and sending inference requests. " +
        "Kelpie only connects to addresses you add here; it never scans your network."

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.loopbackExplanation)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(state.cards) { card in
                AIEndpointCardView(card: card, state: state, isWorking: state.working.contains(card.id)) {
                    editing = state.form(for: card)
                }
            }

            if let form = editing {
                AIEndpointFormView(
                    form: form,
                    discoveredModels: state.cards.first { $0.id == form.id }?.models ?? [],
                    error: state.formError,
                    onSave: { updated in
                        Task {
                            if await state.save(updated) { editing = nil }
                        }
                    },
                    onCancel: {
                        state.formError = nil
                        editing = nil
                    }
                )
            } else {
                AIPanelActionButton(title: "Add endpoint", accessibilityID: "browser.ai.openai.add") {
                    editing = state.form(for: nil)
                }
            }
        }
    }
}

private struct AIEndpointCardView: View {
    let card: AIEndpointCard
    @ObservedObject var state: AIEndpointState
    let isWorking: Bool
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(healthColor)
                    .frame(width: 8, height: 8)
                Text(card.name)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if card.isActive {
                    Text("Active")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
            Text(card.baseURL + (card.loopback ? "  · this Mac" : "") + (card.hasApiKey ? "  · key saved" : ""))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Model: \(card.model ?? "none selected")")
                .font(.system(size: 11))
            Text("Health: \(card.healthState.replacingOccurrences(of: "_", with: " ")) — \(card.healthMessage)")
                .font(.system(size: 11))
                .foregroundStyle(card.online ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            Text("Context: \(card.contextWindow) · Vision: \(card.vision) · Tools: \(card.toolCalling)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let note = state.notes[card.id] {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("browser.ai.openai.\(card.id).note")
            }
            actions
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var actions: some View {
        HStack(spacing: 6) {
            AIPanelActionButton(
                title: card.isActive ? "In use" : "Use",
                accessibilityID: "browser.ai.openai.\(card.id).use",
                prominent: true,
                isEnabled: !isWorking && !card.isActive && card.model != nil
            ) {
                Task { await state.use(card.id, model: card.model) }
            }
            AIPanelActionButton(title: isWorking ? "Working…" : "Test", accessibilityID: "browser.ai.openai.\(card.id).test", isEnabled: !isWorking) {
                Task { await state.test(card.id) }
            }
            AIPanelActionButton(title: "Models", accessibilityID: "browser.ai.openai.\(card.id).models", isEnabled: !isWorking) {
                Task { await state.refreshModels(card.id) }
            }
            AIPanelActionButton(title: "Edit", accessibilityID: "browser.ai.openai.\(card.id).edit", isEnabled: !isWorking, action: onEdit)
            AIPanelActionButton(title: "Remove", accessibilityID: "browser.ai.openai.\(card.id).remove", isEnabled: !isWorking) {
                Task { await state.remove(card.id) }
            }
        }
    }

    private var healthColor: Color {
        switch card.healthState {
        case "ready": return .green
        case "busy": return .blue
        case "loading", "no_model", "model_missing": return .yellow
        case "unreachable", "auth_failed": return .red
        default: return .secondary
        }
    }
}

private struct AIEndpointFormView: View {
    @State var form: AIEndpointForm
    let discoveredModels: [String]
    let error: String?
    let onSave: (AIEndpointForm) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(form.id == nil ? "Add endpoint" : "Edit endpoint")
                .font(.system(size: 12, weight: .semibold))
            field("Name", text: $form.name, id: "name", placeholder: "Strata")
            field("Base URL", text: $form.baseURL, id: "url", placeholder: "http://127.0.0.1:8080/v1")
            Text("Include the base path, e.g. /v1 or /openai/v1. localhost is this Mac.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("API key (optional)").font(.system(size: 11)).foregroundStyle(.secondary)
                SecureField(form.hasStoredKey && !form.clearKey ? "Saved — leave empty to keep" : "Not required for local servers", text: $form.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .accessibilityIdentifier("browser.ai.openai.form.key")
                if form.hasStoredKey {
                    AIPanelActionButton(title: form.clearKey ? "Key will be removed" : "Remove saved key", accessibilityID: "browser.ai.openai.form.clear-key") {
                        form.clearKey.toggle()
                    }
                }
            }
            field("Model ID", text: $form.model, id: "model", placeholder: "Use Models to discover, or type an ID")
            if !discoveredModels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(discoveredModels.prefix(4), id: \.self) { model in
                        AIPanelActionButton(title: model, accessibilityID: "browser.ai.openai.form.model.\(model)") {
                            form.model = model
                        }
                    }
                }
            }
            field("Context window override", text: $form.contextWindow, id: "context", placeholder: "Leave empty to use the server's value")
            tristate("Vision input", value: $form.vision, id: "vision")
            tristate("Tool calling", value: $form.toolCalling, id: "tools")
            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("browser.ai.openai.form.error")
            }
            HStack(spacing: 6) {
                AIPanelActionButton(title: "Save", accessibilityID: "browser.ai.openai.form.save", prominent: true) { onSave(form) }
                AIPanelActionButton(title: "Cancel", accessibilityID: "browser.ai.openai.form.cancel", action: onCancel)
            }
            Text("Saving does not connect. Use Models or Test to contact the server.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.4))
        )
    }

    private func field(_ label: String, text: Binding<String>, id: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .accessibilityIdentifier("browser.ai.openai.form.\(id)")
        }
    }

    private func tristate(_ label: String, value: Binding<String>, id: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            ForEach(["unknown", "yes", "no"], id: \.self) { option in
                AIPanelActionButton(
                    title: option.capitalized,
                    accessibilityID: "browser.ai.openai.form.\(id).\(option)",
                    prominent: value.wrappedValue == option
                ) {
                    value.wrappedValue = option
                }
            }
        }
    }
}
