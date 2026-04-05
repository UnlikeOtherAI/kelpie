import SwiftUI

/// Settings panel showing connection info and server status.
struct SettingsView: View {
    @ObservedObject var serverState: ServerState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("debugOverlay") private var debugOverlay = false
    let onShowWelcome: () -> Void

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
                }

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

    var body: some View {
        NavigationView {
            List {
                Section("Status") {
                    row("Backend", backendLabel)
                    row("Availability", state.isAvailable ? "Available" : "Unavailable")
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

                if !state.isAvailable {
                    Text("Platform AI is not currently available on this device. You can still load an Ollama model over the API.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
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
        case "platform":
            return "Platform"
        default:
            return state.backend
        }
    }

    private var activeModelLabel: String {
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
