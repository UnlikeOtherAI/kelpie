import Foundation
import Darwin
import SwiftUI

enum AIBackend: String, Equatable {
    case native
    case ollama
}

struct AIActiveModel: Equatable {
    let id: String
    let name: String
    let backend: AIBackend
    let capabilities: [String]
}

struct AIOllamaModel: Identifiable, Equatable {
    let id: String
    let name: String
    let sizeBytes: Int64?
    let capabilities: [String]
    let isActive: Bool
}

struct AINativeModelCard: Identifiable, Equatable {
    enum DownloadState: Equatable {
        case idle
        case downloading
    }

    let id: String
    let model: AIApprovedModel
    let isDownloaded: Bool
    let isActive: Bool
    let fitness: AINativeModelFitness
    let downloadState: DownloadState

    var canDownload: Bool {
        if case .noStorage = fitness {
            return false
        }
        return downloadState == .idle && !isDownloaded
    }

    var buttonTitle: String {
        if isActive {
            return "Unload"
        }
        if isDownloaded {
            return "Load"
        }
        if downloadState == .downloading {
            return "Downloading…"
        }
        if case .notRecommended = fitness {
            return "Download anyway"
        }
        return "Download"
    }
}

@MainActor
final class AIState: ObservableObject {
    static let shared = AIState()

    @Published private(set) var isAvailable: Bool
    let isAppleSilicon: Bool

    @Published var ollamaEndpoint = "http://localhost:11434"
    @Published private(set) var ollamaReachable = false
    @Published private(set) var activeModel: AIActiveModel?
    @Published private(set) var deviceCapabilities: AIDeviceCapabilities
    @Published private(set) var nativeModelCards: [AINativeModelCard] = []
    @Published private(set) var ollamaModels: [AIOllamaModel] = []
    @Published private(set) var lastError: String?
    @AppStorage("huggingFaceToken") var huggingFaceToken: String = ""
    var onAuthFailureNavigate: ((URL) -> Void)?

    private var serverPort: UInt16?
    private var refreshTask: Task<Void, Never>?
    private var downloadTasks: [String: Task<Void, Never>] = [:]
    private var downloadStates: [String: AINativeModelCard.DownloadState] = [:]
    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()

    private let aiManager: AIManager = {
        let modelsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kelpie/models", isDirectory: true).path
        return AIManager(modelsDir: modelsDir)
    }()

    private init() {
        let isArm64 = Self.detectAppleSilicon()
        isAppleSilicon = isArm64
        deviceCapabilities = Self.currentDeviceCapabilities()
        isAvailable = isArm64
        rebuildModelCards()
        refreshTask = Task { [weak self] in
            await self?.refreshLoop()
        }
    }

    func configure(localServerPort: UInt16) {
        guard serverPort != localServerPort else { return }
        serverPort = localServerPort
        Task {
            await refresh()
        }
    }

    func refresh() async {
        deviceCapabilities = Self.currentDeviceCapabilities()
        await refreshActiveStatus()
        await refreshOllamaModels()
        rebuildModelCards()
        isAvailable = isAppleSilicon || ollamaReachable
    }

    func dismissError() {
        lastError = nil
    }

    func enableOllamaOnly() {
        guard !isAppleSilicon else { return }
        isAvailable = true
    }

    func testOllama() async {
        await refreshOllamaModels()
        rebuildModelCards()
    }

    func loadNativeModel(id: String) async -> Bool {
        await sendControlRequest(method: "ai-load", body: ["model": id])
    }

    func loadOllamaModel(name: String) async -> Bool {
        await sendControlRequest(method: "ai-load", body: [
            "model": "ollama:\(name)",
            "ollamaEndpoint": ollamaEndpoint,
        ])
    }

    func unloadModel() async -> Bool {
        await sendControlRequest(method: "ai-unload", body: [:])
    }

    func ask(prompt: String, history: [AIChatMessage]) async throws -> String {
        guard let activeModel else {
            throw NSError(domain: "AIState", code: 1, userInfo: [NSLocalizedDescriptionKey: "Load a model first."])
        }

        var body: [String: Any] = ["prompt": prompt]

        if activeModel.backend == .ollama {
            let priorMessages = history.suffix(10).map { $0.apiPayload }
            body["messages"] = priorMessages
        } else {
            body["context"] = "page_text"
        }

        let response = try await sendLocalRequest(method: "ai-infer", body: body)
        guard (response["success"] as? Bool) != false else {
            throw NSError(
                domain: "AIState",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: responseErrorMessage(response)]
            )
        }
        return response["response"] as? String ?? ""
    }

    func downloadNativeModel(id: String) {
        guard downloadTasks[id] == nil, AIModelCatalog.approvedModel(id: id) != nil else { return }

        downloadStates[id] = .downloading
        rebuildModelCards()

        aiManager.hfToken = huggingFaceToken

        downloadTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.downloadTasks[id] = nil
                    self.downloadStates[id] = .idle
                    self.rebuildModelCards()
                }
            }

            let error = await Task.detached { [weak self] in
                self?.aiManager.downloadModel(id: id, progress: nil)
            }.value

            if let error {
                await MainActor.run {
                    if error.contains("auth_required") {
                        self.lastError = "This model requires a Hugging Face token."
                        self.onAuthFailureNavigate?(
                            URL(string: "https://huggingface.co/settings/tokens")!
                        )
                    } else {
                        self.lastError = error
                    }
                }
                return
            }

            await self.refresh()
        }
    }

    func removeNativeModel(id: String) {
        Task { [weak self] in
            guard let self else { return }
            _ = await Task.detached { self.aiManager.removeModel(id: id) }.value
            await self.refresh()
        }
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    private func rebuildModelCards() {
        nativeModelCards = AIModelCatalog.approvedNativeModels
            .map { model in
                let downloaded = aiManager.isModelDownloaded(id: model.id)
                let active = activeModel?.backend == .native && activeModel?.id == model.id
                return AINativeModelCard(
                    id: model.id,
                    model: model,
                    isDownloaded: downloaded,
                    isActive: active,
                    fitness: model.fitness(for: deviceCapabilities),
                    downloadState: downloadStates[model.id] ?? .idle
                )
            }
            .sorted { lhs, rhs in
                sortOrder(for: lhs.fitness) < sortOrder(for: rhs.fitness)
                    || (sortOrder(for: lhs.fitness) == sortOrder(for: rhs.fitness) && lhs.model.sizeBytes < rhs.model.sizeBytes)
            }
    }

    private func sortOrder(for fitness: AINativeModelFitness) -> Int {
        switch fitness {
        case .recommended: return 0
        case .possible: return 1
        case .notRecommended: return 2
        case .noStorage: return 3
        }
    }

    private func refreshActiveStatus() async {
        guard serverPort != nil else { return }
        do {
            let response = try await sendLocalRequest(method: "ai-status", body: [:])
            guard (response["success"] as? Bool) != false else {
                lastError = responseErrorMessage(response)
                return
            }

            let loaded = response["loaded"] as? Bool ?? false
            if !loaded {
                activeModel = nil
                return
            }

            let backend = AIBackend(rawValue: response["backend"] as? String ?? "native") ?? .native
            let name = response["model"] as? String ?? "Unknown Model"
            let modelID: String
            if backend == .native {
                modelID = AIModelCatalog.approvedNativeModels.first(where: { $0.name == name || $0.id == name })?.id ?? name
            } else {
                modelID = name
            }
            activeModel = AIActiveModel(
                id: modelID,
                name: name,
                backend: backend,
                capabilities: response["capabilities"] as? [String] ?? ["text"]
            )

            if let endpoint = response["ollamaEndpoint"] as? String, !endpoint.isEmpty {
                ollamaEndpoint = endpoint
            }
        } catch {
            lastError = nil
            activeModel = nil
        }
    }

    private func refreshOllamaModels() async {
        aiManager.setOllamaEndpoint(ollamaEndpoint)

        let reachable = await Task.detached { [weak self] in
            self?.aiManager.ollamaReachable() ?? false
        }.value

        guard reachable else {
            ollamaReachable = false
            ollamaModels = []
            return
        }

        let modelsJSON = await Task.detached { [weak self] in
            self?.aiManager.ollamaListModels() ?? []
        }.value

        ollamaModels = modelsJSON
            .compactMap { raw in
                guard let name = raw["name"] as? String else { return nil }
                let size = (raw["size"] as? NSNumber)?.int64Value
                let caps = (raw["capabilities"] as? [String]) ?? Self.ollamaCapabilities(for: name)
                return AIOllamaModel(
                    id: name,
                    name: name,
                    sizeBytes: size,
                    capabilities: caps,
                    isActive: activeModel?.backend == .ollama && activeModel?.name == name
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        ollamaReachable = true
    }

    private func sendControlRequest(method: String, body: [String: Any]) async -> Bool {
        do {
            let response = try await sendLocalRequest(method: method, body: body)
            guard (response["success"] as? Bool) != false else {
                lastError = responseErrorMessage(response)
                return false
            }
            await refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func sendLocalRequest(method: String, body: [String: Any]) async throws -> [String: Any] {
        guard let serverPort else {
            throw NSError(domain: "AIState", code: 3, userInfo: [NSLocalizedDescriptionKey: "Local AI server is not ready yet."])
        }
        let url = URL(string: "http://127.0.0.1:\(serverPort)/v1/\(method)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw NSError(domain: "AIState", code: 4, userInfo: [NSLocalizedDescriptionKey: "Local AI request failed."])
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func responseErrorMessage(_ response: [String: Any]) -> String {
        if let error = response["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return response["message"] as? String ?? "Request failed."
    }

    private static func detectAppleSilicon() -> Bool {
        var result: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let status = sysctlbyname("hw.optional.arm64", &result, &size, nil, 0)
        return status == 0 && result == 1
    }

    private static func currentDeviceCapabilities() -> AIDeviceCapabilities {
        let processInfo = ProcessInfo.processInfo
        let totalRamGB = Double(processInfo.physicalMemory) / 1_073_741_824
        let diskFree = (try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
        let diskFreeGB = diskFree / 1_000_000_000
        return AIDeviceCapabilities(
            chipset: cpuBrandString() ?? DeviceInfo.current(port: 0).model,
            totalRamGB: totalRamGB,
            diskFreeGB: diskFreeGB,
            platform: "macos"
        )
    }

    private static func cpuBrandString() -> String? {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    private static func modelDirectory(id: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kelpie/models/\(id)", isDirectory: true)
    }

    private static func ollamaCapabilities(for model: String) -> [String] {
        let lowercased = model.lowercased()
        if lowercased.contains("llava") || lowercased.contains("bakllava") || lowercased.contains("moondream") {
            return ["text", "vision"]
        }
        return ["text"]
    }
}

struct AIChatMessage: Identifiable, Equatable {
    enum Role: String {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String

    var apiPayload: [String: String] {
        ["role": role.rawValue, "content": text]
    }
}
