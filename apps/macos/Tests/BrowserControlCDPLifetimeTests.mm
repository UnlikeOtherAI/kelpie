#import <XCTest/XCTest.h>
#import "CEFBridgeSupport.h"
#include <atomic>

namespace {
void CEF_CALLBACK AddRef(cef_base_ref_counted_t *) {}
int CEF_CALLBACK Release(cef_base_ref_counted_t *) { return 0; }
int CEF_CALLBACK HasRef(cef_base_ref_counted_t *) { return 1; }

// Owns a fake CEF transport, not a live app/browser or user profile.
struct CDPFixture {
    cef_browser_host_t host = {};
    cef_browser_t browser = {};
    cef_registration_t registration = {};
    cef_dev_tools_message_observer_t *observer = nullptr;
    int messageID = 0;
    int browserID;

    CDPFixture() {
        static std::atomic<int> nextID{500000};
        browserID = nextID++;
        host.base = Base(sizeof(host));
        browser.base = Base(sizeof(browser));
        registration.base = Base(sizeof(registration));
        host.get_browser = [](cef_browser_host_t *value) -> cef_browser_t * {
            return &reinterpret_cast<CDPFixture *>(value)->browser;
        };
        browser.get_identifier = [](cef_browser_t *value) -> int {
            auto *fixture = reinterpret_cast<CDPFixture *>(reinterpret_cast<char *>(value) - offsetof(CDPFixture, browser));
            return fixture->browserID;
        };
        host.add_dev_tools_message_observer = [](cef_browser_host_t *value, cef_dev_tools_message_observer_t *observer) -> cef_registration_t * {
            auto *fixture = reinterpret_cast<CDPFixture *>(value);
            fixture->observer = observer;
            observer->base.add_ref(&observer->base);
            return &fixture->registration;
        };
        host.send_dev_tools_message = [](cef_browser_host_t *value, const void *bytes, size_t size) -> int {
            auto *fixture = reinterpret_cast<CDPFixture *>(value);
            NSData *data = [NSData dataWithBytes:bytes length:size];
            NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            fixture->messageID = [payload[@"id"] intValue];
            return 1;
        };
    }

    ~CDPFixture() {
        CEFBridgeRetireBrowserControlCommands(&browser);
        if (observer) { observer->base.release(&observer->base); }
    }

    void Result() {
        const char payload[] = "{\"result\":{\"value\":true}}";
        observer->on_dev_tools_method_result(observer, &browser, messageID, 1, payload, sizeof(payload) - 1);
    }

private:
    static cef_base_ref_counted_t Base(size_t size) {
        cef_base_ref_counted_t result = {};
        result.size = size;
        result.add_ref = AddRef;
        result.release = Release;
        result.has_one_ref = HasRef;
        result.has_at_least_one_ref = HasRef;
        return result;
    }
};
}

@interface BrowserControlCDPLifetimeTests : XCTestCase
@end

@implementation BrowserControlCDPLifetimeTests
- (void)testBrowserControlWaitsPastLegacyTimeoutAndDetachForActualResult {
    CDPFixture fixture;
    XCTestExpectation *retired = [self expectationWithDescription:@"Actual CDP result retires callback"];
    __block NSInteger completions = 0;
    CEFBridgeSendBrowserControlCommand(&fixture.host, @"Runtime.evaluate", @{}, ^(BOOL success, NSDictionary *) {
        completions++;
        XCTAssertTrue(success);
        [retired fulfill];
    });
    fixture.observer->on_dev_tools_agent_detached(fixture.observer, &fixture.browser);
    // Bridge release requests teardown, but is not confirmed renderer close.
    CEFBridgeInvalidateCookieObserver(&fixture.browser);
    CDPFixture *pending = &fixture;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        XCTAssertEqual(completions, 0);
        pending->Result();
    });
    [self waitForExpectations:@[retired] timeout:7];
    XCTAssertEqual(completions, 1);
}

- (void)testConfirmedBrowserCloseRetiresPendingControlExactlyOnce {
    CDPFixture fixture;
    XCTestExpectation *retired = [self expectationWithDescription:@"Confirmed browser close retires callback"];
    __block NSInteger completions = 0;
    CEFBridgeSendBrowserControlCommand(&fixture.host, @"Runtime.evaluate", @{}, ^(BOOL success, NSDictionary *) {
        completions++;
        XCTAssertFalse(success);
        [retired fulfill];
    });
    CEFBridgeRetireBrowserControlCommands(&fixture.browser);
    fixture.Result();
    [self waitForExpectations:@[retired] timeout:1];
    XCTAssertEqual(completions, 1);
}
@end
