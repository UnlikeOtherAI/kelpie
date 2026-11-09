import Foundation
import Darwin

/// Held before SwiftUI constructs a browser session. The file is never removed:
/// every launch must lock the same inode, and process exit releases flock.
final class StandaloneInstance {
    private let descriptor: Int32

    init(lockURL: URL) throws {
        descriptor = open(lockURL.path, O_CREAT | O_RDONLY | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1 else {
            close(descriptor)
            throw POSIXError(.EINVAL)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    deinit { close(descriptor) }
}
