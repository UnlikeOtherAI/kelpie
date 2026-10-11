import Combine
import Foundation

/// One authenticated outbound socket per install. The account bearer stays at UOA.
@MainActor
final class NessieConnection: ObservableObject {
    static let shared = NessieConnection()
    static let resource = "https://api.nessie.works/api/kelpie/connect"
    static let gateway = "wss://api.nessie.works/api/kelpie/connect"

    @Published private(set) var status = "Signed out"
    @Published private(set) var paused = false
    @Published private(set) var running = false
    @Published private(set) var requiresSignIn = false
    private var browser: ConnectBrowser?
    private var socket: URLSessionWebSocketTask?
    private var ledger: ConnectLedger?
    private var lifetime: Task<Void, Never>?
    private var renewal: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var action: Task<Void, Never>?
    private var currentCommand: [String: Any]?
    private var accountSubscription: AnyCancellable?
    private var owner: String?
    private var generation: String?
    private var foreground = true
    private var controlledTab: String?
    private var remoteTabMutation = false
    private var epoch = UUID()

    func start(router: Router, context: HandlerContext) {
        guard browser == nil else { return }
        browser = ConnectBrowser(context: context)
        accountSubscription = UOAAccount.shared.$profile.map { $0?.sub }.removeDuplicates().sink { [weak self] sub in
            Task { @MainActor in self?.accountChanged(sub) }
        }
    }

    func setForeground(_ active: Bool) {
        foreground = active
        if !active { stopCurrent(reason: "App entered background") }
        publishLifecycle()
    }

    func togglePause() {
        paused.toggle()
        if paused { stopCurrent(reason: "Paused on device") }
        publishLifecycle()
    }

    func stop() {
        paused = true
        stopCurrent(reason: "Stopped on device")
        publishLifecycle()
    }

    func claimTab(_ tabID: String) { controlledTab = tabID }

    func personChangedTab() {
        guard controlledTab != nil, !remoteTabMutation else { return }
        paused = true
        stopCurrent(reason: "The person changed tabs")
        publishLifecycle()
    }

    func changeTabRemotely<T>(_ action: () -> T) -> T {
        remoteTabMutation = true
        defer { remoteTabMutation = false }
        return action()
    }

    private var lifecycle: String { foreground && !paused && browser?.isReady == true ? "ready" : "paused" }
    var canMutate: Bool { foreground && !paused && socket != nil && generation != nil && owner != nil && UOAAccount.shared.profile?.sub == owner }

    func renewConsent() {
        UOAAccount.shared.signOut()
        UOAAccount.shared.signIn()
    }

    private func accountChanged(_ subject: String?) {
        guard owner != subject else { return }
        let hadOwner = owner != nil
        stopCurrent(reason: "Account changed")
        lifetime?.cancel()
        close()
        epoch = UUID()
        owner = subject
        controlledTab = nil
        ledger = nil
        paused = false
        requiresSignIn = false
        if hadOwner {
            do { try ConnectLedger.clear() } catch { status = "Recovery storage unavailable"; return }
        }
        guard let subject else { status = "Signed out"; return }
        do { ledger = try ConnectLedger(owner: subject) } catch {
            status = "Recovery storage unavailable"
            return
        }
        let current = epoch
        lifetime = Task { [weak self] in await self?.connectLoop(current) }
    }

    private func connectLoop(_ current: UUID) async {
        var delay: UInt64 = 2
        while !Task.isCancelled, epoch == current, owner != nil {
            do {
                status = "Connecting to Nessie"
                let ticket = try await issueTicket()
                guard epoch == current, !Task.isCancelled else { return }
                guard let gatewayURL = URL(string: Self.gateway) else { throw ConnectLedger.Failure.protocolViolation }
                let connection = URLSession.shared.webSocketTask(with: gatewayURL)
                connection.maximumMessageSize = 1024 * 1024
                socket = connection
                connection.resume()
                let ready = await browser?.modelReady() ?? false
                try await send([
                    "type": "hello", "protocol": 1, "ticket": ticket.value,
                    "installationId": installationID, "label": deviceLabel, "platform": platform,
                    "capabilities": ["browser.control", "page.extract"], "lifecycle": lifecycle,
                    "modelReady": ready, "modelInstalled": browser?.modelInstalled ?? false,
                    "modelCapabilities": ["text"], "delegatedBrowsing": false
                ], connection: connection)
                renewal = Task { [weak self] in await self?.renewTickets(connection, current: current, expires: ticket.expires) }
                while !Task.isCancelled, epoch == current, socket === connection {
                    let message = try await connection.receive()
                    let data: Data
                    switch message {
                    case .data(let value): data = value
                    case .string(let value): data = Data(value.utf8)
                    @unknown default: throw ConnectLedger.Failure.protocolViolation
                    }
                    guard data.count <= 1024 * 1024,
                          let frame = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw ConnectLedger.Failure.protocolViolation
                    }
                    try await receive(frame, connection: connection)
                }
            } catch {
                if epoch != current || Task.isCancelled { return }
                status = "Nessie connection unavailable"
                if let failure = error as? UOATransport.Failure, failure.status == 403 {
                    status = "Sign in again to connect Nessie"
                    requiresSignIn = true
                    close()
                    return
                }
            }
            stopCurrent(reason: "Connection lost; reconcile page before continuing")
            close()
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            delay = min(delay * 2, 60)
        }
    }

    private struct Ticket { let value: String; let expires: Double }

    private func issueTicket() async throws -> Ticket {
        let body = try JSONSerialization.data(withJSONObject: ["resource": Self.resource])
        let response = try await UOAAccount.shared.request("/oauth/kelpie/connect", method: "POST", body: body)
        guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              json["gateway_url"] as? String == Self.gateway, json["token_type"] as? String == "Bearer",
              let ticket = json["connection_ticket"] as? String, !ticket.isEmpty,
              let expires = json["expires_in"] as? Double, expires > 0, expires <= 120 else {
            throw ConnectLedger.Failure.protocolViolation
        }
        return Ticket(value: ticket, expires: expires)
    }

    private func renewTickets(_ connection: URLSessionWebSocketTask, current: UUID, expires: Double) async {
        var expiry = expires
        while !Task.isCancelled, epoch == current, socket === connection {
            try? await Task.sleep(nanoseconds: UInt64(max(1, min(60, expiry / 2))) * 1_000_000_000)
            guard !Task.isCancelled, epoch == current, socket === connection else { return }
            do {
                let ticket = try await issueTicket()
                guard let generation, socket === connection else { return }
                try await send(["type": "auth", "generation": generation, "ticket": ticket.value], connection: connection)
                expiry = ticket.expires
            } catch {
                connection.cancel(with: .policyViolation, reason: nil)
                return
            }
        }
    }

    private func receive(_ frame: [String: Any], connection: URLSessionWebSocketTask) async throws {
        guard let ledger else { throw ConnectLedger.Failure.journal }
        let decision = try ledger.execute("receive", frame)
        if decision["kind"] as? String == "welcome" {
            generation = frame["generation"] as? String
            status = lifecycle == "ready" ? "Connected to Nessie" : "Nessie paused"
            startHeartbeat(connection)
        }
        try await sendFrames(decision, connection: connection)
        switch decision["kind"] as? String {
        case "command":
            guard let command = decision["command"] as? [String: Any] else { return }
            if running || lifecycle != "ready" || !canMutate || socket !== connection {
                try await finish(command, state: "failed", error: "Device is paused or busy", connection: connection)
                return
            }
            currentCommand = command
            running = true
            action = Task { [weak self] in await self?.perform(command, connection: connection) }
        case "cancel":
            if frame["jobId"] as? String == currentCommand?["jobId"] as? String,
               frame["attemptId"] as? String == currentCommand?["attemptId"] as? String {
                action?.cancel()
                browser?.cancelInference()
                running = false
                currentCommand = nil
            }
        default: break
        }
    }

    private func perform(_ command: [String: Any], connection: URLSessionWebSocketTask) async {
        var expiry: Task<Void, Never>?
        defer { expiry?.cancel() }
        do {
            guard let deadline = command["deadline"] as? String,
                  let date = Self.deadline(deadline), date > Date(), date.timeIntervalSinceNow <= 86400 else { throw ConnectBrowser.Failure("Job deadline expired") }
            expiry = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(0, date.timeIntervalSinceNow) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.stopCurrent(reason: "Job deadline expired; reconcile page before continuing")
            }
            guard let browser else { throw ConnectBrowser.Failure("Browser unavailable") }
            let output = try await browser.execute(command)
            try Task.checkCancellation()
            try await finish(command, state: "completed", output: output, connection: connection)
        } catch {
            // Cancellation already writes a terminal event. Late callbacks cannot replace it.
            if !Task.isCancelled {
                try? await finish(command, state: "failed", error: (error as? ConnectBrowser.Failure)?.message ?? "Browser action failed", connection: connection)
            }
        }
        if currentCommand?["jobId"] as? String == command["jobId"] as? String,
           currentCommand?["attemptId"] as? String == command["attemptId"] as? String {
            running = false
            currentCommand = nil
        }
    }

    private func finish(_ command: [String: Any], state: String, output: [String: Any]? = nil,
                        error: String? = nil, connection: URLSessionWebSocketTask?) async throws {
        guard let ledger, let jobID = command["jobId"] as? String, let attemptID = command["attemptId"] as? String else { return }
        var result: [String: Any] = ["jobId": jobID, "attemptId": attemptID, "state": state]
        result["output"] = output
        result["error"] = error
        let decision = try ledger.execute("complete", result)
        if let connection, socket === connection { try await sendFrames(decision, connection: connection) }
    }

    private func stopCurrent(reason: String) {
        action?.cancel()
        browser?.cancelInference()
        guard let command = currentCommand, let ledger, let jobID = command["jobId"] as? String,
              let attemptID = command["attemptId"] as? String else { return }
        currentCommand = nil
        running = false
        do {
            let decision = try ledger.execute("complete", ["jobId": jobID,
                "attemptId": attemptID, "state": "cancelled", "error": reason])
            if let socket { Task { try? await sendFrames(decision, connection: socket) } }
        } catch { status = "Recovery storage unavailable"; close() }
    }

    private func startHeartbeat(_ connection: URLSessionWebSocketTask) {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled, let self, self.socket === connection {
                await self.publishHeartbeat(connection)
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    private func publishLifecycle() {
        guard let socket else { return }
        status = lifecycle == "ready" ? "Connected to Nessie" : "Nessie paused"
        Task { await publishHeartbeat(socket) }
    }

    private func publishHeartbeat(_ connection: URLSessionWebSocketTask) async {
        guard let generation else { return }
        let ready = await browser?.modelReady() ?? false
        try? await send(["type": "heartbeat", "generation": generation,
            "lifecycle": lifecycle, "modelReady": ready, "modelInstalled": browser?.modelInstalled ?? false,
            "modelCapabilities": ["text"], "delegatedBrowsing": false], connection: connection)
    }

    private func sendFrames(_ decision: [String: Any], connection: URLSessionWebSocketTask) async throws {
        for frame in decision["frames"] as? [[String: Any]] ?? [] { try await send(frame, connection: connection) }
    }

    private func send(_ frame: [String: Any], connection: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: frame)
        guard data.count <= 1024 * 1024 else { throw ConnectLedger.Failure.protocolViolation }
        try await connection.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func close() {
        renewal?.cancel()
        heartbeat?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        generation = nil
    }

    private static func deadline(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    private var installationID: String {
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: "nessie.connect.installation"), UUID(uuidString: value) != nil { return value }
        let value = UUID().uuidString
        defaults.set(value, forKey: "nessie.connect.installation")
        return value
    }

    private var platform: String {
        #if os(iOS)
        return "ios"
        #else
        return "macos"
        #endif
    }

    private var deviceLabel: String { String(ProcessInfo.processInfo.hostName.prefix(120)) }
}
