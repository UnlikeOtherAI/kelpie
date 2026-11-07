import Foundation
import CoreFoundation

/// Version-fenced, generic UOA settings frames. A bad delta is never partially applied.
struct UOASettingsValue {
    private(set) var version: String?
    private(set) var value: Any = NSNull()

    mutating func receive(_ data: Data, namespace: String, key: String) throws -> Bool {
        guard data.count <= 300 * 1024,
              let frame = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Self.integer(frame["protocolVersion"]) == 1,
              frame["namespace"] as? String == namespace, frame["key"] as? String == key,
              let nextVersion = frame["version"] as? String,
              nextVersion.range(of: #"^"[a-f0-9]{64}"$"#, options: .regularExpression) != nil else { throw InvalidFrame() }
        if nextVersion == version { return false }
        let next: Any
        switch frame["type"] as? String {
        case "settings.snapshot":
            guard let snapshot = frame["value"] else { throw InvalidFrame() }
            next = snapshot
        case "settings.delta":
            guard let version, frame["baseVersion"] as? String == version,
                  let operation = frame["operation"] as? [String: Any] else { throw InvalidFrame() }
            if operation["type"] as? String == "replace", let replacement = operation["value"] { next = replacement } else if operation["type"] as? String == "splice",
                    var array = value as? [Any], let items = operation["items"] as? [Any],
                    let index = Self.integer(operation["index"]), let count = Self.integer(operation["deleteCount"]),
                    index <= array.count, count <= array.count - index, array.count - count + items.count <= 100_000 {
                array.replaceSubrange(index..<(index + count), with: items)
                next = array
            } else { throw InvalidFrame() }
        default: throw InvalidFrame()
        }
        value = next
        version = nextVersion
        return true
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue >= 0, number.doubleValue <= 100_000,
              number.doubleValue.rounded() == number.doubleValue else { return nil }
        return number.intValue
    }
    struct InvalidFrame: Error {}
}

@MainActor
final class UOASettingsStream {
    private let socketFactory: () async throws -> URLSessionWebSocketTask
    private let receive: (Any) throws -> Void
    private let namespace: String
    private let key: String
    private var task: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private var generation = UUID()

    init(namespace: String, key: String, socket: @escaping () async throws -> URLSessionWebSocketTask, receive: @escaping (Any) throws -> Void) {
        self.namespace = namespace
        self.key = key
        self.socketFactory = socket
        self.receive = receive
    }

    func start() {
        guard task == nil else { return }
        let current = UUID()
        generation = current
        task = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                guard let self, self.generation == current else { return }
                var currentSocket: URLSessionWebSocketTask?
                do {
                    let connection = try await self.socketFactory()
                    guard self.generation == current, !Task.isCancelled else { connection.cancel(); return }
                    currentSocket = connection
                    self.socket = connection
                    connection.maximumMessageSize = 300 * 1024
                    connection.resume()
                    var state = UOASettingsValue()
                    while !Task.isCancelled {
                        let message = try await connection.receive()
                        guard self.generation == current else { return }
                        let data: Data
                        switch message {
                        case .data(let bytes): data = bytes
                        case .string(let text): data = Data(text.utf8)
                        @unknown default: throw UOASettingsValue.InvalidFrame()
                        }
                        if try state.receive(data, namespace: self.namespace, key: self.key) { try self.receive(state.value) }
                        failures = 0
                    }
                } catch {
                    currentSocket?.cancel(with: .goingAway, reason: nil)
                    if self.socket === currentSocket { self.socket = nil }
                    if Task.isCancelled || self.generation != current { return }
                    failures += 1
                    let delay = min(30.0, pow(2.0, Double(min(failures, 5)))) + Double.random(in: 0...1)
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }
    }

    func stop() {
        generation = UUID()
        task?.cancel()
        task = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }
}
