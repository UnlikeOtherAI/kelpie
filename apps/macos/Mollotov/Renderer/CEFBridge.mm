#import "CEFBridge.h"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#include "include/capi/cef_app_capi.h"
#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_frame_capi.h"

#import "CEFBridgeSupport.h"

static NSString *const kCEFBridgeErrorDomain = @"com.mollotov.browser.cef";
static NSString *const kEvalConsolePrefix = @"__mollotov_eval__:";

static BOOL gCEFInitialized = NO;

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
    cef_browser_t *_browser;
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

    NSString *helperExecutable = [[NSBundle mainBundle].privateFrameworksPath stringByAppendingPathComponent:@"MollotovHelper.app/Contents/MacOS/MollotovHelper"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:helperExecutable]) {
        NSLog(@"[CEF] FATAL: MollotovHelper.app not found at expected path: %@", helperExecutable);
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

    NSString *cachePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"mollotov-cef-cache"];
    [[NSFileManager defaultManager] createDirectoryAtPath:cachePath withIntermediateDirectories:YES attributes:nil error:nil];
    cef_string_t cachePathCEF = CEFBridgeStringCreate(cachePath);
    settings.cache_path = cachePathCEF;

    const int ok = cef_initialize(&mainArgs, &settings, nullptr, nullptr);
    CEFBridgeStringClear(&settings.browser_subprocess_path);
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
    windowInfo.parent_view = (__bridge void *)parentView;

    cef_browser_settings_t settings = {};
    settings.size = sizeof(settings);

    cef_string_t initialURL = CEFBridgeStringCreate(_currentURL);
    _browser = cef_browser_host_create_browser_sync(&windowInfo, CEFBridgeClientHandle(_client), &initialURL, &settings, nullptr, nullptr);
    CEFBridgeStringClear(&initialURL);
    return self;
}

- (void)dealloc {
    @synchronized (self) {
        if (_browser != nullptr) {
            _browser->base.release(&_browser->base);
            _browser = nullptr;
        }
        if (_client != nullptr) {
            CEFBridgeReleaseClient(_client);
            _client = nullptr;
        }
    }
}

- (cef_frame_t *)mainFrame {
    @synchronized (self) {
        if (_browser == nullptr || _browser->get_main_frame == nullptr) {
            return nullptr;
        }
        return _browser->get_main_frame(_browser);
    }
}

- (void)loadURL:(NSString *)url {
    cef_frame_t *frame = [self mainFrame];
    if (frame == nullptr || frame->load_url == nullptr) {
        return;
    }

    cef_string_t value = CEFBridgeStringCreate(url ?: @"about:blank");
    frame->load_url(frame, &value);
    CEFBridgeStringClear(&value);
}

- (void)goBack {
    @synchronized (self) {
        if (_browser != nullptr && _browser->go_back != nullptr) {
            _browser->go_back(_browser);
        }
    }
}

- (void)goForward {
    @synchronized (self) {
        if (_browser != nullptr && _browser->go_forward != nullptr) {
            _browser->go_forward(_browser);
        }
    }
}

- (void)reload {
    @synchronized (self) {
        if (_browser != nullptr && _browser->reload != nullptr) {
            _browser->reload(_browser);
        }
    }
}

- (NSString *)currentURL { return _currentURL ?: @""; }
- (NSString *)currentTitle { return _currentTitle ?: @""; }
- (BOOL)isLoading { return _browser != nullptr && _browser->is_loading != nullptr ? _browser->is_loading(_browser) != 0 : _isLoading; }
- (BOOL)canGoBack { return _browser != nullptr && _browser->can_go_back != nullptr ? _browser->can_go_back(_browser) != 0 : _canGoBack; }
- (BOOL)canGoForward { return _browser != nullptr && _browser->can_go_forward != nullptr ? _browser->can_go_forward(_browser) != 0 : _canGoForward; }

- (void)evaluateJavaScript:(NSString *)script
                completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    cef_frame_t *frame = [self mainFrame];
    if (frame == nullptr || frame->execute_java_script == nullptr) {
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
    cef_string_t sourceURL = CEFBridgeStringCreate(@"mollotov://evaluate.js");
    frame->execute_java_script(frame, &code, &sourceURL, 1);
    CEFBridgeStringClear(&code);
    CEFBridgeStringClear(&sourceURL);
}

- (void)getAllCookiesWithCompletion:(void (^)(NSArray<NSDictionary *> *cookies))completion {
    CEFBridgeVisitAllCookies(completion);
}

- (void)setCookieName:(NSString *)name
                value:(NSString *)value
               domain:(NSString *)domain
                 path:(NSString *)path
             httpOnly:(BOOL)httpOnly
               secure:(BOOL)secure
              expires:(NSDate * _Nullable)expires
           completion:(void (^)(BOOL success))completion {
    CEFBridgeSetCookie(name, value, domain, path, httpOnly, secure, expires, completion);
}

- (void)deleteAllCookiesWithCompletion:(void (^)(NSInteger deleted))completion {
    CEFBridgeDeleteAllCookies(completion);
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
        NSRect bounds = view.bounds;
        NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:bounds];
        if (bitmap == nil) {
            completion(nil);
            return;
        }
        [view cacheDisplayInRect:bounds toBitmapImageRep:bitmap];
        completion([bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]);
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
    });
}

- (void)cefBridgeDidCreateBrowser:(cef_browser_t *)browser {
    if (browser == nullptr) {
        return;
    }
    @synchronized (self) {
        if (_browser == nullptr) {
            _browser = browser;
            browser->base.add_ref(&browser->base);
        }
        _canGoBack = browser->can_go_back ? browser->can_go_back(browser) != 0 : NO;
        _canGoForward = browser->can_go_forward ? browser->can_go_forward(browser) != 0 : NO;
        _isLoading = browser->is_loading ? browser->is_loading(browser) != 0 : NO;
    }
    NotifyStateChange(self);
}

- (void)cefBridgeWillCloseBrowser {
    @synchronized (self) {
        if (_browser != nullptr) {
            _browser->base.release(&_browser->base);
            _browser = nullptr;
        }
    }
}

- (void)cefBridgeUpdateLoadingStateWithIsLoading:(BOOL)isLoading
                                       canGoBack:(BOOL)canGoBack
                                    canGoForward:(BOOL)canGoForward {
    _isLoading = isLoading;
    if (_browser != nullptr) {
        _canGoBack = _browser->can_go_back ? _browser->can_go_back(_browser) != 0 : canGoBack;
        _canGoForward = _browser->can_go_forward ? _browser->can_go_forward(_browser) != 0 : canGoForward;
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
