import AVFoundation
import Foundation

@MainActor
final class AudioRecorder {
    struct Result {
        let audio: Data
        let durationMs: Int
    }

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var pcmBuffer = Data()
    private var finalizedResult: Result?
    private var timer: Timer?
    private(set) var isRecording = false
    private var startedAt: Date?
    private let maxDuration: TimeInterval = 30
    private let targetFormat: AVAudioFormat

    var elapsedMs: Int {
        if isRecording, let startedAt {
            return Int(Date().timeIntervalSince(startedAt) * 1000)
        }

        if let finalizedResult {
            return finalizedResult.durationMs
        }

        return 0
    }

    init() {
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            fatalError("Failed to create AI recorder target format")
        }
        self.targetFormat = targetFormat
    }

    func start() async throws {
        guard !isRecording else { throw RecorderError.alreadyRecording }

        guard await microphonePermission() else {
            throw RecordingFailure.permissionDenied
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            try audioSession.setPreferredSampleRate(16_000)
            try audioSession.setPreferredInputNumberOfChannels(1)
            try audioSession.setActive(true)

            let newEngine = AVAudioEngine()
            let inputNode = newEngine.inputNode
            let inputFormat = inputNode.inputFormat(forBus: 0)
            guard inputFormat.channelCount > 0 else {
                throw RecordingFailure.configurationFailed("No microphone input is available")
            }

            guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                throw RecordingFailure.configurationFailed("Unable to convert microphone audio to 16kHz PCM")
            }

            pcmBuffer.removeAll(keepingCapacity: true)
            finalizedResult = nil
            self.converter = converter
            engine = newEngine
            startedAt = Date()

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
                guard let self else { return }
                // Copy the buffer on the audio thread — AVAudioEngine reuses the buffer memory
                guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
                copy.frameLength = buffer.frameLength
                if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
                    for ch in 0..<Int(buffer.format.channelCount) {
                        dst[ch].update(from: src[ch], count: Int(buffer.frameLength))
                    }
                }
                Task { @MainActor in
                    self.append(buffer: copy)
                }
            }

            newEngine.prepare()
            try newEngine.start()
        } catch let error as RecordingFailure {
            cleanupAfterStop(resetElapsed: true)
            throw error
        } catch {
            cleanupAfterStop(resetElapsed: true)
            throw RecordingFailure.configurationFailed(error.localizedDescription)
        }

        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            if let startedAt = self.startedAt, Date().timeIntervalSince(startedAt) >= self.maxDuration {
                _ = self.finalizeRecording()
            }
        }
    }

    func stop() throws -> Result {
        if let finalizedResult {
            self.finalizedResult = nil
            return finalizedResult
        }

        guard isRecording else { throw RecorderError.notRecording }
        let result = finalizeRecording()
        finalizedResult = nil
        return result
    }

    func snapshot() -> [String: Any] {
        [
            "recording": isRecording,
            "elapsedMs": elapsedMs,
        ]
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

        guard conversionError == nil, status != .error else { return }
        guard let channelData = outputBuffer.int16ChannelData else { return }

        let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
        pcmBuffer.append(Data(bytes: channelData.pointee, count: byteCount))
    }

    private func finalizeRecording() -> Result {
        let result = Result(
            audio: makeWAV(fromPCM: pcmBuffer, sampleRate: 16_000, channels: 1, bitsPerSample: 16),
            durationMs: elapsedMs
        )
        finalizedResult = result
        cleanupAfterStop(resetElapsed: false)
        return result
    }

    private func cleanupAfterStop(resetElapsed: Bool) {
        timer?.invalidate()
        timer = nil

        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
        }

        engine = nil
        converter = nil
        startedAt = nil
        isRecording = false

        if resetElapsed {
            finalizedResult = nil
        }
    }

    private func microphonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
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
        header.append("RIFF".data(using: .ascii)!)
        header.append(littleEndianBytes(riffSize))
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(littleEndianBytes(UInt32(16)))
        header.append(littleEndianBytes(UInt16(1)))
        header.append(littleEndianBytes(UInt16(channels)))
        header.append(littleEndianBytes(UInt32(sampleRate)))
        header.append(littleEndianBytes(UInt32(byteRate)))
        header.append(littleEndianBytes(UInt16(blockAlign)))
        header.append(littleEndianBytes(UInt16(bitsPerSample)))
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

enum RecordingFailure: LocalizedError {
    case permissionDenied
    case configurationFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission is required for ai-record"
        case let .configurationFailed(message):
            return message
        }
    }
}

enum RecorderError: Error {
    case alreadyRecording
    case notRecording

    var response: [String: Any] {
        switch self {
        case .alreadyRecording:
            return errorResponse(code: "RECORDING_ALREADY_ACTIVE", message: "Recording is already active")
        case .notRecording:
            return errorResponse(code: "NO_RECORDING_ACTIVE", message: "No recording is active")
        }
    }
}
