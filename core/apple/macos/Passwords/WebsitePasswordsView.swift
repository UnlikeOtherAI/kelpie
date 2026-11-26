import SwiftUI
import AuthenticationServices

struct WebsitePasswordsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logins: [WebsitePasswordStore.Login] = []
    @State private var selected: WebsitePasswordStore.Login?
    @State private var confirming = false
    @State private var failure: String?
    private let store = WebsitePasswordStore()

    var body: some View {
        VStack(alignment: .leading) {
            Text("Saved Passwords").font(.title2)
            if let failure { Text(failure).foregroundStyle(.red) }
            List {
                if logins.isEmpty && failure == nil { Text("No saved passwords").foregroundStyle(.secondary) }
                ForEach(logins) { login in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(login.origin)
                            Text(login.username).foregroundStyle(.secondary)
                        }
                        Spacer()
                        button("Delete", id: "passwords.delete") { confirm(login) }
                    }
                }
            }
            if store.accessGroup != nil {
                button("AutoFill Settings…", id: "passwords.autofill") {
                    Task {
                        do {
                            try await ASSettingsHelper.openCredentialProviderAppSettings()
                        } catch { failure = error.localizedDescription }
                    }
                }
            }
            HStack {
                if !logins.isEmpty { button("Clear All…", id: "passwords.clear") { confirm(nil) } }
                Spacer()
                button("Done", id: "passwords.done", action: dismiss.callAsFunction)
            }
        }
        .padding()
        .frame(width: 460, height: 420)
        .onAppear { refresh() }
        .alert(selected == nil ? "Clear all passwords saved by Kelpie?" : "Delete this password?", isPresented: $confirming) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                do {
                    try store.delete(selected)
                    WebsitePasswordSuggestions.refresh(from: store)
                    refresh()
                } catch { failure = error.localizedDescription }
            }
        } message: {
            if let selected { Text("\(selected.username) at \(selected.origin)") }
        }
    }

    private func button(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        AppKitPairingButton(title: title, style: .normal, accessibilityID: id, action: action)
            .fixedSize()
    }

    private func confirm(_ login: WebsitePasswordStore.Login?) {
        selected = login
        confirming = true
    }

    private func refresh() {
        do {
            logins = try store.logins()
            failure = nil
        } catch { failure = error.localizedDescription }
    }
}
