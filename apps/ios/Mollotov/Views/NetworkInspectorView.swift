import SwiftUI

/// Charles-style network traffic inspector.
struct NetworkInspectorView: View {
    @ObservedObject var store = NetworkTrafficStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var methodFilter: String?
    @State private var categoryFilter: String?
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                if filteredEntries.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No Requests")
                            .font(.headline)
                        Text("Network traffic will appear here as pages load.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List(filteredEntries, id: \.offset) { item in
                        NavigationLink {
                            NetworkDetailView(entry: item.element, index: item.offset)
                        } label: {
                            requestRow(item.element)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Network")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) { store.clear() }
                }
            }
            .searchable(text: $searchText, prompt: "Filter by URL")
        }
    }

    private var filteredEntries: [EnumeratedSequence<[NetworkTrafficStore.TrafficEntry]>.Element] {
        var result = Array(store.entries.enumerated())
        if let m = methodFilter { result = result.filter { $0.element.method == m } }
        if let c = categoryFilter { result = result.filter { $0.element.category == c } }
        if !searchText.isEmpty { result = result.filter { $0.element.url.localizedCaseInsensitiveContains(searchText) } }
        return result
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("All", active: methodFilter == nil && categoryFilter == nil) {
                    methodFilter = nil; categoryFilter = nil
                }
                Group {
                    filterChip("GET", active: methodFilter == "GET") { toggleMethod("GET") }
                    filterChip("POST", active: methodFilter == "POST") { toggleMethod("POST") }
                    filterChip("PUT", active: methodFilter == "PUT") { toggleMethod("PUT") }
                    filterChip("DELETE", active: methodFilter == "DELETE") { toggleMethod("DELETE") }
                }
                Divider().frame(height: 20)
                Group {
                    filterChip("JSON", active: categoryFilter == "JSON") { toggleCategory("JSON") }
                    filterChip("HTML", active: categoryFilter == "HTML") { toggleCategory("HTML") }
                    filterChip("JS", active: categoryFilter == "JS") { toggleCategory("JS") }
                    filterChip("CSS", active: categoryFilter == "CSS") { toggleCategory("CSS") }
                    filterChip("Image", active: categoryFilter == "Image") { toggleCategory("Image") }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func toggleMethod(_ m: String) {
        methodFilter = methodFilter == m ? nil : m
    }

    private func toggleCategory(_ c: String) {
        categoryFilter = categoryFilter == c ? nil : c
    }

    private func filterChip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(active ? .semibold : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(active ? Color.accentColor : Color(.tertiarySystemFill))
                .foregroundColor(active ? .white : .primary)
                .clipShape(Capsule())
        }
    }

    private func requestRow(_ entry: NetworkTrafficStore.TrafficEntry) -> some View {
        HStack(spacing: 8) {
            Text(entry.method)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(methodColor(entry.method))
                .frame(width: 50, alignment: .leading)
            Text(String(entry.statusCode))
                .font(.caption)
                .foregroundColor(statusColor(entry.statusCode))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(shortenURL(entry.url))
                    .font(.caption)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.category)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(entry.duration)ms")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(formatBytes(entry.size))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func methodColor(_ method: String) -> Color {
        switch method {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "OPTIONS": return .purple
        default: return .secondary
        }
    }

    private func statusColor(_ code: Int) -> Color {
        switch code {
        case 200..<300: return .green
        case 300..<400: return .orange
        case 400..<600: return .red
        default: return .secondary
        }
    }

    private func shortenURL(_ url: String) -> String {
        guard let components = URLComponents(string: url) else { return url }
        return (components.path.isEmpty ? "/" : components.path) + (components.query.map { "?\($0)" } ?? "")
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024)KB" }
        return String(format: "%.1fMB", Double(bytes) / 1024.0 / 1024.0)
    }
}

/// Detail view for a single network request/response.
struct NetworkDetailView: View {
    let entry: NetworkTrafficStore.TrafficEntry
    let index: Int

    var body: some View {
        List {
            Section("Request") {
                labelRow("Method", entry.method)
                labelRow("URL", entry.url)
                if let body = entry.requestBody, !body.isEmpty {
                    DisclosureGroup("Body") {
                        Text(body).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
                if !entry.requestHeaders.isEmpty {
                    DisclosureGroup("Headers") {
                        ForEach(entry.requestHeaders.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                            labelRow(k, v)
                        }
                    }
                }
            }
            Section("Response") {
                labelRow("Status", "\(entry.statusCode)")
                labelRow("Content-Type", entry.contentType)
                labelRow("Size", "\(entry.size) bytes")
                labelRow("Duration", "\(entry.duration) ms")
                if let body = entry.responseBody, !body.isEmpty {
                    DisclosureGroup("Body") {
                        Text(body).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
                if !entry.responseHeaders.isEmpty {
                    DisclosureGroup("Headers") {
                        ForEach(entry.responseHeaders.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                            labelRow(k, v)
                        }
                    }
                }
            }
        }
        .navigationTitle("Request #\(index)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { NetworkTrafficStore.shared.selectedIndex = index }
    }

    private func labelRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.caption).textSelection(.enabled)
        }
    }
}
