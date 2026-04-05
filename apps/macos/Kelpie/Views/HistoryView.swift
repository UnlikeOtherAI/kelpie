import SwiftUI

/// macOS navigation history sheet. Tap an entry to navigate.
struct HistoryView: View {
    @ObservedObject var store = HistoryStore.shared
    let onNavigate: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AppKitFirstMouseSheetContainer {
            NavigationStack {
                Group {
                    if store.entries.isEmpty {
                        emptyState(
                            icon: "clock.arrow.circlepath",
                            title: "No History",
                            subtitle: "Visited pages will appear here."
                        )
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
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                                    .contentShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("browser.history.row.\(entry.id.uuidString)")
                                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                                .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.inset)
                    }
                }
                .navigationTitle("History")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("browser.history.done")
                    }
                    if !store.entries.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Clear", role: .destructive) { store.clear() }
                                .accessibilityIdentifier("browser.history.clear")
                        }
                    }
                }
            }
            .frame(minWidth: 520, minHeight: 420)
        }
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
