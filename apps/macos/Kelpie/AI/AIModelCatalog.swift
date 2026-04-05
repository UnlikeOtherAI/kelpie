import Foundation

struct AIModelDescription: Equatable {
    let summary: String
    let strengths: [String]
    let limitations: [String]
    let bestFor: String
    let speedRating: String
}

struct AIApprovedModel: Identifiable, Equatable {
    let id: String
    let name: String
    let huggingFaceRepo: String
    let huggingFaceFile: String
    let sizeBytes: Int64
    let ramWhenLoadedGB: Double
    let capabilities: [String]
    let memory: Bool
    let minRamGB: Double
    let recommendedRamGB: Double
    let quantization: String
    let contextWindow: Int
    let description: AIModelDescription

    var downloadURL: URL {
        URL(string: "https://huggingface.co/\(huggingFaceRepo)/resolve/main/\(huggingFaceFile)")!
    }
}

enum AIModelCatalog {
    static let approvedNativeModels: [AIApprovedModel] = [
        AIApprovedModel(
            id: "gemma-4-e2b-q4",
            name: "Gemma 4 E2B Q4",
            huggingFaceRepo: "bartowski/google_gemma-4-E2B-it-GGUF",
            huggingFaceFile: "google_gemma-4-E2B-it-Q4_K_M.gguf",
            sizeBytes: 2_500_000_000,
            ramWhenLoadedGB: 3.8,
            capabilities: ["text", "vision", "audio"],
            memory: false,
            minRamGB: 8,
            recommendedRamGB: 16,
            quantization: "Q4_K_M",
            contextWindow: 8192,
            description: AIModelDescription(
                summary: "Understands text, images, and speech for local page analysis.",
                strengths: [
                    "Describes screenshots and visual page layouts",
                    "Summarises articles and extracts key information",
                    "Answers spoken questions with native audio input",
                ],
                limitations: [
                    "Image and audio prompts are slower than text-only prompts",
                    "Long pages may need tighter prompting to stay focused",
                ],
                bestFor: "General local browsing assistance with text, vision, and audio input",
                speedRating: "moderate"
            )
        ),
        AIApprovedModel(
            id: "gemma-4-e2b-q8",
            name: "Gemma 4 E2B Q8",
            huggingFaceRepo: "bartowski/google_gemma-4-E2B-it-GGUF",
            huggingFaceFile: "google_gemma-4-E2B-it-Q8_0.gguf",
            sizeBytes: 5_000_000_000,
            ramWhenLoadedGB: 8,
            capabilities: ["text", "vision", "audio"],
            memory: false,
            minRamGB: 16,
            recommendedRamGB: 32,
            quantization: "Q8_0",
            contextWindow: 8192,
            description: AIModelDescription(
                summary: "Higher-quality Gemma 4 build with the same multimodal capabilities.",
                strengths: [
                    "Produces more accurate answers on nuanced questions",
                    "Handles complex visual layouts more reliably",
                    "Retains the same screenshot and audio support as Q4",
                ],
                limitations: [
                    "Needs substantially more RAM than the Q4 build",
                    "Runs slower than the Q4 build on the same hardware",
                ],
                bestFor: "Accuracy-focused local analysis when memory headroom is available",
                speedRating: "moderate"
            )
        ),
    ]

    static func approvedModel(id: String) -> AIApprovedModel? {
        approvedNativeModels.first { $0.id == id }
    }
}

struct AIDeviceCapabilities: Equatable {
    let chipset: String
    let totalRamGB: Double
    let diskFreeGB: Double
    let platform: String

    var summaryLine: String {
        "\(chipset), \(formatted(totalRamGB)) GB RAM, \(formatted(diskFreeGB)) GB free"
    }

    private func formatted(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}

enum AINativeModelFitness: Equatable {
    case recommended
    case possible(message: String)
    case notRecommended(message: String)
    case noStorage(message: String)
}

extension AIApprovedModel {
    func fitness(for device: AIDeviceCapabilities) -> AINativeModelFitness {
        let downloadSizeGB = Double(sizeBytes) / 1_000_000_000
        if device.diskFreeGB < downloadSizeGB {
            return .noStorage(
                message: "Not enough storage — needs \(format(downloadSizeGB)) GB, you have \(format(device.diskFreeGB)) GB free"
            )
        }
        if device.totalRamGB < minRamGB {
            return .notRecommended(
                message: "Not recommended — requires \(format(minRamGB)) GB RAM, you have \(format(device.totalRamGB)) GB"
            )
        }
        if device.totalRamGB < recommendedRamGB || device.diskFreeGB < downloadSizeGB * 1.2 {
            return .possible(message: "May run slowly on this device")
        }
        return .recommended
    }

    private func format(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}
