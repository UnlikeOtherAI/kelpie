#import "CEFBridge_Internal.h"
#import "CEFBridge+Cookies.h"

// Cookie operations exposed by CEFBridge. These methods forward to either
// CEFBridgeSupport's cookie manager helpers or the Chrome DevTools Protocol
// helpers; the bridge itself just acquires/releases CEF handles.

@implementation CEFBridge (Cookies)

- (void)getAllCookiesWithCompletion:(void (^)(NSArray<NSDictionary *> *cookies))completion {
    CEFBridgeVisitAllCookies(_cookieManager, completion);
}

- (void)setCookieName:(NSString *)name
                value:(NSString *)value
                  url:(NSString *)url
               domain:(NSString *)domain
                 path:(NSString *)path
             httpOnly:(BOOL)httpOnly
               secure:(BOOL)secure
              expires:(NSDate * _Nullable)expires
           completion:(void (^)(BOOL success))completion {
    CEFBridgeSetCookie(_cookieManager, name, value, url, domain, path, httpOnly, secure, expires, completion);
}

- (void)setCookieViaCDP:(NSString *)name
                  value:(NSString *)value
                 domain:(NSString *)domain
                   path:(NSString *)path
               httpOnly:(BOOL)httpOnly
                 secure:(BOOL)secure
               sameSite:(NSString * _Nullable)sameSite
                expires:(NSDate * _Nullable)expires
             completion:(void (^)(BOOL success))completion {
    cef_browser_host_t *host = CEFBridgeCopyBrowserHost([self activeBrowser]);
    if (host == nullptr) {
        if (completion != nil) {
            completion(NO);
        }
        return;
    }
    CEFBridgeSetCookieViaCDP(host, name, value, domain, path, httpOnly, secure, sameSite, expires, completion);
    host->base.release(&host->base);
}

- (void)getAllCookiesViaCDPWithCompletion:(void (^)(BOOL success, NSArray<NSDictionary *> *cookies))completion {
    cef_browser_host_t *host = CEFBridgeCopyBrowserHost([self activeBrowser]);
    if (host == nullptr) {
        if (completion != nil) {
            completion(NO, @[]);
        }
        return;
    }
    CEFBridgeGetCookiesViaCDP(host, completion);
    host->base.release(&host->base);
}

- (void)deleteCookieViaCDP:(NSString *)name
                    domain:(NSString *)domain
                      path:(NSString *)path
                completion:(void (^)(BOOL success))completion {
    cef_browser_host_t *host = CEFBridgeCopyBrowserHost([self activeBrowser]);
    if (host == nullptr) {
        if (completion != nil) {
            completion(NO);
        }
        return;
    }
    CEFBridgeDeleteCookieViaCDP(host, name, domain, path, completion);
    host->base.release(&host->base);
}

- (void)deleteAllCookiesViaCDPWithCompletion:(void (^)(BOOL success, NSInteger deleted))completion {
    cef_browser_host_t *host = CEFBridgeCopyBrowserHost([self activeBrowser]);
    if (host == nullptr) {
        if (completion != nil) {
            completion(NO, 0);
        }
        return;
    }
    CEFBridgeDeleteAllCookiesViaCDP(host, completion);
    host->base.release(&host->base);
}

- (void)deleteAllCookiesWithCompletion:(void (^)(NSInteger deleted))completion {
    CEFBridgeDeleteAllCookies(_cookieManager, completion);
}

- (void)flushCookieStoreWithCompletion:(void (^)(void))completion {
    CEFBridgeFlushCookieStore(_cookieManager, completion);
}

@end
