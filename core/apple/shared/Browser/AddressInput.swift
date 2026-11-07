import Foundation

/// Shared native policy for user-entered addresses; API navigation stays URL-only.
enum AddressInput {
    static func resolve(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let size = kelpie_resolve_address_input(trimmed, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        kelpie_resolve_address_input(trimmed, &buffer, size)
        let value = String(cString: buffer)
        return value.isEmpty ? nil : value
    }
}
