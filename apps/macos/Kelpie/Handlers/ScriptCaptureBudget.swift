import Darwin
import Foundation
import ImageIO

/// Each bucket owns one flat directory. Output and queued-frame scratch use separate explicit bounds.
final class ScriptCaptureBudget: @unchecked Sendable {
    let directory: URL
    let maximumBytes: Int
    private let lock = NSLock()
    private var reservation = 0
    private let closeFile: (FileHandle) throws -> Void

    init(directory: URL, maximumBytes: Int, closeFile: @escaping (FileHandle) throws -> Void = { try $0.close() }) {
        self.directory = directory
        self.maximumBytes = maximumBytes
        self.closeFile = closeFile
    }

    func reserveFooter(_ bytes: Int) {
        lock.lock()
        defer { lock.unlock() }
        reservation = max(bytes, 0)
    }

    func check(headroom: Int = 0) throws {
        lock.lock()
        defer { lock.unlock() }
        guard headroom >= 0, try bytesOnDisk() <= maximumBytes - reservation - headroom else { throw ScriptCaptureError.budget }
    }

    func output(url: URL) throws -> Output {
        guard url.deletingLastPathComponent().resolvingSymlinksInPath().path == directory.resolvingSymlinksInPath().path else {
            throw ScriptCaptureError.image
        }
        return try Output(url: url, budget: self)
    }

    func withConsumer<T>(url: URL, _ encode: (CGDataConsumer) throws -> T) throws -> T {
        let sink = try output(url: url)
        do {
            let consumer = try makeConsumer(sink)
            let result = try encode(consumer)
            try sink.close()
            return result
        } catch {
            try? sink.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private func makeConsumer(_ sink: Output) throws -> CGDataConsumer {
        let retained = Unmanaged.passRetained(sink)
        var callbacks = CGDataConsumerCallbacks(
            putBytes: { info, bytes, count in
                guard let info else { return 0 }
                return Unmanaged<Output>.fromOpaque(info).takeUnretainedValue().writeRaw(bytes, count: count)
            },
            releaseConsumer: { info in
                if let info { Unmanaged<Output>.fromOpaque(info).release() }
            }
        )
        guard let consumer = CGDataConsumer(info: retained.toOpaque(), cbks: &callbacks) else {
            retained.release()
            throw ScriptCaptureError.image
        }
        return consumer
    }

    private func write(_ bytes: UnsafeRawPointer, count: Int, handle: FileHandle) -> Int {
        lock.lock()
        defer { lock.unlock() }
        do {
            let existing = try bytesOnDisk()
            guard count >= 0, count <= maximumBytes - reservation - existing else { return 0 }
            try handle.write(contentsOf: Data(bytes: bytes, count: count))
            return count
        } catch { return 0 }
    }

    private func bytesOnDisk() throws -> Int {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        return try urls.reduce(0) { total, url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { throw ScriptCaptureError.image }
            return total + (values.fileSize ?? 0)
        }
    }

    final class Output {
        private let handle: FileHandle
        private let budget: ScriptCaptureBudget
        private var closed = false
        init(url: URL, budget: ScriptCaptureBudget) throws {
            let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { throw ScriptCaptureError.image }
            handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            self.budget = budget
        }
        deinit { try? close() }
        func close() throws {
            guard !closed else { return }
            try budget.closeFile(handle)
            closed = true
        }
        func write(_ data: Data) throws {
            guard !closed else { throw ScriptCaptureError.image }
            let written = data.withUnsafeBytes { bytes -> Int in
                guard let base = bytes.baseAddress else { return 0 }
                return writeRaw(base, count: bytes.count)
            }
            guard written == data.count else { throw ScriptCaptureError.budget }
        }
        /// Atomic at the media-unit boundary: a failed write rolls back to the last complete fragment.
        func appendUnit(_ data: Data) throws {
            let offset = try handle.offset()
            do { try write(data) } catch {
                do {
                    try handle.truncate(atOffset: offset)
                    try handle.seek(toOffset: offset)
                } catch { throw ScriptCaptureError.image }
                throw error
            }
        }

        fileprivate func writeRaw(_ bytes: UnsafeRawPointer, count: Int) -> Int {
            guard !closed else { return 0 }
            return budget.write(bytes, count: count, handle: handle)
        }
    }
}
