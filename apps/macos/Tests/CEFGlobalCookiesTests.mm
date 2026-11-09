#if !defined(KELPIE_WEBKIT_ONLY)
#import <XCTest/XCTest.h>
#import "CEFBridgeSupport.h"
#import "CEFBridge+Cookies.h"

#include <algorithm>
#include <atomic>
#include <string>
#include <vector>

namespace {

std::string Text(const cef_string_t &value) {
    NSString *string = value.str == nullptr ? @"" : [[NSString alloc] initWithCharacters:(const unichar *)value.str length:value.length];
    return string.UTF8String;
}

void Assign(cef_string_t *target, const std::string &value) {
    cef_string_utf8_to_utf16(value.c_str(), value.size(), target);
}

struct StoredCookie {
    std::string name, value, domain, path;
    bool secure = false, httpOnly = false, hasExpires = false;
    double expires = 0;
    cef_cookie_same_site_t sameSite = CEF_COOKIE_SAME_SITE_UNSPECIFIED;
};

/// A CEF cookie manager in memory. Like CEF it answers asynchronously on the main thread,
/// consumes the reference passed with each callback, and never visits an empty store.
struct FakeManager {
    cef_cookie_manager_t api = {};
    std::atomic<int> references{1};
    std::vector<StoredCookie> cookies;
    std::vector<std::string> setURLs;
    std::vector<size_t> setSizes;
    bool refuseVisits = false;

    FakeManager() {
        api.base.size = sizeof(api);
        api.base.add_ref = [](cef_base_ref_counted_t *base) { Self(base)->references++; };
        api.base.release = [](cef_base_ref_counted_t *base) -> int { return --Self(base)->references == 0; };
        api.base.has_one_ref = [](cef_base_ref_counted_t *base) -> int { return Self(base)->references == 1; };
        api.base.has_at_least_one_ref = [](cef_base_ref_counted_t *base) -> int { return Self(base)->references > 0; };
        api.visit_all_cookies = VisitAll;
        api.set_cookie = Set;
        api.delete_cookies = DeleteAll;
    }

    static FakeManager *Self(cef_base_ref_counted_t *base) { return reinterpret_cast<FakeManager *>(base); }
    static FakeManager *Self(cef_cookie_manager_t *manager) { return reinterpret_cast<FakeManager *>(manager); }

    static int VisitAll(cef_cookie_manager_t *self, cef_cookie_visitor_t *visitor) {
        FakeManager *fake = Self(self);
        if (fake->refuseVisits) {
            visitor->base.release(&visitor->base);
            return 0;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            std::vector<StoredCookie> kept;
            const int total = (int)fake->cookies.size();
            for (int index = 0; index < total; index++) {
                const StoredCookie &stored = fake->cookies[index];
                cef_cookie_t cookie = {};
                cookie.size = sizeof(cookie);
                Assign(&cookie.name, stored.name);
                Assign(&cookie.value, stored.value);
                Assign(&cookie.domain, stored.domain);
                Assign(&cookie.path, stored.path);
                cookie.secure = stored.secure;
                cookie.httponly = stored.httpOnly;
                cookie.same_site = stored.sameSite;
                if (stored.hasExpires) {
                    cookie.has_expires = 1;
                    cookie.expires = CEFBridgeBaseTimeFromDate([NSDate dateWithTimeIntervalSince1970:stored.expires]);
                }
                int remove = 0;
                visitor->visit(visitor, &cookie, index, total, &remove);
                if (!remove) { kept.push_back(stored); }
                cef_string_clear(&cookie.name);
                cef_string_clear(&cookie.value);
                cef_string_clear(&cookie.domain);
                cef_string_clear(&cookie.path);
            }
            fake->cookies = kept;
            visitor->base.release(&visitor->base);
        });
        return 1;
    }

    static int Set(cef_cookie_manager_t *self, const cef_string_t *url, const cef_cookie_t *cookie, cef_set_cookie_callback_t *callback) {
        FakeManager *fake = Self(self);
        fake->setURLs.push_back(Text(*url));
        fake->setSizes.push_back(cookie->size);
        StoredCookie stored;
        stored.name = Text(cookie->name);
        stored.value = Text(cookie->value);
        // CEF makes an empty domain a host-only cookie for the URL's host.
        std::string host = Text(*url).substr(Text(*url).find("://") + 3);
        host = host.substr(0, host.find('/'));
        stored.domain = cookie->domain.length == 0 ? host : Text(cookie->domain);
        stored.path = Text(cookie->path);
        stored.secure = cookie->secure;
        stored.httpOnly = cookie->httponly;
        stored.sameSite = cookie->same_site;
        stored.hasExpires = cookie->has_expires;
        if (cookie->has_expires) {
            cef_time_t decoded = {};
            cef_time_from_basetime(cookie->expires, &decoded);
            cef_time_to_doublet(&decoded, &stored.expires);
        }
        // Chromium refuses SameSite=None without Secure.
        const bool accepted = !(stored.sameSite == CEF_COOKIE_SAME_SITE_NO_RESTRICTION && !stored.secure);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (accepted) {
                auto &all = fake->cookies;
                all.erase(std::remove_if(all.begin(), all.end(), [&](const StoredCookie &existing) {
                    return existing.name == stored.name && existing.domain == stored.domain && existing.path == stored.path;
                }), all.end());
                fake->cookies.push_back(stored);
            }
            callback->on_complete(callback, accepted);
            callback->base.release(&callback->base);
        });
        return 1;
    }

    static int DeleteAll(cef_cookie_manager_t *self, const cef_string_t *, const cef_string_t *, cef_delete_cookies_callback_t *callback) {
        FakeManager *fake = Self(self);
        dispatch_async(dispatch_get_main_queue(), ^{
            const int deleted = (int)fake->cookies.size();
            fake->cookies.clear();
            callback->on_complete(callback, deleted);
            callback->base.release(&callback->base);
        });
        return 1;
    }
};

}  // namespace

@interface CEFGlobalCookiesTests : XCTestCase
@end

@implementation CEFGlobalCookiesTests {
    FakeManager *_manager;
}

- (void)setUp {
    _manager = new FakeManager();
    CEFBridgeUseCookieManagerForTesting(&_manager->api);
}

- (void)tearDown {
    CEFBridgeUseCookieManagerForTesting(nullptr);
    XCTAssertTrue(_manager->references.load() == 1, @"Every manager reference the bridge took was released");
    delete _manager;
}

- (NSArray<NSDictionary *> *)visit:(BOOL *)complete {
    XCTestExpectation *done = [self expectationWithDescription:@"visit"];
    __block NSArray<NSDictionary *> *result = nil;
    __block BOOL finished = NO;
    [CEFBridge visitGlobalCookiesWithCompletion:^(BOOL ok, NSArray<NSDictionary<NSString *, id> *> *cookies) {
        finished = ok;
        result = cookies;
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:5];
    *complete = finished;
    return result;
}

- (BOOL)set:(NSDictionary *)cookie {
    XCTestExpectation *done = [self expectationWithDescription:@"set"];
    __block BOOL stored = NO;
    [CEFBridge setGlobalCookie:cookie completion:^(BOOL success) {
        stored = success;
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:5];
    return stored;
}

- (void)testAnEmptyStoreIsACompleteVisitSignalledByRelease {
    BOOL complete = NO;
    NSArray *cookies = [self visit:&complete];
    XCTAssertTrue(complete);
    XCTAssertEqual(cookies.count, 0u);
}

- (void)testARefusedVisitIsIncompleteNeverAnEmptyStore {
    _manager->refuseVisits = true;
    BOOL complete = YES;
    [self visit:&complete];
    XCTAssertFalse(complete);
}

- (void)testVisitReportsRealAttributes {
    StoredCookie cookie;
    cookie.name = "sid";
    cookie.value = "secret";
    cookie.domain = ".example.test";
    cookie.path = "/account";
    cookie.secure = true;
    cookie.httpOnly = true;
    cookie.sameSite = CEF_COOKIE_SAME_SITE_LAX_MODE;
    cookie.hasExpires = true;
    cookie.expires = 2000000000;
    _manager->cookies.push_back(cookie);

    BOOL complete = NO;
    NSArray<NSDictionary *> *cookies = [self visit:&complete];
    XCTAssertTrue(complete);
    XCTAssertEqualObjects(cookies.firstObject[@"domain"], @".example.test");
    XCTAssertEqualObjects(cookies.firstObject[@"path"], @"/account");
    XCTAssertEqualObjects(cookies.firstObject[@"httpOnly"], @YES);
    XCTAssertEqualObjects(cookies.firstObject[@"secure"], @YES);
    XCTAssertEqualObjects(cookies.firstObject[@"sameSite"], @"Lax");
    XCTAssertEqualWithAccuracy([cookies.firstObject[@"expires"] doubleValue], 2000000000, 0.001);
}

- (void)testSetKeepsHostOnlyAndDomainCookiesApartAndPicksTheSchemeFromSecure {
    NSDictionary *host = @{@"name": @"host", @"value": @"1", @"domain": @"www.example.test", @"path": @"/",
                           @"secure": @NO, @"httpOnly": @YES, @"sameSite": @"Unspecified"};
    NSDictionary *wide = @{@"name": @"wide", @"value": @"2", @"domain": @".Example.test", @"path": @"/a",
                           @"secure": @YES, @"httpOnly": @NO, @"sameSite": @"None", @"expires": @2000000000};
    XCTAssertTrue([self set:host]);
    XCTAssertTrue([self set:wide]);
    XCTAssertTrue(_manager->setURLs[0] == "http://www.example.test/");
    XCTAssertTrue(_manager->setURLs[1] == "https://example.test/a");
    XCTAssertTrue(_manager->setSizes[0] == sizeof(cef_cookie_t), @"CEF reads the struct by its size");

    BOOL complete = NO;
    NSArray<NSDictionary *> *cookies = [self visit:&complete];
    NSDictionary *storedHost = [cookies filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name == 'host'"]].firstObject;
    NSDictionary *storedWide = [cookies filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name == 'wide'"]].firstObject;
    XCTAssertTrue(complete);
    XCTAssertEqualObjects(storedHost[@"domain"], @"www.example.test");
    XCTAssertEqualObjects(storedHost[@"httpOnly"], @YES);
    XCTAssertNil(storedHost[@"expires"], @"A session cookie stays a session cookie");
    XCTAssertEqualObjects(storedWide[@"domain"], @".example.test");
    XCTAssertEqualObjects(storedWide[@"sameSite"], @"None");
}

- (void)testSetReportsTheEngineRefusalAndRejectsUnknownSameSite {
    NSDictionary *insecureNone = @{@"name": @"n", @"value": @"1", @"domain": @"example.test", @"path": @"/",
                                   @"secure": @NO, @"httpOnly": @NO, @"sameSite": @"None"};
    NSDictionary *unknown = @{@"name": @"n", @"value": @"1", @"domain": @"example.test", @"path": @"/",
                              @"secure": @NO, @"httpOnly": @NO, @"sameSite": @"lenient"};
    XCTAssertFalse([self set:insecureNone]);
    XCTAssertFalse([self set:unknown]);
    XCTAssertTrue(_manager->setURLs.size() == 1, @"An unnamed SameSite never reaches CEF");
}

- (void)testDeleteRemovesExactlyTheNamedKeys {
    for (const char *domain : {"example.test", ".example.test"}) {
        StoredCookie cookie;
        cookie.name = "sid";
        cookie.domain = domain;
        cookie.path = "/";
        _manager->cookies.push_back(cookie);
    }
    StoredCookie deeper;
    deeper.name = "sid";
    deeper.domain = ".example.test";
    deeper.path = "/a";
    _manager->cookies.push_back(deeper);

    XCTestExpectation *done = [self expectationWithDescription:@"delete"];
    __block NSInteger deleted = -1;
    __block BOOL finished = NO;
    NSArray *keys = @[@{@"domain": @".EXAMPLE.test", @"path": @"/", @"name": @"sid"}];
    [CEFBridge deleteGlobalCookiesMatching:keys completion:^(BOOL complete, NSInteger count) {
        finished = complete;
        deleted = count;
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:5];
    XCTAssertTrue(finished);
    XCTAssertEqual(deleted, 1);
    XCTAssertTrue(_manager->cookies.size() == 2);
}

- (void)testDeleteAllReportsTheCount {
    _manager->cookies.resize(3);
    XCTestExpectation *done = [self expectationWithDescription:@"delete all"];
    [CEFBridge deleteAllGlobalCookiesWithCompletion:^(BOOL success, NSInteger deleted) {
        XCTAssertTrue(success);
        XCTAssertEqual(deleted, 3);
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:5];
}

@end
#endif
