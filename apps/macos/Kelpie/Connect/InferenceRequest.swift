import Foundation

/// Shared native cancellation belongs to this request, including before queue dispatch.
final class InferenceRequest: @unchecked Sendable {
    #if os(iOS)
    let handle = kelpie_local_request_create()
    init() { precondition(handle != nil) }
    deinit { kelpie_local_request_destroy(handle) }
    func cancel() { kelpie_local_request_cancel(handle) }
    #else
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    #endif
}
