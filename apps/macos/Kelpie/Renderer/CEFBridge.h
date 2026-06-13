#import <AppKit/AppKit.h>

/// Objective-C wrapper around CEF's C API for Swift interop.
/// This is intentionally thin — only the functionality we need.
NS_ASSUME_NONNULL_BEGIN

@interface CEFBridge : NSObject

/// Initialize CEF. Must be called once at app startup.
/// Returns YES if this process should continue as the main app,
/// NO if this is a helper subprocess (caller should exit).
+ (BOOL)initializeCEF;

/// Shut down CEF. Call before app termination.
+ (void)shutdownCEF;

/// Pump the CEF message loop. Call periodically from a timer.
+ (void)doMessageLoopWork;

/// Create a new browser instance.
/// @param parentView The NSView to host the browser.
/// @param url The initial URL to load.
/// @param identifier A unique identifier for this browser instance.
- (instancetype)initWithParentView:(NSView *)parentView
                               url:(NSString *)url
                        identifier:(NSString *)identifier;

/// Navigate to a URL.
- (void)loadURL:(NSString *)url;

/// Go back in history.
- (void)goBack;

/// Go forward in history.
- (void)goForward;

/// Reload the current page.
- (void)reload;

/// Reload the current page ignoring the HTTP cache.
- (void)reloadIgnoringCache;

/// Get the current URL.
- (NSString *)currentURL;

/// Get the current page title.
- (NSString *)currentTitle;

/// Whether the browser is loading.
- (BOOL)isLoading;

/// Whether the browser can go back.
- (BOOL)canGoBack;

/// Whether the browser can go forward.
- (BOOL)canGoForward;

/// HTTP status code of the most recently completed main-frame document load,
/// or 0 if not yet known. Captured from CEF's OnLoadEnd callback.
- (NSInteger)mainFrameHTTPStatusCode;

/// Evaluate JavaScript and return the result via callback.
/// The callback receives the result as a JSON string, or nil on error.
- (void)evaluateJavaScript:(NSString *)script
                completion:(void (^ _Nonnull)(NSString * _Nullable result, NSError * _Nullable error))completion;

/// Close the browser and pump the CEF message loop until the close
/// completes. Must be called before releasing the bridge to avoid
/// leaving CrBrowserMain running against freed state.
- (void)closeBrowser;

/// Notify CEF that the browser view is hidden or visible.
/// Call with YES when the view is removed from any window,
/// NO when it is added back. This pauses CEF's rendering
/// pipeline while the view is detached and resumes it on reattach.
- (void)setHidden:(BOOL)hidden;

// Cookie operations live in CEFBridge+Cookies.h.
// Screenshot/resize operations live in CEFBridge+Screenshot.h.

/// Set callback for navigation state changes.
@property (nonatomic, copy, nullable) void (^onStateChange)(void);

/// Set callback for console messages from the page.
@property (nonatomic, copy, nullable) void (^onConsoleMessage)(NSDictionary *message);

@end

NS_ASSUME_NONNULL_END
