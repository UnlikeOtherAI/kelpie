import SwiftUI

/// Settings panel showing connection info and server status.
struct SettingsView: View {
    @ObservedObject var serverState: ServerState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("debugOverlay") private var debugOverlay = false
    @ObservedObject private var aiState = AIState.shared
    @State private var showTokenField = false
    @State private var tokenInput = ""
    @StateObject private var openAIEndpoints = OpenAIEndpointsModel()
    @State private var openAIEditor: OpenAIEndpointsSection.EditorTarget?
    let onShowWelcome: () -> Void
    var onNavigate: ((String) -> Void)?

    var body: some View {
        NavigationView {
            List {
                Section("Device") {
                    row("Name", serverState.deviceInfo.name)
                    row("Model", serverState.deviceInfo.model)
                    row("ID", serverState.deviceInfo.id)
                    row("Platform", serverState.deviceInfo.platform)
                    row("Resolution", "\(serverState.deviceInfo.width)×\(serverState.deviceInfo.height)")
                }

                Section("Network") {
                    row("IP Address", serverState.ipAddress)
                    row("Port", String(serverState.deviceInfo.port))
                    row("HTTP Server", serverState.isServerRunning ? "Running" : "Stopped")
                    row("mDNS", serverState.isMDNSAdvertising ? "Advertising" : "Stopped")
                }

                Section("Connect") {
                    let url = "http://\(serverState.ipAddress):\(serverState.deviceInfo.port)"
                    Text(url)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.blue)
                        .textSelection(.enabled)

                    NavigationLink("Paired Clients") {
                        PairedClientsView(coordinator: serverState.pairingCoordinator)
                    }
                }

                Section("HuggingFace") {
                    HStack {
                        if aiState.huggingFaceToken.isEmpty {
                            Image(systemName: "key")
                                .foregroundColor(.orange)
                            Text("No API Key")
                                .foregroundColor(.orange)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("API Key Set")
                                .foregroundColor(.primary)
                        }
                    }

                    Button(showTokenField ? "Hide API Key Field" : "Set API Key") {
                        showTokenField.toggle()
                        if showTokenField {
                            tokenInput = ""
                        }
                    }

                    if showTokenField {
                        SecureField("HuggingFace Token", text: $tokenInput)
                            .textContentType(.password)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)

                        Button("Save") {
                            aiState.huggingFaceToken = tokenInput
                            tokenInput = ""
                            showTokenField = false
                        }
                        .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if !aiState.huggingFaceToken.isEmpty {
                        Button("Clear", role: .destructive) {
                            aiState.huggingFaceToken = ""
                            tokenInput = ""
                            showTokenField = false
                        }
                    }

                    Button("Open HuggingFace Tokens Page") {
                        dismiss()
                        onNavigate?("https://huggingface.co/settings/tokens")
                    }
                }

                LocalModelSection()
                OpenAIEndpointsSection(model: openAIEndpoints, editorTarget: $openAIEditor)

                Section("Debug") {
                    Toggle("Debug Overlay", isOn: $debugOverlay)
                }

                Section("Experimental") {
                    Toggle("3D DOM Inspector", isOn: Binding(
                        get: { FeatureFlags.is3DInspectorEnabled },
                        set: { UserDefaults.standard.set($0, forKey: "enable3DInspector") }
                    ))
                }

                Section("Help") {
                    Button("Show Welcome Screen") {
                        dismiss()
                        onShowWelcome()
                    }

                    Button("Open Kelpie Website") {
                        openHelpURL("https://unlikeotherai.github.io/kelpie")
                    }

                    Button("Open GitHub Repository") {
                        openHelpURL("https://github.com/UnlikeOtherAI/kelpie")
                    }

                    Button("Open UnlikeOtherAI") {
                        openHelpURL("https://unlikeotherai.com")
                    }
                }

                Section("App") {
                    row("Version", serverState.deviceInfo.version)
                    #if DEBUG
                    row("Build", "Debug")
                    row("AppReveal", "Active")
                    #else
                    row("Build", "Release")
                    #endif
                }
            }
            .sheet(item: $openAIEditor) { target in
                OpenAIEndpointEditor(model: openAIEndpoints, initialEndpointId: target.endpointId)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).textSelection(.enabled)
        }
    }

    private func openHelpURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        openURL(url)
    }
}

struct AIStatusView: View {
    @ObservedObject private var state = AIState.shared
    @Environment(\.dismiss) private var dismiss
    @StateObject private var openAIEndpoints = OpenAIEndpointsModel()
    @State private var openAIEditor: OpenAIEndpointsSection.EditorTarget?

    private var ready: Bool {
        state.backend == "openai" ? openAIEndpoints.rows.contains { $0.isActive && $0.health == .ready } : state.isLoaded
    }

    var body: some View {
        NavigationView {
            List {
                Section("Status") {
                    row("Backend", backendLabel)
                    row("Availability", ready ? "Available" : "Unavailable")
                    row("Loaded", state.isLoaded ? "Yes" : "No")
                }

                Section("Model") {
                    row("Active Model", activeModelLabel)
                    row("Capabilities", capabilitiesLabel)
                }

                if state.backend == "ollama" {
                    Section("Ollama") {
                        row("Endpoint", state.ollamaEndpoint)
                    }
                }

                if !ready {
                    Text("Import a GGUF for on-device inference, or select a reachable LAN endpoint for a larger model.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                LocalModelSection()
                OpenAIEndpointsSection(model: openAIEndpoints, editorTarget: $openAIEditor)
            }
            .sheet(item: $openAIEditor) { target in
                OpenAIEndpointEditor(model: openAIEndpoints, initialEndpointId: target.endpointId)
            }
            .navigationTitle("Local AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var backendLabel: String {
        switch state.backend {
        case "ollama":
            return "Ollama"
        case "openai":
            return "OpenAI-compatible endpoint"
        case "platform":
            return "Platform"
        case "native":
            return "On-device GGUF"
        default:
            return state.backend
        }
    }

    private var activeModelLabel: String {
        if state.backend == "native", let model = state.activeModel { return URL(fileURLWithPath: model).lastPathComponent }
        if state.backend == "platform" {
            return state.isAvailable ? "Platform AI" : "None"
        }
        return state.activeModel ?? "None"
    }

    private var capabilitiesLabel: String {
        state.capabilities.isEmpty ? "None" : state.capabilities.joined(separator: ", ")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).textSelection(.enabled)
        }
    }
}
