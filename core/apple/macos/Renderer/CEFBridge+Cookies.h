#import "CEFBridge.h"

NS_ASSUME_NONNULL_BEGIN

/// Cookie access to the active Chromium request context, implemented in CEFBridge+Cookies.mm.
///
/// Standalone browsers use the global context. Embedded browsers use the selected
/// profile's persistent context and require an active profile for cookie access.
/// The manager reports HttpOnly, Secure, SameSite and expiry without a browser view
/// or DevTools session. Completions run on the main queue exactly once.
///
/// Cookie dictionaries use: `name`, `value`, `domain` (a leading dot marks a domain
/// cookie; no dot is host-only), `path`, `secure`, `httpOnly`, `sameSite`
/// (`Strict`, `Lax`, `None` or `Unspecified`; absent when CEF reports an unknown value)
/// and `expires` (Unix seconds as a double; absent for a session cookie).
@interface CEFBridge (Cookies)

/// YES when the active request context can supply its cookie manager.
+ (BOOL)isGlobalCookieStoreAvailable;

/// Visits every cookie. `complete` is YES only when CEF finished the visit; a refused
/// visit or a timeout reports NO with whatever was seen, never an invented empty store.
+ (void)visitGlobalCookiesWithCompletion:(void (^)(BOOL complete, NSArray<NSDictionary<NSString *, id> *> *cookies))completion;

/// Sets one cookie through `SetCookie` with its exact attributes.
+ (void)setGlobalCookie:(NSDictionary<NSString *, id> *)cookie
             completion:(void (^)(BOOL success))completion;

/// Deletes every cookie whose domain (ignoring case), path and name equal one of `keys`
/// (dictionaries with `domain`, `path` and `name`) in one visit. `complete` is YES only
/// when CEF finished that visit.
+ (void)deleteGlobalCookiesMatching:(NSArray<NSDictionary<NSString *, NSString *> *> *)keys
                         completion:(void (^)(BOOL complete, NSInteger deleted))completion;

/// Deletes every cookie in the store.
+ (void)deleteAllGlobalCookiesWithCompletion:(void (^)(BOOL success, NSInteger deleted))completion;

@end

NS_ASSUME_NONNULL_END
