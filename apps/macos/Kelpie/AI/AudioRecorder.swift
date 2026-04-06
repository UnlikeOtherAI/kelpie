@preconcurrency import AVFoundation
import Foundation

@MainActor
final class AudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsedMs = 0

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var pcmBuffer = Data()
    private var finalizedAudio: Data?
    private var timer: Timer?
    private var startedAt: Date?
    private let targetFormat: AVAudioFormat
    private let maxDuration: TimeInterval = 30

    init() {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            fatalError("Failed to create target audio format")
        }
        targetFormat = format
    }

    var hasPendingAudio: Bool {
        finalizedAudio != nil
    }

    func start() async throws {
        if isRecording {
            throw RecordingError.alreadyActive
        }

        let permission = await microphonePermission()
        guard permission else {
            throw RecordingError.permissionDenied
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecordingError.configurationFailed("Unable to create audio converter")
        }

        pcmBuffer.removeAll(keepingCapacity: true)
        finalizedAudio = nil
        elapsedMs = 0
        startedAt = Date()
        self.converter = converter
        self.engine = engine

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            Task { @MainActor in
                self.append(buffer: buffer)
            }
        }

        do {
            try engine.start()
        } catch {
            cleanupAfterStop(resetElapsed: true)
            throw RecordingError.configurationFailed(error.localizedDescription)
        }

        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }
                guard let startedAt = self.startedAt else { return }
                self.elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                if Date().timeIntervalSince(startedAt) >= self.maxDuration {
                    _ = self.finalizeRecording()
                }
            }
        }
    }

    func stop() -> Data {
        if let finalizedAudio {
            self.finalizedAudio = nil
            return finalizedAudio
        }

        guard isRecording else {
            return Data()
        }

        let output = finalizeRecording()
        finalizedAudio = nil
        return output
    }

    private func append(buffer: AVAudioPCMBuffer) {
        guard isRecording, let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let estimatedFrameCapacity = max(1, AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: estimatedFrameCapacity) else {
            return
        }

        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard conversionError == nil, status != .error else {
            return
        }
        guard let channelData = outputBuffer.int16ChannelData else { return }

        let frameLength = Int(outputBuffer.frameLength)
        let byteCount = frameLength * MemoryLayout<Int16>.size
        pcmBuffer.append(Data(bytes: channelData.pointee, count: byteCount))
    }

    private func cleanupAfterStop(resetElapsed: Bool) {
        timer?.invalidate()
        timer = nil
        startedAt = nil

        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        engine = nil
        converter = nil
        isRecording = false
        if resetElapsed {
            elapsedMs = 0
        }
    }

    private func finalizeRecording() -> Data {
        let wav = makeWAV(fromPCM: pcmBuffer, sampleRate: 16_000, channels: 1, bitsPerSample: 16)
        finalizedAudio = wav
        cleanupAfterStop(resetElapsed: false)
        return wav
    }

    private func microphonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    private func makeWAV(fromPCM pcm: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(pcm.count)
        let riffSize = UInt32(36) + dataSize

        var header = Data()
        // swiftlint:disable:next force_unwrapping
        header.append("RIFF".data(using: .ascii)!)
        header.append(littleEndianBytes(riffSize))
        // swiftlint:disable:next force_unwrapping
        header.append("WAVE".data(using: .ascii)!)
        // swiftlint:disable:next force_unwrapping
        header.append("fmt ".data(using: .ascii)!)
        header.append(littleEndianBytes(UInt32(16)))
        header.append(littleEndianBytes(UInt16(1)))
        header.append(littleEndianBytes(UInt16(channels)))
        header.append(littleEndianBytes(UInt32(sampleRate)))
        header.append(littleEndianBytes(UInt32(byteRate)))
        header.append(littleEndianBytes(UInt16(blockAlign)))
        header.append(littleEndianBytes(UInt16(bitsPerSample)))
        // swiftlint:disable:next force_unwrapping
        header.append("data".data(using: .ascii)!)
        header.append(littleEndianBytes(dataSize))
        header.append(pcm)
        return header
    }

    private func littleEndianBytes<T: FixedWidthInteger>(_ value: T) -> Data {
        var little = value.littleEndian
        return withUnsafeBytes(of: &little) { Data($0) }
    }
}

extension AudioRecorder {
    enum RecordingError: Error {
        case alreadyActive
        case permissionDenied
        case configurationFailed(String)
    }
}
