import Foundation
import Network

/// Outgoing sync requests. Each request uses its own connection, and the connected
/// peer address must pass the same address rule the listener applies.
enum SyncHTTPClient {
    static func post(
        _ endpoint: NWEndpoint,
        path: String,
        body: Data,
        headers: [String: String] = [:],
        timeout: TimeInterval,
        rule: SyncAddressRule
    ) async throws -> SyncHTTPResponse {
        var request = "POST \(path) HTTP/1.1\r\nHost: kelpie-sync\r\nContent-Type: application/json\r\n"
        for (name, value) in headers { request += "\(name): \(value)\r\n" }
        request += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        let call = SyncHTTPCall(connection: NWConnection(to: endpoint, using: .tcp), rule: rule)
        return try await call.run(request: Data(request.utf8) + body, timeout: timeout)
    }

    /// Resolves an advertised service to the address it is reached on, preferring IPv4,
    /// and returns it only when the address rule allows it.
    static func resolve(_ service: NWEndpoint, rule: SyncAddressRule, timeout: TimeInterval = 5) async -> NWEndpoint? {
        let ipv4 = NWParameters.tcp
        (ipv4.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        for parameters in [ipv4, NWParameters.tcp] {
            let call = SyncHTTPCall(connection: NWConnection(to: service, using: parameters), rule: rule)
            if let endpoint = try? await call.connect(timeout: timeout) { return endpoint }
        }
        return nil
    }
}

/// One connection's lifetime. The continuation resumes exactly once: on the response,
/// a failure, the deadline or task cancellation.
private final class SyncHTTPCall: @unchecked Sendable {
    private enum Outcome {
        case response(SyncHTTPResponse)
        case endpoint(NWEndpoint)
    }

    private let connection: NWConnection
    private let rule: SyncAddressRule
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Outcome, Error>?
    private var result: Result<Outcome, Error>?
    private var buffer = Data()

    init(connection: NWConnection, rule: SyncAddressRule) {
        self.connection = connection
        self.rule = rule
    }

    func run(request: Data, timeout: TimeInterval) async throws -> SyncHTTPResponse {
        guard case .response(let response) = try await start(request: request, timeout: timeout) else {
            throw SyncNetworkError.malformed
        }
        return response
    }

    func connect(timeout: TimeInterval) async throws -> NWEndpoint {
        guard case .endpoint(let endpoint) = try await start(request: nil, timeout: timeout) else {
            throw SyncNetworkError.malformed
        }
        return endpoint
    }

    private func start(request: Data?, timeout: TimeInterval) async throws -> Outcome {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Outcome, Error>) in
                lock.lock()
                if let result {
                    lock.unlock()
                    continuation.resume(with: result)
                    return
                }
                self.continuation = continuation
                lock.unlock()
                connection.stateUpdateHandler = { [self] state in self.stateChanged(state, request: request) }
                connection.start(queue: SyncNetwork.queue)
                SyncNetwork.queue.asyncAfter(deadline: .now() + timeout) { [self] in finish(.failure(SyncNetworkError.timeout)) }
            }
        } onCancel: {
            finish(.failure(CancellationError()))
        }
    }

    private func stateChanged(_ state: NWConnection.State, request: Data?) {
        switch state {
        case .ready:
            guard let remote = connection.currentPath?.remoteEndpoint, rule.allows(remote) else {
                finish(.failure(SyncNetworkError.addressRejected))
                return
            }
            guard let request else {
                finish(.success(.endpoint(remote)))
                return
            }
            connection.send(content: request, completion: .contentProcessed { [self] error in
                if error != nil { self.finish(.failure(SyncNetworkError.unreachable)) } else { self.receive() }
            })
        case .failed, .cancelled:
            finish(.failure(SyncNetworkError.unreachable))
        case .waiting:
            finish(.failure(SyncNetworkError.unreachable))
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] content, _, isComplete, error in
            if let content { buffer.append(content) }
            if buffer.count > SyncNetwork.maxResponseBytes {
                finish(.failure(SyncNetworkError.malformed))
            } else if let response = SyncHTTPResponse.parse(buffer, complete: isComplete) {
                finish(.success(.response(response)))
            } else if isComplete || error != nil {
                finish(.failure(SyncNetworkError.malformed))
            } else {
                receive()
            }
        }
    }

    private func finish(_ outcome: Result<Outcome, Error>) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = outcome
        let waiting = continuation
        continuation = nil
        lock.unlock()
        connection.stateUpdateHandler = nil
        connection.cancel()
        waiting?.resume(with: outcome)
    }
}
