import AppKit
import Foundation
import Network

/// What the Models panel shows for one OpenAI-compatible endpoint.
struct AIEndpointCard: Identifiable, Equatable {
    let id: String
    let name: String
    let baseURL: String
    let loopback: Bool
    let hasApiKey: Bool
    let model: String?
    let models: [String]
    let isActive: Bool
    let healthState: String
    let healthMessage: String
    let online: Bool
    let contextWindow: String
    let vision: String
    let toolCalling: String
    let declaredContextWindow: Int?
    let declaredVision: Bool?
    let declaredToolCalling: Bool?
}

/// Editable form for adding or changing an endpoint.
struct AIEndpointForm: Equatable {
    var id: String?
    var name = ""
    var baseURL = "http://127.0.0.1:8080/v1"
    var apiKey = ""
    var hasStoredKey = false
    var clearKey = false
    var model = ""
    var contextWindow = ""
    /// "unknown" / "yes" / "no"
    var vision = "unknown"
    var toolCalling = "unknown"
}

/// Main-actor view model for the endpoint section of the AI panel. All
/// mutations go through Kelpie's own `ai-endpoint-*` methods in-process, so
/// the panel and remote API callers share one code path.
@MainActor
final class AIEndpointState: ObservableObject {
    static let shared = AIEndpointState()

    @Published private(set) var cards: [AIEndpointCard] = []
    @Published private(set) var working: Set<String> = []
    @Published var notes: [String: String] = [:]
    @Published var formError: String?

    private let service = OpenAIEndpointService.shared
    private var router: Router?
    private var observers: [NSObjectProtocol] = []
    private let pathMonitor = NWPathMonitor()
    private var lastPathStatus: NWPath.Status?

    private init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .openAIEndpointsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.reload() }
        })
        // Re-check after sleep: cached readiness from before sleep is not live.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.service.refreshActiveNow() }
        })
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.networkChanged(path.status) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.kelpie.ai.endpoints.path"))
    }

    func configure(router: Router) {
        self.router = router
        Task {
            await service.refreshActiveNow()
            await reload()
        }
    }

    private func networkChanged(_ status: NWPath.Status) {
        defer { lastPathStatus = status }
        guard lastPathStatus != nil, lastPathStatus != status else { return }
        Task { await service.refreshActiveNow() }
    }

    func reload() async {
        let list = await service.listJSON()
        let endpoints = list["endpoints"] as? [[String: Any]] ?? []
        cards = endpoints.map(Self.card(from:))
    }

    // MARK: - Actions

    func save(_ form: AIEndpointForm) async -> Bool {
        var body: [String: Any] = [
            "name": form.name,
            "baseURL": form.baseURL,
            "model": form.model.trimmingCharacters(in: .whitespacesAndNewlines),
            "capabilities": [
                "contextWindow": Int(form.contextWindow.trimmingCharacters(in: .whitespaces)).map { $0 as Any } ?? NSNull(),
                "vision": Self.tristate(form.vision),
                "toolCalling": Self.tristate(form.toolCalling)
            ]
        ]
        if let id = form.id { body["id"] = id }
        if form.clearKey {
            body["clearApiKey"] = true
        } else if !form.apiKey.isEmpty {
            body["apiKey"] = form.apiKey
        }
        let response = await dispatch("ai-endpoint-save", body)
        if response["success"] as? Bool == true {
            formError = nil
            // Earlier test notes describe the previous configuration.
            if let id = form.id { notes[id] = nil }
            return true
        }
        formError = Self.errorMessage(response)
        return false
    }

    func remove(_ id: String) async {
        await perform(id, "ai-endpoint-remove", ["id": id]) { _ in "Removed." }
    }

    func refreshModels(_ id: String) async {
        await perform(id, "ai-endpoint-models", ["id": id]) { response in
            let count = (response["models"] as? [Any])?.count ?? 0
            return response["warning"] as? String ?? "Found \(count) model\(count == 1 ? "" : "s")."
        }
    }

    func test(_ id: String) async {
        await perform(id, "ai-endpoint-test", ["id": id, "generate": true, "tools": true]) { response in
            var parts: [String] = []
            if let health = response["health"] as? [String: Any] {
                parts.append("Health: \(health["state"] as? String ?? "unknown")")
            }
            if let generation = response["generation"] as? [String: Any] {
                let ok = generation["ok"] as? Bool ?? false
                parts.append(ok ? "generation OK in \(generation["latencyMs"] as? Int ?? 0) ms" : "generation failed")
            }
            if let tools = response["toolCalling"] as? [String: Any] {
                parts.append((tools["ok"] as? Bool ?? false) ? "tool calling OK" : "tool calling failed: \(tools["detail"] as? String ?? "")")
            }
            return parts.joined(separator: " · ")
        }
    }

    func use(_ id: String, model: String?) async {
        var body: [String: Any] = ["backend": "openai", "endpoint": id]
        if let model, !model.isEmpty { body["model"] = model }
        await perform(id, "ai-load", body) { _ in "Active." }
        await AIState.shared.refresh()
    }

    func form(for card: AIEndpointCard?) -> AIEndpointForm {
        guard let card else { return AIEndpointForm() }
        return AIEndpointForm(
            id: card.id,
            name: card.name,
            baseURL: card.baseURL,
            hasStoredKey: card.hasApiKey,
            model: card.model ?? "",
            contextWindow: card.declaredContextWindow.map(String.init) ?? "",
            vision: Self.tristateText(card.declaredVision),
            toolCalling: Self.tristateText(card.declaredToolCalling)
        )
    }

    private func perform(
        _ id: String,
        _ method: String,
        _ body: [String: Any],
        summary: ([String: Any]) -> String
    ) async {
        working.insert(id)
        defer { working.remove(id) }
        let response = await dispatch(method, body)
        notes[id] = response["success"] as? Bool == true ? summary(response) : Self.errorMessage(response)
        await reload()
    }

    private func dispatch(_ method: String, _ body: [String: Any]) async -> [String: Any] {
        guard let router else {
            return errorResponse(code: "AI_UNAVAILABLE", message: "Kelpie's local server is not ready yet.")
        }
        return await router.handle(method: method, body: body).json
    }

    // MARK: - Mapping

    private static func card(from json: [String: Any]) -> AIEndpointCard {
        let health = json["health"] as? [String: Any] ?? [:]
        let caps = json["capabilities"] as? [String: Any] ?? [:]
        return AIEndpointCard(
            id: json["id"] as? String ?? "",
            name: json["name"] as? String ?? "",
            baseURL: json["baseURL"] as? String ?? "",
            loopback: json["loopback"] as? Bool ?? false,
            hasApiKey: json["hasApiKey"] as? Bool ?? false,
            model: json["model"] as? String,
            models: (json["models"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String },
            isActive: json["active"] as? Bool ?? false,
            healthState: health["state"] as? String ?? "unknown",
            healthMessage: health["message"] as? String ?? "",
            online: health["online"] as? Bool ?? false,
            contextWindow: describe(caps["contextWindow"]) { "\($0) tokens" },
            vision: describe(caps["vision"]) { ($0 as? Bool) == true ? "yes" : "no" },
            toolCalling: describe(caps["toolCalling"]) { ($0 as? Bool) == true ? "yes" : "no" },
            declaredContextWindow: userValue(caps["contextWindow"]) as? Int,
            declaredVision: userValue(caps["vision"]) as? Bool,
            declaredToolCalling: userValue(caps["toolCalling"]) as? Bool
        )
    }

    private static func describe(_ raw: Any?, format: (Any) -> String) -> String {
        guard let capability = raw as? [String: Any], let value = capability["value"], !(value is NSNull) else { return "unknown" }
        let source = capability["source"] as? String ?? ""
        return "\(format(value)) (\(source))"
    }

    private static func userValue(_ raw: Any?) -> Any? {
        guard let capability = raw as? [String: Any], capability["source"] as? String == "user" else { return nil }
        return capability["value"]
    }

    private static func tristate(_ text: String) -> Any {
        switch text {
        case "yes": return true
        case "no": return false
        default: return NSNull()
        }
    }

    private static func tristateText(_ value: Bool?) -> String {
        value.map { $0 ? "yes" : "no" } ?? "unknown"
    }

    static func errorMessage(_ response: [String: Any]) -> String {
        (response["error"] as? [String: Any])?["message"] as? String ?? "Request failed."
    }
}
