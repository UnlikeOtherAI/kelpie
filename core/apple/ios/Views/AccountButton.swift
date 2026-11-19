import SwiftUI

struct AccountButton: View {
    @ObservedObject private var account = UOAAccount.shared
    @ObservedObject private var bookmarks = BookmarkStore.shared
    @State private var showMenu = false

    var body: some View {
        Button {
            if account.profile == nil && !account.signingIn { account.signIn() } else { showMenu = true }
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
            AccountMenuActions()
        } message: {
            Text(bookmarks.syncError ?? account.profile?.name ?? account.profile?.email ?? "")
        }
    }
}

struct AccountMenuItems: View {
    @ObservedObject private var account = UOAAccount.shared
    @ObservedObject private var bookmarks = BookmarkStore.shared

    var body: some View {
        if account.signingIn {
            AccountMenuActions()
        } else if let profile = account.profile {
            Menu {
                if let error = bookmarks.syncError { Text(error) }
                AccountMenuActions()
            } label: {
                Label {
                    Text(profile.name ?? profile.email)
                } icon: {
                    if let avatar = account.avatar {
                        Image(uiImage: avatar)
                    } else {
                        Image(systemName: "person.crop.circle")
                    }
                }
            }
            .accessibilityIdentifier("browser.account.menu")
        } else {
            Button(action: account.signIn) { Label("Login/register", systemImage: "person.crop.circle") }
                .accessibilityIdentifier("browser.account.menu")
        }
    }
}

private struct AccountMenuActions: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject private var account = UOAAccount.shared
    @ObservedObject private var bookmarks = BookmarkStore.shared

    var body: some View {
        if account.signingIn {
            Button("Cancel login", action: account.cancelSignIn)
        } else {
            Button("Refresh favourites", action: bookmarks.refreshAccountBookmarks)
            Button("Sign out", role: .destructive, action: account.signOut)
            if account.profile != nil, let url = URL(string: UOATransport.origin + "/auth/delete-account") {
                Button("Delete account") { openURL(url) }
                    .accessibilityIdentifier("browser.account.delete")
            }
        }
    }
}
