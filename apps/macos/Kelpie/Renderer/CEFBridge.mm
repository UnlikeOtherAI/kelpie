#import "CEFBridge_Internal.h"

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString *const kCEFBridgeErrorDomain = @"com.kelpie.browser.cef";
static NSString *const kEvalConsolePrefix = @"__kelpie_eval__:";

// Upper bound on how long a single evaluateJavaScript call may stay pending.
// The eval result is delivered back through the page's console (see the wrapped
// script in -evaluateJavaScript:completion:). That channel never fires if the
// script returns a never-resolving promise, the frame is torn down mid-eval, or
// the page replaces window.console.log (so Chromium's native console sink is
// never hit). Without a bound the continuation waits forever and the request
// hangs — see GitHub issues #23/#24. This is a safety backstop; normal evals
// complete in milliseconds.
static const NSTimeInterval kEvalTimeoutSeconds = 30.0;

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

- (void)_failAllPendingEvalsWithError:(NSError *)error {
    NSArray *blocks = nil;
    @synchronized (self) {
        blocks = _pendingEvalBlocks.allValues;
        [_pendingEvalBlocks removeAllObjects];
    }
    for (id block in blocks) {
        void (^completion)(NSString *, NSError *) = block;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, error);
        });
    }
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
        CEFBridgeDescribeBrowser(createdBrowser),
        (unsigned long)parentView.subviews.count
    );
    CEFBridgeLogBrowserHandles("create_browser_sync", _callbackBrowser, _createdBrowser, [self activeBrowser]);
    return self;
}

- (void)closeBrowser {
    // Force-close the browser so CEF can tear down CrBrowserMain and all
    // internal threads cleanly before this bridge is released. Without this,
    // releasing the browser handle leaves CEF's internal state half-alive,
    // and creating a new browser (on renderer switch) collides with it.
    cef_browser_host_t *host = CEFBridgeCopyBrowserHost([self activeBrowser]);
    if (host == nullptr) { return; }
    if (host->close_browser != nullptr) {
        host->close_browser(host, 1); // force=1: skip JS unload, close immediately
    }
    host->base.release(&host->base);
    // Drain CEF's message queue so the close events are processed before
    // the caller releases this object.
    for (int i = 0; i < 30; i++) {
        cef_do_message_loop_work();
    }
}

- (void)setHidden:(BOOL)hidden {
    cef_browser_host_t *host = CEFBridgeCopyBrowserHost([self activeBrowser]);
    if (host == nullptr) { return; }
    if (host->was_hidden != nullptr) {
        host->was_hidden(host, hidden ? 1 : 0);
    }
    host->base.release(&host->base);
}

- (void)dealloc {
    // Resolve any still-pending evals so their continuations don't leak when the
    // bridge is torn down (e.g. renderer switch) before a result arrives.
    [self _failAllPendingEvalsWithError:[NSError
        errorWithDomain:kCEFBridgeErrorDomain
                   code:5
               userInfo:@{NSLocalizedDescriptionKey: @"CEF bridge released before evaluation completed"}]];
    @synchronized (self) {
        // Nil out all owner back-pointers before releasing CEF handles.
        // The 60 Hz message-loop timer can fire cef_do_message_loop_work()
        // between here and the next run-loop iteration, invoking callbacks
        // through these pointers. Clearing them first turns those callbacks
        // into safe no-ops instead of dangling-pointer crashes.
        CEFBridgeNullifyClientOwner(_client);
        if (_callbackBrowser != nullptr) {
            CEFBridgeInvalidateScreenshotCapture(_callbackBrowser);
            CEFBridgeInvalidateCookieObserver(_callbackBrowser);
        }
        if (_createdBrowser != nullptr) {
            CEFBridgeInvalidateScreenshotCapture(_createdBrowser);
            CEFBridgeInvalidateCookieObserver(_createdBrowser);
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
        NSLog(@"[CEFBridge] mainFrame unavailable active=nil created=%@ callback=%@", CEFBridgeDescribeBrowser(_createdBrowser), CEFBridgeDescribeBrowser(_callbackBrowser));
        CEFBridgeLogBrowserHandles("main_frame_unavailable_nil", _callbackBrowser, _createdBrowser, browser);
        return nullptr;
    }

    cef_frame_t *frame = CEFBridgeCopyMainFrame(browser);
    if (frame == nullptr) {
        NSLog(@"[CEFBridge] mainFrame returned null active=%@ created=%@ callback=%@", CEFBridgeDescribeBrowser(browser), CEFBridgeDescribeBrowser(_createdBrowser), CEFBridgeDescribeBrowser(_callbackBrowser));
        CEFBridgeLogBrowserHandles("main_frame_unavailable_null", _callbackBrowser, _createdBrowser, browser);
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

    NSString *identifier;
    @synchronized (self) {
        // Both the id increment and the pending-block registration happen under
        // the lock so the eval bookkeeping stays consistent regardless of caller
        // thread (today every caller is on the @MainActor CEFRenderer).
        identifier = [NSString stringWithFormat:@"%@-%ld", _identifier ?: @"cef", (long)++_nextEvalID];
        if (completion != nil) {
            _pendingEvalBlocks[identifier] = [completion copy];
        }
    }
    if (completion != nil) {
        // Backstop: if the console result channel never delivers, resolve the
        // pending block with a timeout error so the caller's continuation can
        // never wait forever. -_finishEvalWithIdentifier: atomically removes the
        // block, so whichever fires first (real result or this timeout) wins and
        // the loser is a no-op — the completion runs exactly once.
        __weak CEFBridge *weakSelf = self;
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kEvalTimeoutSeconds * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{
                NSError *timeoutError = [NSError
                    errorWithDomain:kCEFBridgeErrorDomain
                               code:4
                           userInfo:@{NSLocalizedDescriptionKey: @"JavaScript evaluation timed out"}];
                [weakSelf _finishEvalWithIdentifier:identifier result:nil error:timeoutError];
            });
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
        CEFBridgeDescribeBrowser(_callbackBrowser),
        CEFBridgeDescribeBrowser(_createdBrowser),
        CEFBridgeDescribeBrowser([self activeBrowser]),
        (unsigned long)_parentView.subviews.count
    );
    CEFBridgeLogBrowserHandles("did_create_browser", _callbackBrowser, _createdBrowser, [self activeBrowser]);
    CEFBridgeNotifyStateChange(self);
}

- (void)cefBridgeWillCloseBrowser {
    // The frame is going away, so any pending eval's console result can never
    // arrive. Resolve them now instead of leaving callers blocked until the
    // per-eval timeout fires.
    [self _failAllPendingEvalsWithError:[NSError
        errorWithDomain:kCEFBridgeErrorDomain
                   code:5
               userInfo:@{NSLocalizedDescriptionKey: @"CEF browser closed before evaluation completed"}]];
    @synchronized (self) {
        if (_callbackBrowser != nullptr) {
            CEFBridgeInvalidateScreenshotCapture(_callbackBrowser);
            CEFBridgeInvalidateCookieObserver(_callbackBrowser);
        }
        if (_createdBrowser != nullptr) {
            CEFBridgeInvalidateScreenshotCapture(_createdBrowser);
            CEFBridgeInvalidateCookieObserver(_createdBrowser);
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
    CEFBridgeNotifyStateChange(self);
}

- (void)cefBridgeUpdateCurrentURL:(NSString *)url {
    _currentURL = url ?: @"";
    CEFBridgeNotifyStateChange(self);
}

- (void)cefBridgeUpdateMainFrameHTTPStatusCode:(NSInteger)statusCode {
    _mainFrameHTTPStatusCode = statusCode;
}

- (NSInteger)mainFrameHTTPStatusCode { return _mainFrameHTTPStatusCode; }

- (void)cefBridgeUpdateCurrentTitle:(NSString *)title {
    _currentTitle = title ?: @"";
    CEFBridgeNotifyStateChange(self);
}

- (void)cefBridgeUpdateLoadingProgress:(double)progress {
    _loadingProgress = progress;
}

@end
