#import "CEFBridge.h"

NS_ASSUME_NONNULL_BEGIN

/// Cookie operations implemented in CEFBridge+Cookies.mm.
///
/// These methods are part of the bridge's public surface and were factored
/// into a category so the primary `CEFBridge.mm` translation unit stays
/// within the project's 500-line file limit.
@interface CEFBridge (Cookies)

/// Get all cookies as an array of dictionaries.
- (void)getAllCookiesWithCompletion:(void (^ _Nonnull)(NSArray<NSDictionary *> *cookies))completion;

/// Set a cookie.
- (void)setCookieName:(NSString *)name
                value:(NSString *)value
                  url:(NSString *)url
               domain:(NSString *)domain
                 path:(NSString *)path
             httpOnly:(BOOL)httpOnly
               secure:(BOOL)secure
              expires:(NSDate * _Nullable)expires
           completion:(void (^ _Nonnull)(BOOL success))completion;

/// Set a cookie via Chrome DevTools Protocol.
- (void)setCookieViaCDP:(NSString *)name
                  value:(NSString *)value
                 domain:(NSString *)domain
                   path:(NSString *)path
               httpOnly:(BOOL)httpOnly
                 secure:(BOOL)secure
               sameSite:(NSString * _Nullable)sameSite
                expires:(NSDate * _Nullable)expires
             completion:(void (^ _Nonnull)(BOOL success))completion;

/// Get cookies via Chrome DevTools Protocol.
- (void)getAllCookiesViaCDPWithCompletion:(void (^ _Nonnull)(BOOL success, NSArray<NSDictionary *> *cookies))completion;

/// Delete a cookie via Chrome DevTools Protocol.
- (void)deleteCookieViaCDP:(NSString *)name
                    domain:(NSString *)domain
                      path:(NSString *)path
                completion:(void (^ _Nonnull)(BOOL success))completion;

/// Delete all current-context cookies via Chrome DevTools Protocol.
- (void)deleteAllCookiesViaCDPWithCompletion:(void (^ _Nonnull)(BOOL success, NSInteger deleted))completion;

/// Delete all cookies.
- (void)deleteAllCookiesWithCompletion:(void (^ _Nonnull)(NSInteger deleted))completion;

/// Flush the cookie store to ensure all pending set/delete operations are committed.
- (void)flushCookieStoreWithCompletion:(void (^ _Nonnull)(void))completion;

@end

NS_ASSUME_NONNULL_END
