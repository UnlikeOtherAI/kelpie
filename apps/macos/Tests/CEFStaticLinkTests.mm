#if !defined(KELPIE_WEBKIT_ONLY)
#import <XCTest/XCTest.h>
#import "CEFBridgeSupport.h"

namespace {
struct MediaDecision {
    cef_media_access_callback_t callback{};
    bool canceled = false;
    bool continued = false;
    bool released = false;

    MediaDecision() {
        callback.base.size = sizeof(callback);
        callback.base.release = [](cef_base_ref_counted_t *self) -> int {
            reinterpret_cast<MediaDecision *>(self)->released = true;
            return 0;
        };
        callback.cancel = [](cef_media_access_callback_t *self) {
            reinterpret_cast<MediaDecision *>(self)->canceled = true;
        };
        callback.cont = [](cef_media_access_callback_t *self, uint32_t) {
            reinterpret_cast<MediaDecision *>(self)->continued = true;
        };
    }
};
}

@interface CEFStaticLinkTests : XCTestCase
@end

@implementation CEFStaticLinkTests
- (void)testStaticLibraryIncludesLifecycleCategory {
    XCTAssertTrue([CEFBridge respondsToSelector:@selector(initializeCEF)]);
    XCTAssertTrue([CEFBridge respondsToSelector:@selector(shutdownCEF)]);
    XCTAssertTrue([CEFBridge respondsToSelector:@selector(doMessageLoopWork)]);
}
- (void)testMicrophoneWithoutVisibleTabIsDeniedByCEFClient {
    __attribute__((objc_precise_lifetime)) CEFBridge *bridge = [[CEFBridge alloc] init];
    BridgeClient *client = CEFBridgeCreateClient(bridge);
    cef_client_t *handle = CEFBridgeClientHandle(client);
    cef_permission_handler_t *permission = handle->get_permission_handler(handle);
    cef_string_t origin = CEFBridgeStringCreate(@"https://voice.example");

    MediaDecision microphone;
    XCTAssertTrue(permission->on_request_media_access_permission(
        permission, nullptr, nullptr, &origin, CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE, &microphone.callback));
    XCTAssertTrue(microphone.canceled);
    XCTAssertFalse(microphone.continued);
    XCTAssertTrue(microphone.released);

    MediaDecision combined;
    XCTAssertTrue(permission->on_request_media_access_permission(
        permission, nullptr, nullptr, &origin,
        CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE | CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE, &combined.callback));
    XCTAssertTrue(combined.canceled);
    XCTAssertFalse(combined.continued);
    XCTAssertTrue(combined.released);

    MediaDecision camera;
    XCTAssertFalse(permission->on_request_media_access_permission(
        permission, nullptr, nullptr, &origin, CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE, &camera.callback));
    XCTAssertFalse(camera.canceled);
    XCTAssertFalse(camera.continued);
    XCTAssertTrue(camera.released);

    CEFBridgeStringClear(&origin);
    permission->base.release(&permission->base);
    CEFBridgeReleaseClient(client);
}
@end
#endif
