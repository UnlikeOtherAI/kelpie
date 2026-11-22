import SwiftUI
#if os(iOS)
import QuickLook
#endif

struct DownloadsPopup: View {
    @ObservedObject private var store = DownloadStore.shared
    #if os(iOS)
    @State private var preview: URL?
    #endif

    var body: some View {
        let records = store.list()
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Downloads").font(.headline)
                Spacer()
                Button("Clear") { store.clearFinished() }
                    .disabled(!records.contains { $0.state != .inProgress })
            }
            Divider()
            if records.isEmpty {
                Text("No downloads").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(records, id: \.id) { row($0) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        #if os(iOS)
        .quickLookPreview($preview)
        #endif
    }

    private func row(_ record: DownloadStore.Record) -> some View {
        let name = record.filename ?? URL(string: record.url)?.lastPathComponent ?? "Download"
        return HStack(spacing: 4) {
            if record.state == .complete, let path = record.path {
                let file = URL(fileURLWithPath: path)
                Button {
                    #if os(macOS)
                    NSWorkspace.shared.open(file)
                    #else
                    preview = file
                    #endif
                } label: {
                    label(name, status(record))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(name)")
                #if os(macOS)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                } label: {
                    Image(systemName: "magnifyingglass").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
                .accessibilityLabel("Show in Finder")
                #else
                ShareLink(item: file) {
                    Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share downloaded file")
                #endif
            } else {
                label(name, status(record))
            }
        }
    }

    private func label(_ name: String, _ status: String) -> some View {
        VStack(alignment: .leading) {
            Text(name).lineLimit(1).truncationMode(.middle)
            Text(status).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func status(_ record: DownloadStore.Record) -> String {
        switch record.state {
        case .inProgress: return "Downloading…"
        case .failed: return record.error ?? "Failed"
        case .complete: return ByteCountFormatter.string(fromByteCount: record.bytesReceived, countStyle: .file)
        }
    }
}
