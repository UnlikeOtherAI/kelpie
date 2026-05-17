import SwiftUI
import AppKit

/// Settings panel showing connection info, server status, and renderer info.
struct SettingsView: View {
    @ObservedObject var serverState: ServerState
    @ObservedObject var rendererState: RendererState
    var onNavigate: ((String) -> Void)?
    @ObservedObject private var aiState = AIState.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showHFTokenField = false
    @State private var hfTokenDraft = ""

    private var huggingFaceToken: String { aiState.huggingFaceToken }

    var body: some View {
        VStack {
            Form {
                Section("Device") {
                    row("Name", serverState.deviceInfo.name)
                    row("Model", serverState.deviceInfo.model)
                    row("ID", serverState.deviceInfo.id)
                    row("Platform", serverState.deviceInfo.platform)
                    row("Resolution", "\(serverState.deviceInfo.width) x \(serverState.deviceInfo.height)")
                }

                Section("Renderer") {
                    row("Active Engine", rendererState.activeEngine.displayName)
                    row("Available", RendererState.Engine.allCases.map(\.rawValue).joined(separator: ", "))
                }

                if aiState.isAvailable {
                    Section("AI") {
                        Picker("Active Model", selection: activeModelSelection) {
                            Text("None").tag("none")

                            if !aiState.nativeModelCards.filter(\.isDownloaded).isEmpty {
                                Text("Native").tag("native.header").disabled(true)
                                ForEach(aiState.nativeModelCards.filter(\.isDownloaded)) { card in
                                    Text(card.model.name).tag(card.id)
                                }
                            }

                            if !aiState.ollamaModels.isEmpty {
                                Text("Ollama").tag("ollama.header").disabled(true)
                                ForEach(aiState.ollamaModels) { model in
                                    Text(model.name).tag("ollama:\(model.name)")
                                }
                            }
                        }
                        .pickerStyle(.menu)

                        row("Device", aiState.deviceCapabilities.summaryLine)

                        HStack {
                            Text("Ollama")
                                .foregroundColor(.secondary)
                            Spacer()
                            TextField("http://localhost:11434", text: $aiState.ollamaEndpoint)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 210)
                            Button("Test") {
                                Task { await aiState.testOllama() }
                            }
                            .controlSize(.small)
                            Circle()
                                .fill(aiState.ollamaReachable ? Color.green : Color.secondary.opacity(0.5))
                                .frame(width: 8, height: 8)
                            Text(aiState.ollamaReachable ? "Online" : "Offline")
                                .foregroundColor(.secondary)
                        }

                        Text("Models run locally. No data leaves your device.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("HuggingFace") {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(huggingFaceToken.isEmpty ? .orange : .green)
                        Text("API Token")
                        Spacer()
                        Text(huggingFaceToken.isEmpty ? "Not set" : "Configured")
                            .foregroundColor(.secondary)
                    }

                    if showHFTokenField {
                        SecureField("hf_...", text: $hfTokenDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .accessibilityIdentifier("settings.hf-token.input")

                        HStack {
                            if !huggingFaceToken.isEmpty {
                                Button("Clear") {
                                    aiState.huggingFaceToken = ""
                                    hfTokenDraft = ""
                                    showHFTokenField = false
                                }
                                .controlSize(.small)
                            }
                            Spacer()
                            Button("Cancel") {
                                hfTokenDraft = ""
                                showHFTokenField = false
                            }
                            .controlSize(.small)
                            Button("Save") {
                                aiState.huggingFaceToken = hfTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                hfTokenDraft = ""
                                showHFTokenField = false
                            }
                            .controlSize(.small)
                            .disabled(hfTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("settings.hf-token.save")
                        }
                    } else {
                        Button("Set API Key") {
                            hfTokenDraft = huggingFaceToken
                            showHFTokenField = true
                        }
                        .controlSize(.small)
                        .accessibilityIdentifier("settings.hf-token.toggle")
                    }

                    Button("Open HuggingFace Tokens Page") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onNavigate?("https://huggingface.co/settings/tokens")
                        }
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("settings.hf-token.open-page")
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

                Section("App") {
                    row("Version", serverState.deviceInfo.version)
                    #if DEBUG
                    row("Build", "Debug")
                    #else
                    row("Build", "Release")
                    #endif
                }

                Section("Experimental") {
                    Toggle("3D DOM Inspector", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "enable3DInspector") },
                        set: { UserDefaults.standard.set($0, forKey: "enable3DInspector") }
                    ))
                    Text("Explode the page into 3D layers to debug element stacking. Restart not required.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                AppKitSettingsDoneButton(action: dismiss.callAsFunction)
                    .frame(width: 92, height: 34)
            }
            .padding()
        }
        .frame(width: 400, height: 600)
    }

    private var activeModelSelection: Binding<String> {
        Binding(
            get: {
                guard let activeModel = aiState.activeModel else { return "none" }
                if activeModel.backend == .ollama {
                    return "ollama:\(activeModel.name)"
                }
                return activeModel.id
            },
            set: { selection in
                Task {
                    switch selection {
                    case "none":
                        _ = await aiState.unloadModel()
                    case let value where value.hasPrefix("ollama:"):
                        _ = await aiState.loadOllamaModel(name: String(value.dropFirst("ollama:".count)))
                    case "native.header", "ollama.header":
                        break
                    default:
                        _ = await aiState.loadNativeModel(id: selection)
                    }
                }
            }
        )
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).textSelection(.enabled)
        }
    }
}

private struct AppKitSettingsDoneButton: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "Done", target: context.coordinator, action: #selector(Coordinator.handlePress))
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.keyEquivalent = "\r"
        button.keyEquivalentModifierMask = []
        button.focusRingType = .none
        button.setAccessibilityIdentifier("settings.done")
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.title = "Done"
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

/// Lets sheet content accept the first click after focus moves away from the browser renderer.
struct AppKitFirstMouseSheetContainer<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> FirstMouseHostingView<Content> {
        FirstMouseHostingView(rootView: content)
    }

    func updateNSView(_ nsView: FirstMouseHostingView<Content>, context: Context) {
        nsView.rootView = content
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
