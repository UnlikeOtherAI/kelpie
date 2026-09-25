import SwiftUI

struct AccountButton: View {
    let tintColor: NSColor
    @ObservedObject private var account = UOAAccount.shared
    @ObservedObject private var bookmarks = BookmarkStore.shared
    @State private var isPresented = false

    var body: some View {
        ZStack {
            if let avatar = account.avatar {
                Image(nsImage: avatar).resizable().scaledToFill()
            } else {
                Circle().fill(Color(nsColor: tintColor).opacity(0.08))
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 24)).foregroundStyle(Color(nsColor: tintColor))
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color(nsColor: tintColor).opacity(0.18), lineWidth: 0.5))
        .overlay(AppKitInvisibleButton(accessibilityID: "browser.account", accessibilityLabel: "UOA account", isEnabled: true) {
            isPresented.toggle()
        })
        .overlay(alignment: .bottomTrailing) {
            if account.error != nil || bookmarks.syncError != nil {
                Circle().fill(.red).frame(width: 7, height: 7).allowsHitTesting(false)
            }
        }
        .onChange(of: isPresented) { _, open in if open { bookmarks.refreshAccountBookmarks() } }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("UnlikeOtherAI account").font(.headline)
                if let profile = account.profile {
                    Text(profile.name ?? profile.email).font(.subheadline.weight(.semibold))
                    if profile.name != nil { Text(profile.email).foregroundStyle(.secondary) }
                    Text(bookmarks.isSyncing ? "Syncing favourites…" : "Favourites saved to your UOA account")
                        .font(.caption).foregroundStyle(.secondary)
                    action("Refresh favourites", id: "refresh", action: bookmarks.refreshAccountBookmarks)
                    action("Sign out", id: "sign-out", action: account.signOut)
                } else if account.signingIn {
                    Text("Complete sign-in in the UOA window.").foregroundStyle(.secondary)
                    action("Cancel sign-in", id: "cancel", action: account.cancelSignIn)
                } else {
                    Text("Sign in to use your account favourites on this Mac.").foregroundStyle(.secondary)
                    action("Sign in with UOA", id: "sign-in", action: account.signIn)
                }
                if let error = account.error ?? bookmarks.syncError {
                    Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18).frame(width: 300)
        }
    }

    private func action(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Text(title).frame(maxWidth: .infinity, alignment: .leading).frame(height: 28)
            .contentShape(Rectangle())
            .overlay(AppKitInvisibleButton(accessibilityID: "browser.account.\(id)", accessibilityLabel: title, isEnabled: true, action: action))
    }
}
