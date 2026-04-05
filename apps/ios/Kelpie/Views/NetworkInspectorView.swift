import SwiftUI

/// Charles-style network traffic inspector.
struct NetworkInspectorView: View {
    @ObservedObject var store = NetworkTrafficStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var methodFilter: String?
    @State private var categoryFilter: String?
    @State private var initiatorFilter: String?
    @State private var searchText = ""

    private let methodOptions = ["GET", "POST", "PUT", "DELETE"]
    private let categoryOptions = ["HTML", "JSON", "JS", "CSS", "Image", "Font", "XML", "Other"]
    private let initiatorOptions = ["browser", "js"]

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
                        Text("Network traffic will appear here as pages load, including the page document itself.")
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
        if let i = initiatorFilter { result = result.filter { $0.element.initiator == i } }
        if !searchText.isEmpty { result = result.filter { $0.element.url.localizedCaseInsensitiveContains(searchText) } }
        return result
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Method", selection: selectedMethodBinding) {
                Text("All Methods").tag("ALL")
                ForEach(methodOptions, id: \.self) { method in
                    Text(method).tag(method)
                }
            }
            .pickerStyle(.menu)
            Picker("Category", selection: selectedCategoryBinding) {
                Text("All Types").tag("ALL")
                ForEach(categoryOptions, id: \.self) { cat in
                    Text(cat).tag(cat)
                }
            }
            .pickerStyle(.menu)
            Picker("Source", selection: selectedInitiatorBinding) {
                Text("All Sources").tag("ALL")
                Text("Browser").tag("browser")
                Text("JS (fetch/XHR)").tag("js")
            }
            .pickerStyle(.menu)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }

    private var selectedMethodBinding: Binding<String> {
        Binding(
            get: { methodFilter ?? "ALL" },
            set: { methodFilter = $0 == "ALL" ? nil : $0 }
        )
    }

    private var selectedCategoryBinding: Binding<String> {
        Binding(
            get: { categoryFilter ?? "ALL" },
            set: { categoryFilter = $0 == "ALL" ? nil : $0 }
        )
    }

    private var selectedInitiatorBinding: Binding<String> {
        Binding(
            get: { initiatorFilter ?? "ALL" },
            set: { initiatorFilter = $0 == "ALL" ? nil : $0 }
        )
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
