import SwiftUI

/// Add/edit sheet for one OpenAI-compatible endpoint. Saving stores the
/// configuration only; Refresh Models, Test and Use are the actions that
/// connect, and they act on the saved settings.
struct OpenAIEndpointEditor: View {
    enum TriState: String, CaseIterable, Identifiable {
        case unknown = "Unknown"
        case supported = "Yes"
        case unsupported = "No"

        var id: String { rawValue }

        init(_ value: Bool?) {
            switch value {
            case .some(true): self = .supported
            case .some(false): self = .unsupported
            case .none: self = .unknown
            }
        }

        var bool: Bool? {
            switch self {
            case .supported: return true
            case .unsupported: return false
            case .unknown: return nil
            }
        }
    }

    @ObservedObject var model: OpenAIEndpointsModel
    @Environment(\.dismiss) private var dismiss

    @State private var endpointId: String?
    @State private var name = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var clearApiKey = false
    @State private var modelId = ""
    @State private var contextWindow = ""
    @State private var vision = TriState.unknown
    @State private var toolCalling = TriState.unknown
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var confirmRemove = false
    @State private var loaded = false
    /// Cleared before saving so the normalised URL replaces what was typed;
    /// SwiftUI does not refresh a text field while it is being edited.
    @FocusState private var editingText: Bool

    init(model: OpenAIEndpointsModel, initialEndpointId: String?) {
        self.model = model
        _endpointId = State(initialValue: initialEndpointId)
    }

    /// A plain `String` so SwiftUI shows it verbatim instead of as a link.
    private static let baseURLPlaceholder: String = "Base URL, e.g. http://studio.local:1234/v1"

    private var row: OpenAIEndpointsModel.Row? { endpointId.flatMap(model.row) }
    private var isBusy: Bool { endpointId.map { model.busyIds.contains($0) } ?? false }
    private var typedURLIsLoopback: Bool { (try? OpenAIEndpointURL.normalize(baseURL))?.isLoopback ?? false }

    var body: some View {
        NavigationView {
            Form {
                endpointSection
                modelSection
                capabilitySection
                if let row {
                    actionSection(row)
                }
            }
            .navigationTitle(endpointId == nil ? "Add Endpoint" : "Edit Endpoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("settings.ai.openai.close")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave)
                        .accessibilityIdentifier("settings.ai.openai.save")
                }
            }
            .onAppear(perform: loadOnce)
            .confirmationDialog("Remove this endpoint?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { Task { await remove() } }
            } message: {
                Text("Its saved API key is deleted too. If it is in use, Kelpie stops using it.")
            }
        }
    }

    // MARK: - Sections

    private var endpointSection: some View {
        Section {
            TextField("Name", text: $name)
                .focused($editingText)
                .accessibilityIdentifier("settings.ai.openai.name")
            TextField(Self.baseURLPlaceholder, text: $baseURL)
                .focused($editingText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .accessibilityIdentifier("settings.ai.openai.baseURL")
            if typedURLIsLoopback {
                Text(OpenAIEndpointsSection.loopbackMeans)
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .accessibilityIdentifier("settings.ai.openai.urlLoopbackNote")
            }
            SecureField(apiKeyPlaceholder, text: $apiKey)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("settings.ai.openai.apiKey")
            if row?.hasApiKey == true {
                Button(clearApiKey ? "Keep Saved Key" : "Clear Key", role: clearApiKey ? nil : .destructive) {
                    clearApiKey.toggle()
                    if clearApiKey { apiKey = "" }
                }
                .accessibilityIdentifier("settings.ai.openai.clearKey")
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .accessibilityIdentifier("settings.ai.openai.error")
            }
        } header: {
            Text("Endpoint")
        } footer: {
            Text("The API key is optional and is stored encrypted on this device. It is never shown again or sent anywhere except this endpoint.")
        }
    }

    private var modelSection: some View {
        Section {
            TextField("Model ID", text: $modelId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .accessibilityIdentifier("settings.ai.openai.model")
            if let models = row?.config.models, !models.isEmpty {
                Menu {
                    ForEach(models, id: \.id) { discovered in
                        Button(discoveredLabel(discovered)) { modelId = discovered.id }
                    }
                } label: {
                    Label("Choose from \(models.count) discovered model\(models.count == 1 ? "" : "s")", systemImage: "list.bullet")
                }
                .accessibilityIdentifier("settings.ai.openai.modelPicker")
            }
        } header: {
            Text("Model")
        } footer: {
            Text(row?.config.models.isEmpty == false
                 ? "Model IDs are shown exactly as the server lists them."
                 : "Save, then Refresh Models to list the server's models, or type a model ID.")
        }
    }

    private var capabilitySection: some View {
        Section {
            TextField("Context window (tokens)", text: $contextWindow)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("settings.ai.openai.contextWindow")
            Picker("Vision", selection: $vision) {
                ForEach(TriState.allCases) { Text($0.rawValue).tag($0) }
            }
            .accessibilityIdentifier("settings.ai.openai.vision")
            Picker("Tool calling", selection: $toolCalling) {
                ForEach(TriState.allCases) { Text($0.rawValue).tag($0) }
            }
            .accessibilityIdentifier("settings.ai.openai.toolCalling")
        } header: {
            Text("Capabilities")
        } footer: {
            Text(capabilityFooter)
        }
    }

    private func actionSection(_ row: OpenAIEndpointsModel.Row) -> some View {
        Section {
            HStack {
                Text("Health")
                Spacer()
                OpenAIHealthBadge(state: row.health)
            }
            Button("Refresh Models") { Task { await model.refreshModels(row.id) } }
                .accessibilityIdentifier("settings.ai.openai.refreshModels")
            Button("Test") { Task { await model.test(row.id) } }
                .accessibilityIdentifier("settings.ai.openai.test")
            Button(row.isActive ? "In Use" : "Use") { Task { await model.use(row.id) } }
                .disabled(row.isActive || row.config.model == nil)
                .accessibilityIdentifier("settings.ai.openai.use")
            Button("Remove", role: .destructive) { confirmRemove = true }
                .accessibilityIdentifier("settings.ai.openai.remove")
            if isBusy {
                ProgressView()
            } else if let message = model.statusMessages[row.id] {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.ai.openai.status")
            }
        } header: {
            Text("Actions")
        } footer: {
            Text("Actions use the saved settings. Test sends a short prompt and a tool-calling probe to the selected model.")
        }
        .disabled(isBusy)
    }

    // MARK: - Helpers

    private var apiKeyPlaceholder: String {
        if clearApiKey { return "Key will be removed on save" }
        return row?.hasApiKey == true ? "Saved" : "API key (optional)"
    }

    private var canSave: Bool {
        !isSaving
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var capabilityFooter: String {
        guard let capabilities = row?.config.capabilities else {
            return "Unknown stays unknown until the server reports it, you set it, or a test proves it."
        }
        let context = capabilities.contextWindow.value.map(String.init) ?? "unknown"
        return "In effect: context \(context)\(Self.source(capabilities.contextWindow.source)), "
            + "vision \(Self.describe(capabilities.vision.value))\(Self.source(capabilities.vision.source)), "
            + "tool calling \(Self.describe(capabilities.toolCalling.value))\(Self.source(capabilities.toolCalling.source))."
    }

    private static func describe(_ value: Bool?) -> String {
        value.map { $0 ? "yes" : "no" } ?? "unknown"
    }

    private static func source<Value>(_ source: OpenAICapability<Value>.Source?) -> String {
        source.map { " (\($0.rawValue))" } ?? ""
    }

    private func discoveredLabel(_ stored: OpenAIStoredModel) -> String {
        guard let status = stored.status else { return stored.id }
        return "\(stored.id) — \(status)"
    }

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true
        guard let config = row?.config else { return }
        name = config.name
        baseURL = config.baseURL
        modelId = config.model ?? ""
        contextWindow = config.declared.contextWindow.map(String.init) ?? ""
        vision = TriState(config.declared.vision)
        toolCalling = TriState(config.declared.toolCalling)
    }

    private func save() async {
        editingText = false
        isSaving = true
        defer { isSaving = false }
        let trimmedWindow = contextWindow.trimmingCharacters(in: .whitespaces)
        guard trimmedWindow.isEmpty || (Int(trimmedWindow) ?? 0) > 0 else {
            errorMessage = "Context window must be a positive whole number."
            return
        }
        var declared = row?.config.declared ?? OpenAIDeclaredCapabilities()
        declared.contextWindow = Int(trimmedWindow)
        declared.vision = vision.bool
        declared.toolCalling = toolCalling.bool
        let draft = OpenAIEndpointService.Draft(
            id: endpointId,
            name: name,
            baseURL: baseURL,
            apiKey: apiKey.isEmpty ? nil : apiKey,
            clearApiKey: clearApiKey,
            model: modelId,
            declared: declared
        )
        switch await model.save(draft) {
        case .success(let config):
            errorMessage = nil
            endpointId = config.id
            baseURL = config.baseURL
            apiKey = ""
            clearApiKey = false
        case .failure(let error):
            errorMessage = error.message
        }
    }

    private func remove() async {
        guard let endpointId else { return }
        await model.remove(endpointId)
        dismiss()
    }
}
