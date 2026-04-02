import Foundation
import Darwin

@MainActor
final class AIState: ObservableObject {
    static let shared = AIState()

    @Published private(set) var isAvailable: Bool
    let isAppleSilicon: Bool

    private init() {
        var result: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let status = sysctlbyname("hw.optional.arm64", &result, &size, nil, 0)
        isAppleSilicon = (status == 0 && result == 1)
        isAvailable = isAppleSilicon
    }

    func enableOllamaOnly() {
        guard !isAppleSilicon else { return }
        isAvailable = true
    }
}
