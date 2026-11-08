import Combine
import SwiftUI

/// Settings section listing the person's OpenAI-compatible endpoints.
/// Adding or editing opens `OpenAIEndpointEditor`; nothing here connects
/// until the person taps Refresh Models, Test or Use.
///
/// The editor sheet is presented by `SettingsView` (via `editorTarget`), not
/// from inside the List: a sheet attached to List content inside the
/// Settings sheet replaces the Settings sheet instead of stacking on it.
struct OpenAIEndpointsSection: View {
    enum EditorTarget: Identifiable {
        case new
        case existing(String)

        var id: String {
            switch self {
            case .new: return "new"
            case .existing(let id): return id
            }
        }
    }

    @ObservedObject var model: OpenAIEndpointsModel
    @Binding var editorTarget: EditorTarget?
    private let staleTicker = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    static var loopbackMeans: String { AIHandler.openAIHost.loopbackMeans }

    var body: some View {
        Section {
            Text(Self.loopbackMeans)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.ai.openai.loopbackNote")

            ForEach(model.rows) { row in
                Button {
                    editorTarget = .existing(row.id)
                } label: {
                    OpenAIEndpointRowView(row: row)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.ai.openai.row.\(row.config.name)")
            }

            Button {
                editorTarget = .new
            } label: {
                Label("Add Endpoint", systemImage: "plus")
            }
            .accessibilityIdentifier("settings.ai.openai.add")
        } header: {
            Text("OpenAI-compatible endpoints")
        } footer: {
            Text("Kelpie only connects to addresses you save here, and only when you refresh, test or use one. "
                 + "If the selected endpoint fails, requests fail — Kelpie never switches to another backend.")
        }
        .task { await model.reload() }
        .onReceive(staleTicker) { _ in model.reloadSoon() }
    }
}

extension OpenAIEndpointsSection.EditorTarget {
    var endpointId: String? {
        if case .existing(let id) = self { return id }
        return nil
    }
}

struct OpenAIEndpointRowView: View {
    let row: OpenAIEndpointsModel.Row

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.config.name)
                        .font(.body.weight(.medium))
                    if row.isActive {
                        Text("In use")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.accentColor)
                            .accessibilityIdentifier("settings.ai.openai.row.active")
                    }
                }
                Text(row.config.baseURL)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.config.model ?? "No model selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            OpenAIHealthBadge(state: row.health)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// Health state as text on a colour-coded capsule.
struct OpenAIHealthBadge: View {
    let state: OpenAIEndpointHealth.State

    var body: some View {
        Text(OpenAIHealthLabel.text(for: state))
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .accessibilityLabel("Health: \(OpenAIHealthLabel.text(for: state))")
            .accessibilityIdentifier("settings.ai.openai.health")
    }

    private var color: Color {
        switch state {
        case .ready: return .green
        case .busy, .loading, .noModel, .modelMissing: return .orange
        case .unreachable, .authFailed: return .red
        case .unknown: return .gray
        }
    }
}
