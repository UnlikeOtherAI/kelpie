#import "CEFBridge_Internal.h"

#include <atomic>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

// New-window opens Kelpie replays as tabs, and app links (`slack:`, `mailto:`)
// Chromium cannot load. Both run on the CEF UI thread, which is the main thread.

struct RequestHandler {
    cef_request_handler_t handler;
    std::atomic<int> refCount;
    __unsafe_unretained CEFBridge *owner;
};

static RequestHandler *RequestHandlerFromBase(cef_base_ref_counted_t *base) {
    return reinterpret_cast<RequestHandler *>(reinterpret_cast<uint8_t *>(base) - offsetof(RequestHandler, handler));
}

static void RequestAddRef(cef_base_ref_counted_t *base) {
    RequestHandlerFromBase(base)->refCount.fetch_add(1, std::memory_order_relaxed);
}

static int RequestRelease(cef_base_ref_counted_t *base) {
    RequestHandler *handler = RequestHandlerFromBase(base);
    if (handler->refCount.fetch_sub(1, std::memory_order_acq_rel) == 1) {
        delete handler;
        return 1;
    }
    return 0;
}

static int RequestHasOneRef(cef_base_ref_counted_t *base) {
    return RequestHandlerFromBase(base)->refCount.load(std::memory_order_acquire) == 1 ? 1 : 0;
}

static int RequestHasAtLeastOneRef(cef_base_ref_counted_t *base) {
    return RequestHandlerFromBase(base)->refCount.load(std::memory_order_acquire) >= 1 ? 1 : 0;
}

/// Schemes Chromium loads itself. Everything else belongs to another app.
static BOOL IsAppLink(NSURL *url) {
    static NSSet<NSString *> *webSchemes = [NSSet setWithArray:@[
        @"http", @"https", @"about", @"data", @"blob", @"file", @"javascript", @"chrome", @"chrome-error",
        @"chrome-extension", @"devtools", @"view-source", @"filesystem", @"ws", @"wss"
    ]];
    NSString *scheme = url.scheme.lowercaseString;
    return scheme.length > 0 && ![webSchemes containsObject:scheme];
}

/// `scheme://host[:port]` for http(s) pages, otherwise nil.
static NSString *_Nullable OriginOf(NSURL *url) {
    NSString *scheme = url.scheme.lowercaseString;
    if (url.host.length == 0 || !([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"])) return nil;
    NSString *port = url.port != nil ? [@":" stringByAppendingString:url.port.stringValue] : @"";
    return [NSString stringWithFormat:@"%@://%@%@", scheme, url.host.lowercaseString, port];
}

static int OnBeforeBrowse(cef_request_handler_t *self, cef_browser_t *browser, cef_frame_t *frame,
                          cef_request_t *request, int userGesture, int) {
    NSURL *target = [NSURL URLWithString:CEFBridgeStringFromUserFree(request->get_url(request))];
    const BOOL appLink = target != nil && IsAppLink(target);
    if (appLink) {
        CEFBridge *owner = RequestHandlerFromBase(&self->base)->owner;
        NSURL *source = [NSURL URLWithString:CEFBridgeStringFromUserFree(frame->get_url(frame))];
        NSString *requester = source ? OriginOf(source) : nil;
        BOOL fromPage = frame->is_main(frame) != 0;
        if (!fromPage && requester != nil) {
            // Only a frame of the page's own origin may ask; third-party frames cannot.
            cef_frame_t *main = browser->get_main_frame(browser);
            NSURL *page = main ? [NSURL URLWithString:CEFBridgeStringFromUserFree(main->get_url(main))] : nil;
            if (main) main->base.release(&main->base);
            fromPage = page != nil && [requester isEqualToString:OriginOf(page) ?: @""];
        }
        [owner cefBridgeRequestAppLink:target requester:requester fromPage:fromPage userGesture:userGesture != 0];
    }
    // The C API transfers one reference to each ref-counted callback argument.
    browser->base.release(&browser->base);
    frame->base.release(&frame->base);
    request->base.release(&request->base);
    return appLink ? 1 : 0;
}

cef_request_handler_t *CEFBridgeCreateRequestHandler(CEFBridge * _Nullable owner) {
    RequestHandler *handler = new RequestHandler();
    memset(&handler->handler, 0, sizeof(handler->handler));
    handler->refCount = 1;
    handler->owner = owner;
    handler->handler.base.size = sizeof(handler->handler);
    handler->handler.base.add_ref = RequestAddRef;
    handler->handler.base.release = RequestRelease;
    handler->handler.base.has_one_ref = RequestHasOneRef;
    handler->handler.base.has_at_least_one_ref = RequestHasAtLeastOneRef;
    handler->handler.on_before_browse = OnBeforeBrowse;
    return &handler->handler;
}

void CEFBridgeNullifyRequestHandler(cef_request_handler_t *handler) {
    if (handler != nullptr) RequestHandlerFromBase(&handler->base)->owner = nil;
}

int CEFBridgeOpenPopupAsTab(CEFBridge *owner, const cef_string_t *targetURL,
                            cef_window_open_disposition_t disposition) {
    // Chromium cannot hand its new context to a tab, so a tab is replayed from
    // the URL. Only a real page URL is replayed; a pop-up, or a blank window the
    // opener writes into or navigates later, stays native.
    if (owner == nil || disposition == CEF_WOD_NEW_POPUP || targetURL == nullptr) return 0;
    NSString *string = [[NSString alloc] initWithCharacters:(const unichar *)targetURL->str length:targetURL->length];
    NSURL *url = [NSURL URLWithString:string];
    if (url == nil || OriginOf(url) == nil) return 0;
    void (^openTab)(NSURL *) = owner.onOpenTab;
    if (openTab == nil) return 0;
    dispatch_async(dispatch_get_main_queue(), ^{ openTab(url); });
    return 1;
}

@implementation CEFBridge (NewWindows)

- (void)cefBridgeResetAppLinkAllowance {
    _appLinkAsked = NO;
}

- (void)cefBridgeRequestAppLink:(NSURL *)url requester:(nullable NSString *)requester
                       fromPage:(BOOL)fromPage userGesture:(BOOL)userGesture {
    // A link activation may always ask; otherwise a document asks once, which
    // covers launch pages that redirect to their app without letting them loop.
    if (!fromPage || (!userGesture && _appLinkAsked)) return;
    if (!userGesture) _appLinkAsked = YES;
    void (^request)(NSURL *, NSString *_Nullable) = self.onAppLinkRequest;
    if (request != nil) dispatch_async(dispatch_get_main_queue(), ^{ request(url, requester); });
}

@end
