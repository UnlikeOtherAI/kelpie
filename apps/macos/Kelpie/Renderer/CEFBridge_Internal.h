#import <AppKit/AppKit.h>

#import "CEFBridge.h"
#import "CEFBridgeSupport.h"

NS_ASSUME_NONNULL_BEGIN

/// Shared private interface for CEFBridge.mm and its category split files
/// (CEFBridge+Screenshot.mm, CEFBridge+Cookies.mm).
///
/// Ivars declared here are visible to any file that imports this header.
/// They MUST remain the single source of truth for the bridge's internal
/// state — never redeclare them in a category extension.
@interface CEFBridge () {
@public
    __weak NSView *_parentView;
    NSString *_identifier;
    NSString *_currentURL;
    NSString *_currentTitle;
    BOOL _isLoading;
    BOOL _canGoBack;
    BOOL _canGoForward;
    NSInteger _mainFrameHTTPStatusCode;
    double _loadingProgress;
    NSInteger _nextEvalID;
    NSMutableDictionary<NSString *, id> *_pendingEvalBlocks;
    BridgeClient *_client;
    cef_browser_t *_createdBrowser;
    cef_browser_t *_callbackBrowser;
    cef_cookie_manager_t *_cookieManager;
}

/// Returns the live browser handle, preferring `_createdBrowser` over `_callbackBrowser`.
- (nullable cef_browser_t *)activeBrowser;

/// Returns the main frame of the active browser, or NULL if unavailable.
/// Caller is responsible for releasing the returned frame via base.release.
- (nullable cef_frame_t *)copyMainFrame;

/// Resume a pending JS evaluation block.
- (void)_finishEvalWithIdentifier:(NSString *)identifier
                           result:(nullable NSString *)result
                            error:(nullable NSError *)error;

/// Resolve every pending JS evaluation block with the same error.
- (void)_failAllPendingEvalsWithError:(NSError *)error;

@end

// MARK: - Browser-handle introspection helpers (used by screenshot + cookie paths)

cef_browser_host_t *_Nullable CEFBridgeCopyBrowserHost(cef_browser_t *_Nullable browser);
cef_frame_t *_Nullable CEFBridgeCopyMainFrame(cef_browser_t *_Nullable browser);
int CEFBridgeBrowserIdentifier(cef_browser_t *_Nullable browser);
NSInteger CEFBridgeBrowserLivenessScore(cef_browser_t *_Nullable browser);
NSString *CEFBridgeDescribeBrowser(cef_browser_t *_Nullable browser);
void CEFBridgeLogBrowserHandles(const char *event,
                                cef_browser_t *_Nullable callbackBrowser,
                                cef_browser_t *_Nullable createdBrowser,
                                cef_browser_t *_Nullable activeBrowser);
void CEFBridgeNotifyStateChange(CEFBridge *owner);

NS_ASSUME_NONNULL_END
