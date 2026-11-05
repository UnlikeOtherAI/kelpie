import Foundation

#if DEBUG
/// Bounded stage durations only; no captured pixels, geometry, or page data.
struct ScriptCaptureTiming {
    private var previous = ProcessInfo.processInfo.systemUptime
    private var durations: [Int] = []

    mutating func mark() {
        let now = ProcessInfo.processInfo.systemUptime
        durations.append(Int(min(max((now - previous) * 1000, 0), 99999)))
        previous = now
    }

    func emit(sample: String, engine: String) {
        guard durations.count == 5 else { return }
        let renderer = ["webkit", "chromium"].contains(engine) ? engine : "other"
        let values = durations.map(String.init).joined(separator: ",")
        print("[WorkflowCaptureTiming] sample=\(sample) engine=\(renderer) ms=\(values)")
    }
}
#endif
