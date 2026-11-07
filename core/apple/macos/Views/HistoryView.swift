import SwiftUI

/// Anchored history popup, matching the additional-controls popup.
struct HistoryView: View {
    @ObservedObject var store = HistoryStore.shared
    let onNavigate: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("History").font(.headline)
                Spacer()
                if !store.entries.isEmpty {
                    AppKitToolbarButton(
                        systemName: "trash",
                        accessibilityID: "browser.history.clear",
                        accessibilityLabel: "Clear history"
                    ) { store.clear() }
                }
            }
            if store.entries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 32))
                    Text("No History").font(.headline)
                    Text("Visited pages will appear here.").font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.entries.reversed()) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title.isEmpty ? entry.url : entry.title)
                                    .font(.body).lineLimit(1)
                                Text(entry.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Text(entry.timestamp, style: .time).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(AppKitInvisibleButton(
                                accessibilityID: "browser.history.row.\(entry.id.uuidString)",
                                accessibilityLabel: entry.title.isEmpty ? entry.url : entry.title
                            ) {
                                dismiss()
                                onNavigate(entry.url)
                            })
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 320, height: 420)
    }
}
