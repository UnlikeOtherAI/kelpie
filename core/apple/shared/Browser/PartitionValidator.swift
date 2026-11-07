import Foundation

/// Swift mirror of `packages/shared/src/partition.ts`.
///
/// A partition string is a free-form storage-container identifier supplied on
/// `new-tab`. The rules below are the same ones the CLI and the MCP Zod schema
/// enforce, so a string accepted by one is accepted by all. Keep this file and
/// the TypeScript original in lockstep — a validator that drifts lets a caller
/// create a partition on one platform that another rejects.
enum PartitionValidator {
    /// Maximum length of a partition identifier, in ASCII characters.
    static let maxLength = 128

    /// Maximum length of the free-form per-tab display `name`.
    static let maxNameLength = 200

    /// Reserved internal prefix. Android's non-persistent emulation names its
    /// profiles `ephemeral-<partition>-<uuid>`; a user-supplied string with the
    /// same prefix could collide with one of those.
    static let reservedPrefix = "ephemeral-"

    /// Case-insensitively reserved whole strings. `default` is Android's
    /// `Profile.DEFAULT_PROFILE_NAME`; `.` and `..` are path-traversal hazards
    /// on any platform that derives a directory name from the partition.
    private static let reservedNames: Set<String> = [".", "..", "default"]

    /// Why a partition string was rejected. Raw values match the TypeScript
    /// `PartitionInvalidReason` union so diagnostics read the same everywhere.
    enum Failure: String {
        case charsetOrLength = "charset-or-length"
        case noAlnum = "no-alnum"
        case reserved
        case reservedPrefix = "reserved-prefix"

        /// Human-readable explanation, surfaced in `INVALID_PARTITION`.
        var message: String {
            switch self {
            case .charsetOrLength:
                return "partition must be 1-\(PartitionValidator.maxLength) characters from [A-Za-z0-9._-]"
            case .noAlnum:
                return "partition must contain at least one letter or digit"
            case .reserved:
                return "partition must not be \".\", \"..\" or \"default\" (case-insensitive)"
            case .reservedPrefix:
                return "partition must not start with \"\(PartitionValidator.reservedPrefix)\" (reserved internal prefix)"
            }
        }
    }

    /// Returns `nil` when the string is a valid partition identifier, otherwise
    /// the reason it was rejected.
    ///
    /// Check order is fixed — charset/length, then alphanumeric, then reserved
    /// word, then reserved prefix — so every platform reports the same reason,
    /// not merely the same verdict.
    static func validate(_ value: String) -> Failure? {
        guard !value.isEmpty, value.count <= maxLength else { return .charsetOrLength }
        guard value.unicodeScalars.allSatisfy(isAllowed) else { return .charsetOrLength }
        guard value.unicodeScalars.contains(where: isAlphanumeric) else { return .noAlnum }
        if reservedNames.contains(value.lowercased()) { return .reserved }
        if value.hasPrefix(reservedPrefix) { return .reservedPrefix }
        return nil
    }

    /// Convenience predicate for callers that do not need the failure reason.
    static func isValid(_ value: String) -> Bool {
        validate(value) == nil
    }

    private static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "A"..."Z", "a"..."z", "0"..."9": return true
        default: return false
        }
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        if isAlphanumeric(scalar) { return true }
        switch scalar {
        case ".", "_", "-": return true
        default: return false
        }
    }
}
