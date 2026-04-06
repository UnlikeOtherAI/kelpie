#import "CEFBridge.h"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "CEFBridgeSupport.h"

static NSString *const kCEFBridgeErrorDomain = @"com.kelpie.browser.cef";
static NSString *const kEvalConsolePrefix = @"__kelpie_eval__:";

static BOOL gCEFInitialized = NO;
static const void *kCEFHandlingSendEventKey = &kCEFHandlingSendEventKey;

@protocol CrAppProtocol
- (BOOL)isHandlingSendEvent;
@end

@protocol CrAppControlProtocol <CrAppProtocol>
- (void)setHandlingSendEvent:(BOOL)handlingSendEvent;
@end

@protocol CefAppProtocol <CrAppControlProtocol>
@end

@interface NSApplication (KelpieCEFAppProtocol) <CefAppProtocol>
@end

@implementation NSApplication (KelpieCEFAppProtocol)

- (BOOL)isHandlingSendEvent {
    return [objc_getAssociatedObject(self, kCEFHandlingSendEventKey) boolValue];
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
    objc_setAssociatedObject(
        self,
        kCEFHandlingSendEventKey,
        @(handlingSendEvent),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

@end

@interface CEFBridge ()
- (void)_finishEvalWithIdentifier:(NSString *)identifier result:(NSString *)result error:(NSError *)error;
@end

@interface CEFBridge () {
    __weak NSView *_parentView;
    NSString *_identifier;
    NSString *_currentURL;
    NSString *_currentTitle;
    BOOL _isLoading;
    BOOL _canGoBack;
    BOOL _canGoForward;
    double _loadingProgress;
    NSInteger _nextEvalID;
    NSMutableDictionary<NSString *, id> *_pendingEvalBlocks;
    BridgeClient *_client;
    cef_browser_t *_createdBrowser;
    cef_browser_t *_callbackBrowser;
    cef_cookie_manager_t *_cookieManager;
}
@end

static void NotifyStateChange(CEFBridge *owner) {
    if (owner.onStateChange == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (owner.onStateChange != nil) {
            owner.onStateChange();
        }
    });
}

static void FinishEval(CEFBridge *owner, NSString *identifier, NSString *result, NSError *error) {
    if (owner == nil || identifier.length == 0) {
        return;
    }
    [owner _finishEvalWithIdentifier:identifier result:result error:error];
}

static NSData *WindowCropPNGData(NSView *view, NSWindow *window, BOOL *fullyCaptured) {
    if (fullyCaptured != nullptr) {
        *fullyCaptured = NO;
    }
    if (view == nil || window == nil) {
        return nil;
    }

    NSView *frameView = window.contentView.superview;
    if (frameView == nil) {
        return nil;
    }

    // ScreenCaptureKit is not a drop-in replacement for synchronous crop capture
    // of CEF's accelerated surface, so keep the legacy call scoped and silenced
    // until the screenshot path is migrated end-to-end.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CGImageRef windowImage = CGWindowListCreateImage(
        CGRectNull,
        kCGWindowListOptionIncludingWindow,
        (CGWindowID)window.windowNumber,
        kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution
    );
#pragma clang diagnostic pop
    if (windowImage == nullptr) {
        return nil;
    }

    NSRect rectInFrameView = [view convertRect:view.bounds toView:frameView];
    NSRect backingRect = [frameView convertRectToBacking:rectInFrameView];
    CGFloat imageWidth = (CGFloat)CGImageGetWidth(windowImage);
    CGFloat imageHeight = (CGFloat)CGImageGetHeight(windowImage);
    CGRect desiredCropRect = CGRectMake(
        backingRect.origin.x,
        imageHeight - NSMaxY(backingRect),
        backingRect.size.width,
        backingRect.size.height
    );
    CGRect imageBounds = CGRectMake(0, 0, imageWidth, imageHeight);
    CGRect cropRect = CGRectIntersection(desiredCropRect, imageBounds);
    if (fullyCaptured != nullptr) {
        *fullyCaptured = CGRectEqualToRect(cropRect, desiredCropRect);
    }

    NSData *pngData = nil;
    if (!CGRectIsEmpty(cropRect)) {
        CGImageRef croppedImage = CGImageCreateWithImageInRect(windowImage, cropRect);
        if (croppedImage != nullptr) {
            NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:croppedImage];
            pngData = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            CGImageRelease(croppedImage);
        }
    }

    CGImageRelease(windowImage);
    return pngData;
}

static NSRect ExpandedWindowFrameIfNeeded(NSView *view, NSWindow *window) {
    if (view == nil || window == nil) {
        return NSZeroRect;
    }
    NSView *frameView = window.contentView.superview;
    if (frameView == nil) {
        return window.frame;
    }

    NSRect rectInFrameView = [view convertRect:view.bounds toView:frameView];
    NSRect currentFrame = window.frame;
    CGFloat requiredWidth = ceil(NSMaxX(rectInFrameView));
    CGFloat requiredHeight = ceil(NSMaxY(rectInFrameView));

    if (requiredWidth <= currentFrame.size.width + 0.5 &&
        requiredHeight <= currentFrame.size.height + 0.5) {
        return currentFrame;
    }

    NSRect expandedFrame = currentFrame;
    CGFloat widthDelta = fmax(requiredWidth - currentFrame.size.width, 0.0);
    CGFloat heightDelta = fmax(requiredHeight - currentFrame.size.height, 0.0);
    expandedFrame.size.width += widthDelta;
    expandedFrame.size.height += heightDelta;
    expandedFrame.origin.y -= heightDelta;
    return expandedFrame;
}

static NSData *CachedViewPNGData(NSView *view) {
    if (view == nil) {
        return nil;
    }

    NSRect bounds = view.bounds;
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:bounds];
    if (bitmap == nil) {
        return nil;
    }
    [view cacheDisplayInRect:bounds toBitmapImageRep:bitmap];
    return [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

static void CaptureWithExpandedWindowIfNeeded(NSView *view,
                                              NSWindow *window,
                                              void (^completion)(NSData * _Nullable pngData)) {
    if (view == nil || completion == nil) {
        if (completion != nil) {
            completion(nil);
        }
        return;
    }
    if (window == nil || (window.styleMask & NSWindowStyleMaskFullScreen) != 0) {
        completion(CachedViewPNGData(view));
        return;
    }

    NSRect originalFrame = window.frame;
    NSRect expandedFrame = ExpandedWindowFrameIfNeeded(view, window);
    if (NSEqualRects(originalFrame, expandedFrame)) {
        completion(WindowCropPNGData(view, window, nil) ?: CachedViewPNGData(view));
        return;
    }

    [window setFrame:expandedFrame display:YES];
    [window layoutIfNeeded];
    [window.contentView layoutSubtreeIfNeeded];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSData *resizedPNG = WindowCropPNGData(view, window, nil);
        [window setFrame:originalFrame display:YES];
        [window layoutIfNeeded];
        [window.contentView layoutSubtreeIfNeeded];
        completion(resizedPNG ?: CachedViewPNGData(view));
    });
}

static cef_browser_host_t *CopyBrowserHost(cef_browser_t *browser) {
    if (browser == nullptr || browser->get_host == nullptr) {
        return nullptr;
    }
    return browser->get_host(browser);
}

static cef_frame_t *CopyMainFrame(cef_browser_t *browser) {
    if (browser == nullptr || browser->get_main_frame == nullptr) {
        return nullptr;
    }
    return browser->get_main_frame(browser);
}

static int BrowserIdentifier(cef_browser_t *browser) {
    if (browser == nullptr || browser->get_identifier == nullptr) {
        return 0;
    }
    return browser->get_identifier(browser);
}

static NSInteger BrowserLivenessScore(cef_browser_t *browser) {
    if (browser == nullptr) {
        return NSIntegerMin;
    }

    NSInteger score = 0;
    if (browser->is_valid != nullptr && browser->is_valid(browser)) {
        score += 4;
    }
    if (browser->has_document != nullptr && browser->has_document(browser)) {
        score += 2;
    }

    cef_browser_host_t *host = CopyBrowserHost(browser);
    if (host != nullptr) {
        score += 1;
        if (host->has_view != nullptr && host->has_view(host)) {
            score += 1;
        }
        host->base.release(&host->base);
    }

    cef_frame_t *frame = CopyMainFrame(browser);
    if (frame != nullptr) {
        score += 4;
        if (frame->is_valid != nullptr && frame->is_valid(frame)) {
            score += 2;
        }
        frame->base.release(&frame->base);
    }

    return score;
}

static NSString *DescribeBrowser(cef_browser_t *browser) {
    if (browser == nullptr) {
        return @"nil";
    }

    const int browserID = BrowserIdentifier(browser);
    const BOOL isValid = browser->is_valid != nullptr ? browser->is_valid(browser) != 0 : NO;
    const BOOL hasDocument = browser->has_document != nullptr ? browser->has_document(browser) != 0 : NO;

    cef_browser_host_t *host = CopyBrowserHost(browser);
    const BOOL hasHost = host != nullptr;
    const BOOL hasView = hasHost && host->has_view != nullptr ? host->has_view(host) != 0 : NO;
    const BOOL isWindowless = hasHost && host->is_window_rendering_disabled != nullptr
        ? host->is_window_rendering_disabled(host) != 0
        : NO;

    cef_frame_t *frame = CopyMainFrame(browser);
    const BOOL hasFrame = frame != nullptr;
    const BOOL frameValid = hasFrame && frame->is_valid != nullptr ? frame->is_valid(frame) != 0 : NO;
    NSString *frameID = hasFrame && frame->get_identifier != nullptr
        ? CEFBridgeStringFromUserFree(frame->get_identifier(frame))
        : @"";
    NSString *frameURL = hasFrame && frame->get_url != nullptr
        ? CEFBridgeStringFromUserFree(frame->get_url(frame))
        : @"";

    if (frame != nullptr) {
        frame->base.release(&frame->base);
    }
    if (host != nullptr) {
        host->base.release(&host->base);
    }

    return [NSString stringWithFormat:
            @"ptr=%p id=%d valid=%d doc=%d host=%d view=%d windowless=%d frame=%d frameValid=%d frameID=%@ url=%@ score=%ld",
            browser,
            browserID,
            isValid,
            hasDocument,
            hasHost,
            hasView,
            isWindowless,
            hasFrame,
            frameValid,
            frameID.length > 0 ? frameID : @"<none>",
            frameURL.length > 0 ? frameURL : @"<none>",
            (long)BrowserLivenessScore(browser)];
}

static void LogBrowserHandles(const char *event, cef_browser_t *callbackBrowser, cef_browser_t *createdBrowser, cef_browser_t *activeBrowser) {
    const int callbackID = BrowserIdentifier(callbackBrowser);
    const int createdID = BrowserIdentifier(createdBrowser);
    const int activeID = BrowserIdentifier(activeBrowser);
    const long callbackScore = (long)BrowserLivenessScore(callbackBrowser);
    const long createdScore = (long)BrowserLivenessScore(createdBrowser);
    const long activeScore = (long)BrowserLivenessScore(activeBrowser);
    fprintf(
        stderr,
        "[CEFBridge] %s callback=%p(id=%d score=%ld) created=%p(id=%d score=%ld) active=%p(id=%d score=%ld)\n",
        event,
        callbackBrowser,
        callbackID,
        callbackScore,
        createdBrowser,
        createdID,
        createdScore,
        activeBrowser,
        activeID,
        activeScore
    );
}

@implementation CEFBridge

- (void)_finishEvalWithIdentifier:(NSString *)identifier result:(NSString *)result error:(NSError *)error {
    void (^completion)(NSString *, NSError *) = nil;
    @synchronized (self) {
        completion = _pendingEvalBlocks[identifier];
        [_pendingEvalBlocks removeObjectForKey:identifier];
    }
    if (completion == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(result, error);
    });
}

+ (BOOL)initializeCEF {
    if (gCEFInitialized) {
        return YES;
    }

    const char *apiHash = cef_api_hash(CEF_API_VERSION, 0);
    NSLog(@"[CEF] Configured API version=%d hash=%s", cef_api_version(), apiHash != nullptr ? apiHash : "");

    NSString *helperExecutable = [[NSBundle mainBundle].privateFrameworksPath stringByAppendingPathComponent:@"Kelpie Helper.app/Contents/MacOS/Kelpie Helper"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:helperExecutable]) {
        NSLog(@"[CEF] FATAL: Kelpie Helper.app not found at expected path: %@", helperExecutable);
        return NO;
    }

    cef_main_args_t mainArgs = CEFBridgeMainArgs();
    int exitCode = cef_execute_process(&mainArgs, nullptr, nullptr);
    if (exitCode >= 0) {
        return NO;
    }

    cef_settings_t settings = {};
    settings.size = sizeof(settings);
    settings.no_sandbox = 1;
    settings.multi_threaded_message_loop = 0;

    cef_string_t subprocessPath = CEFBridgeStringCreate(helperExecutable);
    settings.browser_subprocess_path = subprocessPath;

    NSString *frameworkPath = [[NSBundle mainBundle].privateFrameworksPath stringByAppendingPathComponent:@"Chromium Embedded Framework.framework"];
    cef_string_t frameworkPathCEF = CEFBridgeStringCreate(frameworkPath);
    settings.framework_dir_path = frameworkPathCEF;

    NSString *bundlePath = [NSBundle mainBundle].bundlePath;
    cef_string_t bundlePathCEF = CEFBridgeStringCreate(bundlePath);
    settings.main_bundle_path = bundlePathCEF;

    NSString *cachePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"kelpie-cef-cache"];
    [[NSFileManager defaultManager] createDirectoryAtPath:cachePath withIntermediateDirectories:YES attributes:nil error:nil];
    cef_string_t cachePathCEF = CEFBridgeStringCreate(cachePath);
    settings.cache_path = cachePathCEF;

    const int ok = cef_initialize(&mainArgs, &settings, nullptr, nullptr);
    CEFBridgeStringClear(&settings.browser_subprocess_path);
    CEFBridgeStringClear(&settings.framework_dir_path);
    CEFBridgeStringClear(&settings.main_bundle_path);
    CEFBridgeStringClear(&settings.cache_path);
    gCEFInitialized = ok != 0;
    return gCEFInitialized;
}

+ (void)shutdownCEF {
    if (!gCEFInitialized) {
        return;
    }
    cef_shutdown();
    gCEFInitialized = NO;
}

+ (void)doMessageLoopWork {
    if (gCEFInitialized) {
        cef_do_message_loop_work();
    }
}

- (instancetype)initWithParentView:(NSView *)parentView
                               url:(NSString *)url
                        identifier:(NSString *)identifier {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _parentView = parentView;
    _identifier = [identifier copy];
    _currentURL = url.length > 0 ? [url copy] : @"about:blank";
    _currentTitle = @"";
    _pendingEvalBlocks = [NSMutableDictionary dictionary];
    _client = CEFBridgeCreateClient(self);

    cef_window_info_t windowInfo = {};
    windowInfo.size = sizeof(windowInfo);
    windowInfo.parent_view = (__bridge void *)parentView;
    NSRect parentBounds = parentView.bounds;
    windowInfo.bounds.x = 0;
    windowInfo.bounds.y = 0;
    windowInfo.bounds.width = (int)NSWidth(parentBounds);
    windowInfo.bounds.height = (int)NSHeight(parentBounds);
    windowInfo.hidden = 0;

    cef_browser_settings_t settings = {};
    settings.size = sizeof(settings);

    cef_string_t initialURL = CEFBridgeStringCreate(_currentURL);
    cef_browser_t *createdBrowser =
        cef_browser_host_create_browser_sync(&windowInfo, CEFBridgeClientHandle(_client), &initialURL, &settings, nullptr, nullptr);
    CEFBridgeStringClear(&initialURL);

    @synchronized (self) {
        _createdBrowser = createdBrowser;
    }

    _cookieManager = CEFBridgeCookieManagerFromBrowser(createdBrowser);

    NSLog(
        @"[CEFBridge] create_browser_sync returned=%@ parentSubviews=%lu",
        DescribeBrowser(createdBrowser),
        (unsigned long)parentView.subviews.count
    );
    LogBrowserHandles("create_browser_sync", _callbackBrowser, _createdBrowser, [self activeBrowser]);
    return self;
}

- (void)closeBrowser {
    // Force-close the browser so CEF can tear down CrBrowserMain and all
    // internal threads cleanly before this bridge is released. Without this,
    // releasing the browser handle leaves CEF's internal state half-alive,
    // and creating a new browser (on renderer switch) collides with it.
    cef_browser_t *browser = [self activeBrowser];
    if (browser == nullptr) { return; }
    cef_browser_host_t *host = browser->get_host ? browser->get_host(browser) : nullptr;
    if (host == nullptr) { return; }
    host->close_browser(host, 1); // force=1: skip JS unload, close immediately
    host->base.release(&host->base);
    // Drain CEF's message queue so the close events are processed before
    // the caller releases this object.
    for (int i = 0; i < 30; i++) {
        cef_do_message_loop_work();
    }
}

- (void)setHidden:(BOOL)hidden {
    cef_browser_t *browser = [self activeBrowser];
    if (browser == nullptr) { return; }
    cef_browser_host_t *host = browser->get_host ? browser->get_host(browser) : nullptr;
    if (host == nullptr) { return; }
    if (host->was_hidden != nullptr) {
        host->was_hidden(host, hidden ? 1 : 0);
    }
    host->base.release(&host->base);
}

- (void)dealloc {
    @synchronized (self) {
        // Nil out all owner back-pointers before releasing CEF handles.
        // The 60 Hz message-loop timer can fire cef_do_message_loop_work()
        // between here and the next run-loop iteration, invoking callbacks
        // through these pointers. Clearing them first turns those callbacks
        // into safe no-ops instead of dangling-pointer crashes.
        CEFBridgeNullifyClientOwner(_client);
        if (_callbackBrowser != nullptr) {
            CEFBridgeInvalidateScreenshotCapture(_callbackBrowser);
        }
        if (_createdBrowser != nullptr) {
            CEFBridgeInvalidateScreenshotCapture(_createdBrowser);
        }
        if (_cookieManager != nullptr) {
            _cookieManager->base.release(&_cookieManager->base);
            _cookieManager = nullptr;
        }
        if (_callbackBrowser != nullptr) {
            _callbackBrowser->base.release(&_callbackBrowser->base);
            _callbackBrowser = nullptr;
        }
        if (_createdBrowser != nullptr) {
            _createdBrowser->base.release(&_createdBrowser->base);
            _createdBrowser = nullptr;
        }
        if (_client != nullptr) {
            CEFBridgeReleaseClient(_client);
            _client = nullptr;
        }
    }
}

- (cef_browser_t *)activeBrowser {
    @synchronized (self) {
        return _createdBrowser != nullptr ? _createdBrowser : _callbackBrowser;
    }
}

- (cef_frame_t *)copyMainFrame {
    cef_browser_t *browser = [self activeBrowser];
    if (browser == nullptr) {
        NSLog(@"[CEFBridge] mainFrame unavailable active=nil created=%@ callback=%@", DescribeBrowser(_createdBrowser), DescribeBrowser(_callbackBrowser));
        LogBrowserHandles("main_frame_unavailable_nil", _callbackBrowser, _createdBrowser, browser);
        return nullptr;
    }

    cef_frame_t *frame = CopyMainFrame(browser);
    if (frame == nullptr) {
        NSLog(@"[CEFBridge] mainFrame returned null active=%@ created=%@ callback=%@", DescribeBrowser(browser), DescribeBrowser(_createdBrowser), DescribeBrowser(_callbackBrowser));
        LogBrowserHandles("main_frame_unavailable_null", _callbackBrowser, _createdBrowser, browser);
    }
    return frame;
}

- (void)loadURL:(NSString *)url {
    cef_frame_t *frame = [self copyMainFrame];
    if (frame == nullptr || frame->load_url == nullptr) {
        if (frame != nullptr) {
            frame->base.release(&frame->base);
        }
        return;
    }

    cef_string_t value = CEFBridgeStringCreate(url ?: @"about:blank");
    frame->load_url(frame, &value);
    CEFBridgeStringClear(&value);
    frame->base.release(&frame->base);
}

- (void)goBack {
    @synchronized (self) {
        cef_browser_t *browser = [self activeBrowser];
        if (browser != nullptr && browser->go_back != nullptr) {
            browser->go_back(browser);
        }
    }
}

- (void)goForward {
    @synchronized (self) {
        cef_browser_t *browser = [self activeBrowser];
        if (browser != nullptr && browser->go_forward != nullptr) {
            browser->go_forward(browser);
        }
    }
}

- (void)reload {
    @synchronized (self) {
        cef_browser_t *browser = [self activeBrowser];
        if (browser != nullptr && browser->reload != nullptr) {
            browser->reload(browser);
        }
    }
}

- (void)reloadIgnoringCache {
    @synchronized (self) {
        cef_browser_t *browser = [self activeBrowser];
        if (browser != nullptr && browser->reload_ignore_cache != nullptr) {
            browser->reload_ignore_cache(browser);
        }
    }
}

- (NSString *)currentURL { return _currentURL ?: @""; }
- (NSString *)currentTitle { return _currentTitle ?: @""; }
- (BOOL)isLoading {
    cef_browser_t *browser = [self activeBrowser];
    return browser != nullptr && browser->is_loading != nullptr ? browser->is_loading(browser) != 0 : _isLoading;
}
- (BOOL)canGoBack {
    cef_browser_t *browser = [self activeBrowser];
    return browser != nullptr && browser->can_go_back != nullptr ? browser->can_go_back(browser) != 0 : _canGoBack;
}
- (BOOL)canGoForward {
    cef_browser_t *browser = [self activeBrowser];
    return browser != nullptr && browser->can_go_forward != nullptr ? browser->can_go_forward(browser) != 0 : _canGoForward;
}

- (void)evaluateJavaScript:(NSString *)script
                completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    cef_frame_t *frame = [self copyMainFrame];
    if (frame == nullptr || frame->execute_java_script == nullptr) {
        if (frame != nullptr) {
            frame->base.release(&frame->base);
        }
        if (completion != nil) {
            completion(nil, [NSError errorWithDomain:kCEFBridgeErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"CEF browser frame is unavailable"}]);
        }
        return;
    }

    NSString *identifier = [NSString stringWithFormat:@"%@-%ld", _identifier ?: @"cef", (long)++_nextEvalID];
    if (completion != nil) {
        @synchronized (self) {
            _pendingEvalBlocks[identifier] = [completion copy];
        }
    }

    NSString *wrapped = [NSString stringWithFormat:
                         @"(function(){const __mId=%@;const __mScript=%@;Promise.resolve().then(function(){return (0,eval)(__mScript);}).then(function(value){try{console.log('%@'+JSON.stringify({id:__mId,ok:true,value:value===undefined?null:value}));}catch(error){console.log('%@'+JSON.stringify({id:__mId,ok:true,value:String(value)}));}}).catch(function(error){console.log('%@'+JSON.stringify({id:__mId,ok:false,error:String(error)}));});})();",
                         CEFBridgeJSONStringForValue(identifier),
                         CEFBridgeJSONStringForValue(script ?: @"undefined"),
                         kEvalConsolePrefix,
                         kEvalConsolePrefix,
                         kEvalConsolePrefix];

    cef_string_t code = CEFBridgeStringCreate(wrapped);
    cef_string_t sourceURL = CEFBridgeStringCreate(@"kelpie://evaluate.js");
    frame->execute_java_script(frame, &code, &sourceURL, 1);
    CEFBridgeStringClear(&code);
    CEFBridgeStringClear(&sourceURL);
    frame->base.release(&frame->base);
}

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

- (void)deleteAllCookiesWithCompletion:(void (^)(NSInteger deleted))completion {
    CEFBridgeDeleteAllCookies(_cookieManager, completion);
}

- (void)flushCookieStoreWithCompletion:(void (^)(void))completion {
    CEFBridgeFlushCookieStore(_cookieManager, completion);
}

- (void)takeScreenshotWithCompletion:(void (^)(NSData * _Nullable pngData))completion {
    NSView *view = _parentView;
    if (view == nil || completion == nil) {
        if (completion != nil) {
            completion(nil);
        }
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        NSWindow *window = view.window;
        cef_browser_host_t *host = CopyBrowserHost([self activeBrowser]);
        if (host != nullptr) {
            const CGSize logicalSize = view.bounds.size;
            CEFBridgeCaptureScreenshot(host, logicalSize, ^(NSData * _Nullable pngData) {
                if (pngData != nil) {
                    completion(pngData);
                } else if (window != nil && (window.styleMask & NSWindowStyleMaskFullScreen) == 0) {
                    CaptureWithExpandedWindowIfNeeded(view, window, completion);
                } else if (window != nil) {
                    completion(WindowCropPNGData(view, window, nil) ?: CachedViewPNGData(view));
                } else {
                    completion(CachedViewPNGData(view));
                }
            });
            host->base.release(&host->base);
            return;
        }

        if (window != nil && (window.styleMask & NSWindowStyleMaskFullScreen) == 0) {
            CaptureWithExpandedWindowIfNeeded(view, window, completion);
            return;
        } else if (window != nil) {
            if (NSData *pngData = WindowCropPNGData(view, window, nil)) {
                completion(pngData);
                return;
            }
        }

        completion(CachedViewPNGData(view));
    });
}

- (void)resizeTo:(NSSize)size {
    NSView *view = _parentView;
    if (view == nil) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        view.frame = NSMakeRect(view.frame.origin.x, view.frame.origin.y, size.width, size.height);
        for (NSView *subview in view.subviews) {
            subview.frame = view.bounds;
            subview.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        }
        [view layoutSubtreeIfNeeded];

        cef_browser_host_t *host = CopyBrowserHost([self activeBrowser]);
        if (host != nullptr) {
            if (host->notify_move_or_resize_started != nullptr) {
                host->notify_move_or_resize_started(host);
            }
            if (host->notify_screen_info_changed != nullptr) {
                host->notify_screen_info_changed(host);
            }
            if (host->was_resized != nullptr) {
                host->was_resized(host);
            }
            if (host->set_focus != nullptr) {
                host->set_focus(host, 1);
            }
            host->base.release(&host->base);
        }
    });
}

- (void)cefBridgeDidCreateBrowser:(cef_browser_t *)browser {
    if (browser == nullptr) {
        NSLog(@"[CEFBridge] didCreateBrowser browser=nil");
        return;
    }
    @synchronized (self) {
        if (_callbackBrowser != nullptr) {
            _callbackBrowser->base.release(&_callbackBrowser->base);
        }
        _callbackBrowser = browser;
        browser->base.add_ref(&browser->base);
        _canGoBack = browser->can_go_back ? browser->can_go_back(browser) != 0 : NO;
        _canGoForward = browser->can_go_forward ? browser->can_go_forward(browser) != 0 : NO;
        _isLoading = browser->is_loading ? browser->is_loading(browser) != 0 : NO;
    }
    NSLog(
        @"[CEFBridge] didCreateBrowser callback=%@ created=%@ active=%@ parentSubviews=%lu",
        DescribeBrowser(_callbackBrowser),
        DescribeBrowser(_createdBrowser),
        DescribeBrowser([self activeBrowser]),
        (unsigned long)_parentView.subviews.count
    );
    LogBrowserHandles("did_create_browser", _callbackBrowser, _createdBrowser, [self activeBrowser]);
    NotifyStateChange(self);
}

- (void)cefBridgeWillCloseBrowser {
    @synchronized (self) {
        if (_callbackBrowser != nullptr) {
            CEFBridgeInvalidateScreenshotCapture(_callbackBrowser);
        }
        if (_createdBrowser != nullptr) {
            CEFBridgeInvalidateScreenshotCapture(_createdBrowser);
        }
        if (_callbackBrowser != nullptr) {
            _callbackBrowser->base.release(&_callbackBrowser->base);
            _callbackBrowser = nullptr;
        }
        if (_createdBrowser != nullptr) {
            _createdBrowser->base.release(&_createdBrowser->base);
            _createdBrowser = nullptr;
        }
    }
}

- (void)cefBridgeUpdateLoadingStateWithIsLoading:(BOOL)isLoading
                                       canGoBack:(BOOL)canGoBack
                                    canGoForward:(BOOL)canGoForward {
    _isLoading = isLoading;
    cef_browser_t *browser = [self activeBrowser];
    if (browser != nullptr) {
        _canGoBack = browser->can_go_back ? browser->can_go_back(browser) != 0 : canGoBack;
        _canGoForward = browser->can_go_forward ? browser->can_go_forward(browser) != 0 : canGoForward;
    } else {
        _canGoBack = canGoBack;
        _canGoForward = canGoForward;
    }
    NotifyStateChange(self);
}

- (void)cefBridgeUpdateCurrentURL:(NSString *)url {
    _currentURL = url ?: @"";
    NotifyStateChange(self);
}

- (void)cefBridgeUpdateCurrentTitle:(NSString *)title {
    _currentTitle = title ?: @"";
    NotifyStateChange(self);
}

- (void)cefBridgeUpdateLoadingProgress:(double)progress {
    _loadingProgress = progress;
}

- (void)cefBridgeHandleConsoleMessage:(NSString *)message
                               source:(NSString *)source
                                 line:(NSInteger)line {
    if ([message hasPrefix:kEvalConsolePrefix]) {
        NSString *payload = [message substringFromIndex:kEvalConsolePrefix.length];
        NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *decoded = data != nil ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *identifier = decoded[@"id"];
        if ([decoded[@"ok"] boolValue]) {
            FinishEval(self, identifier, CEFBridgeJSONStringForValue(decoded[@"value"]), nil);
        } else {
            NSString *messageText = decoded[@"error"] ?: @"JavaScript evaluation failed";
            NSError *error = [NSError errorWithDomain:kCEFBridgeErrorDomain code:3 userInfo:@{NSLocalizedDescriptionKey: messageText}];
            FinishEval(self, identifier, nil, error);
        }
        return;
    }

    if (self.onConsoleMessage != nil) {
        NSDictionary *payload = @{
            @"message": message ?: @"",
            @"source": source ?: @"",
            @"line": @(line),
        };
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.onConsoleMessage != nil) {
                self.onConsoleMessage(payload);
            }
        });
    }
}

@end
