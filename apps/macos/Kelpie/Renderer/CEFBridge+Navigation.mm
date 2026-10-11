#import "CEFBridge_Internal.h"

/// Native main-frame state and identity are updated by CEF's load callbacks.
@implementation CEFBridge (Navigation)
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
    if (statusCode == 0) {
        @synchronized (self) { _documentVersion = NSUUID.UUID.UUIDString; ++_documentNavigationCount; }
    }
}

- (NSString *)documentVersion {
    @synchronized (self) {
        if (!_documentVersion) _documentVersion = NSUUID.UUID.UUIDString;
        return _documentVersion;
    }
}

- (NSUInteger)documentNavigationCount {
    @synchronized (self) { return _documentNavigationCount; }
}

- (NSInteger)mainFrameHTTPStatusCode { return _mainFrameHTTPStatusCode; }

- (void)cefBridgeUpdateCurrentTitle:(NSString *)title {
    _currentTitle = title ?: @"";
    CEFBridgeNotifyStateChange(self);
}

- (void)cefBridgeUpdateLoadingProgress:(double)progress { _loadingProgress = progress; }
@end
