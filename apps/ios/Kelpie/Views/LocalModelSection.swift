import SwiftUI
import UniformTypeIdentifiers

struct LocalModelSection: View {
    @State private var importing = false
    @State private var busy = false
    @State private var message = "Import a small instruction GGUF for offline text inference. Use a LAN endpoint for larger models."
    @AppStorage("ai.importedModel") private var path = ""

    var body: some View {
        Section("On-device model") {
            Text(message)
            Button("Import GGUF model") { importing = true }.disabled(busy)
            if !path.isEmpty {
                Button("Use imported model") { load(path) }.disabled(busy)
            }
            if busy { Button("Cancel") { LocalInference.shared.cancel() } }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            guard case let .success(url) = result else { return }
            busy = true
            message = "Importing model…"
            Task {
                do {
                    path = try await LocalInference.shared.importModel(url)
                    load(path)
                } catch {
                    message = error.localizedDescription
                    busy = false
                }
            }
        }
    }

    private func load(_ selected: String) {
        busy = true
        message = "Loading on this device…"
        Task {
            let result = await LocalInference.shared.load(["model": selected])
            message = result["success"] as? Bool == true ? "On-device model ready"
                : (result["error"] as? [String: Any])?["message"] as? String ?? "Could not load model"
            busy = false
        }
    }
}
