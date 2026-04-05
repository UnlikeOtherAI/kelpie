#import <Foundation/Foundation.h>

#import "CEFBridge.h"

#include "include/cef_api_versions.h"
#ifndef CEF_API_VERSION
#define CEF_API_VERSION CEF_API_VERSION_14600
#endif
#include "include/cef_api_hash.h"
#include "include/capi/cef_app_capi.h"
#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_client_capi.h"
#include "include/capi/cef_callback_capi.h"
#include "include/capi/cef_cookie_capi.h"
#include "include/capi/cef_devtools_message_observer_capi.h"
#include "include/capi/cef_request_context_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_registration_capi.h"
#include "include/internal/cef_time.h"

typedef struct BridgeClient BridgeClient;

cef_main_args_t CEFBridgeMainArgs(void);
cef_string_t CEFBridgeStringCreate(NSString *value);
void CEFBridgeStringClear(cef_string_t *value);
NSString *CEFBridgeStringFromUserFree(cef_string_userfree_t value);
NSString *CEFBridgeJSONStringForValue(id value);
cef_basetime_t CEFBridgeBaseTimeFromDate(NSDate *value);

BridgeClient *CEFBridgeCreateClient(CEFBridge *owner);
cef_client_t *CEFBridgeClientHandle(BridgeClient *client);
void CEFBridgeNullifyClientOwner(BridgeClient *client);
void CEFBridgeReleaseClient(BridgeClient *client);

cef_cookie_manager_t *CEFBridgeCookieManagerFromBrowser(cef_browser_t *browser);
void CEFBridgeVisitAllCookies(cef_cookie_manager_t *manager, void (^completion)(NSArray<NSDictionary *> *cookies));
void CEFBridgeSetCookie(cef_cookie_manager_t *manager,
                        NSString *name,
                        NSString *value,
                        NSString *url,
                        NSString *domain,
                        NSString *path,
                        BOOL httpOnly,
                        BOOL secure,
                        NSDate *expires,
                        void (^completion)(BOOL success));
void CEFBridgeDeleteAllCookies(cef_cookie_manager_t *manager, void (^completion)(NSInteger deleted));
void CEFBridgeFlushCookieStore(cef_cookie_manager_t *manager, void (^completion)(void));
void CEFBridgeCaptureScreenshot(cef_browser_host_t *host,
                                CGSize logicalSize,
                                void (^completion)(NSData * _Nullable pngData));
void CEFBridgeInvalidateScreenshotCapture(cef_browser_t *browser);

@interface CEFBridge (SupportCallbacks)
- (void)cefBridgeDidCreateBrowser:(cef_browser_t *)browser;
- (void)cefBridgeWillCloseBrowser;
- (void)cefBridgeUpdateLoadingStateWithIsLoading:(BOOL)isLoading
                                       canGoBack:(BOOL)canGoBack
                                    canGoForward:(BOOL)canGoForward;
- (void)cefBridgeUpdateCurrentURL:(NSString *)url;
- (void)cefBridgeUpdateCurrentTitle:(NSString *)title;
- (void)cefBridgeUpdateLoadingProgress:(double)progress;
- (void)cefBridgeHandleConsoleMessage:(NSString *)message
                               source:(NSString *)source
                                 line:(NSInteger)line;
@end
