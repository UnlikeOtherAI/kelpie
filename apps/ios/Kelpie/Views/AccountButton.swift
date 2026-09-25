import SwiftUI

struct AccountButton: View {
    @ObservedObject private var account = UOAAccount.shared
    @ObservedObject private var bookmarks = BookmarkStore.shared
    @State private var showMenu = false

    var body: some View {
        Button {
            if account.profile == nil && !account.signingIn { account.signIn() }
            else { showMenu = true }
        } label: {
            Group {
                if let avatar = account.avatar {
                    Image(uiImage: avatar).resizable().scaledToFill()
                        .frame(width: 32, height: 32).clipShape(Circle())
                } else {
                    Image(systemName: "person.crop.circle").font(.system(size: 22))
                }
            }
            .frame(width: 44, height: 44)
            .modifier(BrowserGlass())
        }
        .accessibilityLabel(account.profile == nil ? "Login/register" : "Account")
        .accessibilityIdentifier("browser.account")
        .confirmationDialog("Account", isPresented: $showMenu, titleVisibility: .visible) {
            if account.signingIn {
                Button("Cancel login", action: account.cancelSignIn)
            } else {
                Button("Refresh favourites", action: bookmarks.refreshAccountBookmarks)
                Button("Sign out", role: .destructive, action: account.signOut)
            }
        } message: {
            Text(bookmarks.syncError ?? account.profile?.name ?? account.profile?.email ?? "")
        }
        .alert("Login", isPresented: Binding(get: { account.error != nil }, set: { if !$0 { account.error = nil } })) {
            Button("OK") { account.error = nil }
        } message: {
            Text(account.error ?? "")
        }
    }
}
