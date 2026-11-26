import AuthenticationServices
import SwiftUI

final class CredentialProviderViewController: ASCredentialProviderViewController {
    private var store: WebsitePasswordStore? {
        guard let id = Bundle.main.bundleIdentifier, id.hasSuffix(".autofill") else { return nil }
        return .sharedWithProvider(hostID: String(id.dropLast(".autofill".count)))
    }

    override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 250)) }

    override func prepareInterfaceForExtensionConfiguration() {
        Task {
            guard let store else { cancel(.failed); return }
            do {
                try await WebsitePasswordSuggestions.replace(from: store)
                extensionContext.completeExtensionConfigurationRequest()
            } catch { cancel(.failed) }
        }
    }

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        do {
            guard let store else { cancel(.failed); return }
            let logins = try store.logins().filter { login in
                serviceIdentifiers.contains { WebsitePasswordSuggestions.matches(login, service: $0) }
            }
            view = NSHostingView(rootView: VStack(alignment: .leading) {
                if logins.isEmpty { Text("No saved Kelpie password for this website.") }
                List(logins) { login in
                    Button("\(login.username) — \(login.origin)") { self.provide(login) }
                }
                Button("Cancel") { self.cancel(.userCanceled) }
            }.padding().frame(minWidth: 360, minHeight: 180))
        } catch { cancel(.failed) }
    }

    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        resolve(credentialRequest)
    }

    override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        resolve(credentialRequest)
    }

    private func resolve(_ request: any ASCredentialRequest) {
        guard let identity = request.credentialIdentity as? ASPasswordCredentialIdentity,
              let record = identity.recordIdentifier, let login = WebsitePasswordStore.Login(account: record),
              identity.user == login.username, WebsitePasswordSuggestions.matches(login, service: identity.serviceIdentifier)
        else { cancel(.credentialIdentityNotFound); return }
        provide(login)
    }

    private func provide(_ login: WebsitePasswordStore.Login) {
        guard let store else { cancel(.failed); return }
        do {
            let password = try store.password(for: login)
            extensionContext.completeRequest(withSelectedCredential: ASPasswordCredential(user: login.username, password: password), completionHandler: nil)
        } catch let failure as WebsitePasswordStore.Failure where failure.status == errSecItemNotFound {
            cancel(.credentialIdentityNotFound)
        } catch { cancel(.failed) }
    }

    private func cancel(_ code: ASExtensionError.Code) {
        extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: code.rawValue))
    }
}
