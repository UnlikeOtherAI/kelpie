import SwiftUI

/// Full-screen navigation history list. Tap an entry to navigate.
struct HistoryView: View {
    @ObservedObject var store = HistoryStore.shared
    let onNavigate: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No History")
                            .font(.headline)
                        Text("Visited pages will appear here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(store.entries.reversed()) { entry in
                            Button {
                                onNavigate(entry.url)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title.isEmpty ? entry.url : entry.title)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    HStack {
                                        Text(entry.url)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(entry.timestamp, style: .time)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .accessibilityIdentifier("browser.history.row.\(entry.id.uuidString)")
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("browser.history.done")
                }
                if !store.entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", role: .destructive) { store.clear() }
                            .accessibilityIdentifier("browser.history.clear")
                    }
                }
            }
        }
    }
}
