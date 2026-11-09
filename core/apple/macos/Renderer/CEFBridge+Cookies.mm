#import "CEFBridgeSupport.h"
#import "CEFBridge+Cookies.h"

#include <atomic>
#include <string.h>

// CEF's global cookie manager. Ownership follows the CEF C API: a struct passed into a
// CEF function hands CEF one reference, which CEF releases when it no longer needs the
// struct. A visitor's release therefore marks the end of its visit, which is the only
// completion signal CEF gives when the store holds no cookies at all.

static const NSTimeInterval kCookieOperationTimeout = 10;

// The shared message pump runs CEF at 60 Hz, and every cookie request waits for at least
// one pump turn. While a request is pending the pump runs every 4 ms instead, so a sync
// merge or renderer switch is bounded by CEF's own latency rather than by the frame rate.
// It uses a default-mode timer like the shared pump, so it never runs inside a nested
// modal loop that CEF itself may be running.
static NSInteger sPendingCookieOperations = 0;
static NSTimer *sCookiePump = nil;

static void BeginCookiePumpBoost(void) {
    if (sPendingCookieOperations++ > 0) { return; }
    sCookiePump = [NSTimer scheduledTimerWithTimeInterval:0.004 repeats:YES block:^(NSTimer *) {
        [CEFBridge doMessageLoopWork];
    }];
}

static void EndCookiePumpBoost(void) {
    if (--sPendingCookieOperations > 0) { return; }
    [sCookiePump invalidate];
    sCookiePump = nil;
}

/// State shared by one CEF request and its timeout. Touched only on the main thread: CEF's
/// UI thread is the main thread under the external message pump.
@interface CEFCookieOperation : NSObject
@property (nonatomic) BOOL accepted;
@property (nonatomic) BOOL succeeded;
@property (nonatomic) BOOL stopped;
@property (nonatomic) BOOL settled;
@property (nonatomic) BOOL boosted;
@property (nonatomic) NSInteger count;
@property (nonatomic) NSInteger visited;
@property (nonatomic) NSInteger expectedTotal;
@property (nonatomic, readonly) NSMutableArray<NSDictionary<NSString *, id> *> *cookies;
/// Keys to delete during a visit; nil for a plain enumeration.
@property (nonatomic, copy, nullable) NSSet<NSString *> *deleteKeys;
@property (nonatomic, copy, nullable) BOOL (^verdict)(CEFCookieOperation *operation);
@property (nonatomic, copy, nullable) void (^completion)(CEFCookieOperation *operation, BOOL complete);
@end

@implementation CEFCookieOperation

- (instancetype)init {
    if ((self = [super init])) {
        _cookies = [NSMutableArray array];
    }
    return self;
}

/// Reports the outcome once, after the CEF call that started the request has returned.
- (void)settle {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.settled) { return; }
        self.settled = YES;
        BOOL complete = self.accepted && !self.stopped && self.verdict != nil && self.verdict(self);
        [self deliver:complete];
    });
}

- (void)scheduleTimeout {
    self.boosted = YES;
    BeginCookiePumpBoost();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kCookieOperationTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.settled) { return; }
        self.settled = YES;
        self.stopped = YES;
        NSLog(@"[CEFBridge] global cookie operation timed out");
        [self deliver:NO];
    });
}

- (void)deliver:(BOOL)complete {
    if (self.boosted) {
        self.boosted = NO;
        EndCookiePumpBoost();
    }
    void (^completion)(CEFCookieOperation *, BOOL) = self.completion;
    self.completion = nil;
    self.verdict = nil;
    if (completion != nil) { completion(self, complete); }
}

@end

namespace {

template <typename API>
struct CookieHandle {
    API api;  // First member: CEF's base pointer is this struct's address.
    std::atomic<int> references;
    void *operation;  // Retained CEFCookieOperation.
};

template <typename API>
CookieHandle<API> *HandleFromBase(cef_base_ref_counted_t *base) {
    return reinterpret_cast<CookieHandle<API> *>(base);
}

template <typename API>
CEFCookieOperation *OperationOf(API *api) {
    return (__bridge CEFCookieOperation *)reinterpret_cast<CookieHandle<API> *>(api)->operation;
}

template <typename API>
void HandleAddRef(cef_base_ref_counted_t *base) {
    HandleFromBase<API>(base)->references.fetch_add(1, std::memory_order_relaxed);
}

template <typename API>
int HandleRelease(cef_base_ref_counted_t *base) {
    CookieHandle<API> *handle = HandleFromBase<API>(base);
    if (handle->references.fetch_sub(1, std::memory_order_acq_rel) != 1) { return 0; }
    CEFCookieOperation *operation = (__bridge_transfer CEFCookieOperation *)handle->operation;
    handle->operation = nullptr;
    delete handle;
    [operation settle];
    return 1;
}

template <typename API>
int HandleHasOneRef(cef_base_ref_counted_t *base) {
    return HandleFromBase<API>(base)->references.load(std::memory_order_acquire) == 1 ? 1 : 0;
}

template <typename API>
int HandleHasAtLeastOneRef(cef_base_ref_counted_t *base) {
    return HandleFromBase<API>(base)->references.load(std::memory_order_acquire) >= 1 ? 1 : 0;
}

template <typename API>
CookieHandle<API> *MakeHandle(CEFCookieOperation *operation) {
    CookieHandle<API> *handle = new CookieHandle<API>();
    memset(&handle->api, 0, sizeof(API));
    handle->api.base.size = sizeof(API);
    handle->api.base.add_ref = HandleAddRef<API>;
    handle->api.base.release = HandleRelease<API>;
    handle->api.base.has_one_ref = HandleHasOneRef<API>;
    handle->api.base.has_at_least_one_ref = HandleHasAtLeastOneRef<API>;
    handle->references.store(1, std::memory_order_relaxed);
    handle->operation = (__bridge_retained void *)operation;
    return handle;
}

BOOL Flag(id value) {
    return [value isKindOfClass:[NSNumber class]] && [value boolValue];
}

NSString *StringFrom(const cef_string_t &value) {
    if (value.str == nullptr || value.length == 0) { return @""; }
    return [[NSString alloc] initWithCharacters:(const unichar *)value.str length:value.length];
}

NSString *SameSiteName(cef_cookie_same_site_t value) {
    switch (value) {
        case CEF_COOKIE_SAME_SITE_UNSPECIFIED: return @"Unspecified";
        case CEF_COOKIE_SAME_SITE_NO_RESTRICTION: return @"None";
        case CEF_COOKIE_SAME_SITE_LAX_MODE: return @"Lax";
        case CEF_COOKIE_SAME_SITE_STRICT_MODE: return @"Strict";
        default: return nil;
    }
}

BOOL SameSiteValue(id name, cef_cookie_same_site_t *value) {
    if (![name isKindOfClass:[NSString class]]) { return NO; }
    if ([name isEqualToString:@"Unspecified"]) { *value = CEF_COOKIE_SAME_SITE_UNSPECIFIED; return YES; }
    if ([name isEqualToString:@"None"]) { *value = CEF_COOKIE_SAME_SITE_NO_RESTRICTION; return YES; }
    if ([name isEqualToString:@"Lax"]) { *value = CEF_COOKIE_SAME_SITE_LAX_MODE; return YES; }
    if ([name isEqualToString:@"Strict"]) { *value = CEF_COOKIE_SAME_SITE_STRICT_MODE; return YES; }
    return NO;
}

NSNumber *UnixSeconds(cef_basetime_t value) {
    cef_time_t decoded = {};
    double seconds = 0;
    if (value.val == 0 || !cef_time_from_basetime(value, &decoded) || !cef_time_to_doublet(&decoded, &seconds)) {
        return nil;
    }
    return @(seconds);
}

NSDictionary *CookieDictionary(const cef_cookie_t &cookie) {
    NSMutableDictionary *dict = [@{
        @"name": StringFrom(cookie.name),
        @"value": StringFrom(cookie.value),
        @"domain": StringFrom(cookie.domain),
        @"path": StringFrom(cookie.path),
        @"secure": @(cookie.secure != 0),
        @"httpOnly": @(cookie.httponly != 0),
    } mutableCopy];
    NSString *sameSite = SameSiteName(cookie.same_site);
    if (sameSite != nil) { dict[@"sameSite"] = sameSite; }
    NSNumber *expires = cookie.has_expires ? UnixSeconds(cookie.expires) : nil;
    if (expires != nil) { dict[@"expires"] = expires; }
    return dict;
}

NSString *KeyString(NSString *domain, NSString *path, NSString *name) {
    return [NSString stringWithFormat:@"%@\x1F%@\x1F%@", domain.lowercaseString, path, name];
}

int VisitCookie(cef_cookie_visitor_t *self, const cef_cookie_t *cookie, int, int total, int *deleteCookie) {
    if (deleteCookie != nullptr) { *deleteCookie = 0; }
    CEFCookieOperation *operation = OperationOf(self);
    if (operation.stopped) { return 0; }
    operation.expectedTotal = total;
    operation.visited += 1;
    if (cookie == nullptr) { return 1; }
    if (operation.deleteKeys != nil) {
        NSString *key = KeyString(StringFrom(cookie->domain), StringFrom(cookie->path), StringFrom(cookie->name));
        if ([operation.deleteKeys containsObject:key] && deleteCookie != nullptr) {
            *deleteCookie = 1;
            operation.count += 1;
        }
    } else {
        [operation.cookies addObject:CookieDictionary(*cookie)];
    }
    return 1;
}

void SetCookieComplete(cef_set_cookie_callback_t *self, int success) {
    CEFCookieOperation *operation = OperationOf(self);
    operation.succeeded = success != 0;
    [operation settle];
}

void DeleteCookiesComplete(cef_delete_cookies_callback_t *self, int deleted) {
    CEFCookieOperation *operation = OperationOf(self);
    operation.succeeded = YES;
    operation.count = deleted;
    [operation settle];
}

cef_cookie_manager_t *sTestingManager = nullptr;

/// A new reference to the global manager, or nullptr before CEF has initialized.
cef_cookie_manager_t *CopyGlobalManager() {
    if (sTestingManager != nullptr) {
        sTestingManager->base.add_ref(&sTestingManager->base);
        return sTestingManager;
    }
    return CEFBridgeIsCEFInitialized() ? cef_cookie_manager_get_global_manager(nullptr) : nullptr;
}

BOOL VisitWasComplete(CEFCookieOperation *operation) {
    return operation.visited == operation.expectedTotal;
}

/// Runs a full visit; `operation.deleteKeys` turns it into an exact delete.
void StartVisit(CEFCookieOperation *operation) {
    operation.verdict = ^BOOL(CEFCookieOperation *op) { return VisitWasComplete(op); };
    cef_cookie_manager_t *manager = CopyGlobalManager();
    if (manager == nullptr || manager->visit_all_cookies == nullptr) {
        if (manager != nullptr) { manager->base.release(&manager->base); }
        [operation settle];
        return;
    }
    [operation scheduleTimeout];
    CookieHandle<cef_cookie_visitor_t> *visitor = MakeHandle<cef_cookie_visitor_t>(operation);
    visitor->api.visit = VisitCookie;
    operation.accepted = manager->visit_all_cookies(manager, &visitor->api) != 0;
    manager->base.release(&manager->base);
}

cef_cookie_t MakeCookie(NSDictionary<NSString *, id> *source, NSString *domain, BOOL secure,
                        cef_cookie_same_site_t sameSite) {
    cef_cookie_t cookie = {};
    cookie.size = sizeof(cookie);
    NSString *path = [source[@"path"] isKindOfClass:[NSString class]] ? source[@"path"] : @"/";
    cookie.name = CEFBridgeStringCreate(source[@"name"]);
    cookie.value = CEFBridgeStringCreate([source[@"value"] isKindOfClass:[NSString class]] ? source[@"value"] : @"");
    // An empty domain makes CEF create a host-only cookie for the URL's host.
    cookie.domain = CEFBridgeStringCreate([domain hasPrefix:@"."] ? domain : @"");
    cookie.path = CEFBridgeStringCreate(path.length > 0 ? path : @"/");
    cookie.secure = secure ? 1 : 0;
    cookie.httponly = Flag(source[@"httpOnly"]) ? 1 : 0;
    cookie.same_site = sameSite;
    cookie.priority = CEF_COOKIE_PRIORITY_MEDIUM;
    id expires = source[@"expires"];
    if ([expires isKindOfClass:[NSNumber class]]) {
        cookie.has_expires = 1;
        cookie.expires = CEFBridgeBaseTimeFromDate([NSDate dateWithTimeIntervalSince1970:[expires doubleValue]]);
    }
    return cookie;
}

void ClearCookie(cef_cookie_t *cookie) {
    CEFBridgeStringClear(&cookie->name);
    CEFBridgeStringClear(&cookie->value);
    CEFBridgeStringClear(&cookie->domain);
    CEFBridgeStringClear(&cookie->path);
}

/// The URL CEF validates the cookie against: scheme from Secure, as DevTools does.
NSString *CookieURL(NSString *domain, NSString *path, BOOL secure) {
    NSString *host = [domain hasPrefix:@"."] ? [domain substringFromIndex:1] : domain;
    if ([host containsString:@":"] && ![host hasPrefix:@"["]) { host = [NSString stringWithFormat:@"[%@]", host]; }
    NSString *urlPath = [path hasPrefix:@"/"] ? path : @"/";
    return [NSString stringWithFormat:@"%@://%@%@", secure ? @"https" : @"http", host, urlPath];
}

}  // namespace

void CEFBridgeUseCookieManagerForTesting(cef_cookie_manager_t *manager) {
    sTestingManager = manager;
}

@implementation CEFBridge (Cookies)

+ (BOOL)isGlobalCookieStoreAvailable {
    return sTestingManager != nullptr || CEFBridgeIsCEFInitialized();
}

+ (void)visitGlobalCookiesWithCompletion:(void (^)(BOOL complete, NSArray<NSDictionary<NSString *, id> *> *cookies))completion {
    CEFCookieOperation *operation = [CEFCookieOperation new];
    void (^reply)(BOOL, NSArray<NSDictionary<NSString *, id> *> *) = [completion copy];
    operation.completion = ^(CEFCookieOperation *op, BOOL complete) { reply(complete, [op.cookies copy]); };
    StartVisit(operation);
}

+ (void)setGlobalCookie:(NSDictionary<NSString *, id> *)cookie completion:(void (^)(BOOL success))completion {
    CEFCookieOperation *operation = [CEFCookieOperation new];
    void (^reply)(BOOL) = [completion copy];
    operation.completion = ^(CEFCookieOperation *, BOOL complete) { reply(complete); };
    operation.verdict = ^BOOL(CEFCookieOperation *op) { return op.succeeded; };

    NSString *name = [cookie[@"name"] isKindOfClass:[NSString class]] ? cookie[@"name"] : nil;
    NSString *domain = [cookie[@"domain"] isKindOfClass:[NSString class]] ? [cookie[@"domain"] lowercaseString] : nil;
    NSString *path = [cookie[@"path"] isKindOfClass:[NSString class]] ? cookie[@"path"] : @"/";
    cef_cookie_same_site_t sameSite = CEF_COOKIE_SAME_SITE_UNSPECIFIED;
    BOOL secure = Flag(cookie[@"secure"]);
    cef_cookie_manager_t *manager = CopyGlobalManager();
    if (name.length == 0 || domain.length <= ([domain hasPrefix:@"."] ? 1 : 0) || !SameSiteValue(cookie[@"sameSite"], &sameSite) ||
        manager == nullptr || manager->set_cookie == nullptr) {
        if (manager != nullptr) { manager->base.release(&manager->base); }
        [operation settle];
        return;
    }

    [operation scheduleTimeout];
    cef_cookie_t value = MakeCookie(cookie, domain, secure, sameSite);
    cef_string_t url = CEFBridgeStringCreate(CookieURL(domain, path, secure));
    CookieHandle<cef_set_cookie_callback_t> *callback = MakeHandle<cef_set_cookie_callback_t>(operation);
    callback->api.on_complete = SetCookieComplete;
    operation.accepted = manager->set_cookie(manager, &url, &value, &callback->api) != 0;
    CEFBridgeStringClear(&url);
    ClearCookie(&value);
    manager->base.release(&manager->base);
}

+ (void)deleteGlobalCookiesMatching:(NSArray<NSDictionary<NSString *, NSString *> *> *)keys
                         completion:(void (^)(BOOL complete, NSInteger deleted))completion {
    CEFCookieOperation *operation = [CEFCookieOperation new];
    NSMutableSet<NSString *> *wanted = [NSMutableSet setWithCapacity:keys.count];
    for (NSDictionary<NSString *, NSString *> *key in keys) {
        NSString *path = [key[@"path"] isKindOfClass:[NSString class]] && key[@"path"].length > 0 ? key[@"path"] : @"/";
        if ([key[@"domain"] isKindOfClass:[NSString class]] && [key[@"name"] isKindOfClass:[NSString class]]) {
            [wanted addObject:KeyString(key[@"domain"], path, key[@"name"])];
        }
    }
    operation.deleteKeys = wanted;
    void (^reply)(BOOL, NSInteger) = [completion copy];
    operation.completion = ^(CEFCookieOperation *op, BOOL complete) { reply(complete, op.count); };
    StartVisit(operation);
}

+ (void)deleteAllGlobalCookiesWithCompletion:(void (^)(BOOL success, NSInteger deleted))completion {
    CEFCookieOperation *operation = [CEFCookieOperation new];
    void (^reply)(BOOL, NSInteger) = [completion copy];
    operation.completion = ^(CEFCookieOperation *op, BOOL complete) { reply(complete, op.count); };
    operation.verdict = ^BOOL(CEFCookieOperation *op) { return op.succeeded; };
    cef_cookie_manager_t *manager = CopyGlobalManager();
    if (manager == nullptr || manager->delete_cookies == nullptr) {
        if (manager != nullptr) { manager->base.release(&manager->base); }
        [operation settle];
        return;
    }
    [operation scheduleTimeout];
    CookieHandle<cef_delete_cookies_callback_t> *callback = MakeHandle<cef_delete_cookies_callback_t>(operation);
    callback->api.on_complete = DeleteCookiesComplete;
    operation.accepted = manager->delete_cookies(manager, nullptr, nullptr, &callback->api) != 0;
    manager->base.release(&manager->base);
}

@end
