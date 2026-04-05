#import "CEFBridgeSupport.h"

#import <crt_externs.h>

#include <atomic>
#include <mutex>
#include <stddef.h>
#include <string.h>
#include <unordered_map>

static inline NSString *StringFromCEFString(const cef_string_t *value) {
    if (value == nullptr || value->str == nullptr || value->length == 0) {
        return @"";
    }
    return [[NSString alloc] initWithCharacters:(const unichar *)value->str length:value->length];
}

static char **sAugmentedArgv = nullptr;
static int sAugmentedArgc = 0;
static const char *kUseMockKeychainArg = "--use-mock-keychain";

cef_main_args_t CEFBridgeMainArgs(void) {
    if (sAugmentedArgv == nullptr) {
        int origArgc = *_NSGetArgc();
        char **origArgv = *_NSGetArgv();
        // Inject --use-mock-keychain to prevent Keychain password prompts.
        sAugmentedArgc = origArgc + 1;
        sAugmentedArgv = (char **)calloc(sAugmentedArgc + 1, sizeof(char *));
        for (int i = 0; i < origArgc; i++) {
            sAugmentedArgv[i] = origArgv[i];
        }
        sAugmentedArgv[origArgc] = (char *)kUseMockKeychainArg;
    }
    cef_main_args_t args = {};
    args.argc = sAugmentedArgc;
    args.argv = sAugmentedArgv;
    return args;
}

cef_string_t CEFBridgeStringCreate(NSString *value) {
    cef_string_t result = {};
    const char *utf8 = value.length > 0 ? value.UTF8String : "";
    cef_string_utf8_to_utf16(utf8, strlen(utf8), &result);
    return result;
}

void CEFBridgeStringClear(cef_string_t *value) {
    if (value != nullptr) {
        cef_string_clear(value);
    }
}

NSString *CEFBridgeStringFromUserFree(cef_string_userfree_t value) {
    if (value == nullptr) {
        return @"";
    }
    NSString *result = StringFromCEFString(value);
    cef_string_userfree_free(value);
    return result;
}

NSString *CEFBridgeJSONStringForValue(id value) {
    id jsonValue = value ?: [NSNull null];
    if ([NSJSONSerialization isValidJSONObject:jsonValue]) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:jsonValue options:0 error:nil];
        if (data != nil) {
            return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
    }

    NSData *wrapped = [NSJSONSerialization dataWithJSONObject:@[jsonValue] options:0 error:nil];
    if (wrapped == nil) {
        return @"null";
    }
    NSString *string = [[NSString alloc] initWithData:wrapped encoding:NSUTF8StringEncoding];
    if (string.length >= 2 && [string hasPrefix:@"["] && [string hasSuffix:@"]"]) {
        return [string substringWithRange:NSMakeRange(1, string.length - 2)];
    }
    return string ?: @"null";
}

cef_basetime_t CEFBridgeBaseTimeFromDate(NSDate *value) {
    cef_basetime_t result = {};
    if (value == nil) {
        return result;
    }
    cef_time_t encoded = {};
    if (!cef_time_from_doublet(value.timeIntervalSince1970, &encoded)) {
        return result;
    }
    cef_time_to_basetime(&encoded, &result);
    return result;
}

static inline NSDate *NSDateFromCEFBaseTime(cef_basetime_t value) {
    if (value.val == 0) {
        return nil;
    }
    cef_time_t decoded = {};
    if (!cef_time_from_basetime(value, &decoded)) {
        return nil;
    }
    double seconds = 0;
    if (!cef_time_to_doublet(&decoded, &seconds)) {
        return nil;
    }
    return [NSDate dateWithTimeIntervalSince1970:seconds];
}

template <typename T>
static inline T *StructFromBase(cef_base_ref_counted_t *base, size_t offset) {
    return reinterpret_cast<T *>(reinterpret_cast<uint8_t *>(base) - offset);
}

struct RefCountedState {
    std::atomic<int> count;
};

template <typename T>
static void AddRefImpl(cef_base_ref_counted_t *base, size_t offset) {
    StructFromBase<T>(base, offset)->ref.count.fetch_add(1, std::memory_order_relaxed);
}

template <typename T>
static int ReleaseImpl(cef_base_ref_counted_t *base, size_t offset) {
    T *object = StructFromBase<T>(base, offset);
    if (object->ref.count.fetch_sub(1, std::memory_order_acq_rel) == 1) {
        delete object;
        return 1;
    }
    return 0;
}

template <typename T>
static int HasOneRefImpl(cef_base_ref_counted_t *base, size_t offset) {
    return StructFromBase<T>(base, offset)->ref.count.load(std::memory_order_acquire) == 1 ? 1 : 0;
}

template <typename T>
static int HasAtLeastOneRefImpl(cef_base_ref_counted_t *base, size_t offset) {
    return StructFromBase<T>(base, offset)->ref.count.load(std::memory_order_acquire) >= 1 ? 1 : 0;
}

struct LifeSpanHandler {
    cef_life_span_handler_t handler;
    RefCountedState ref;
    __unsafe_unretained CEFBridge *owner;
};

struct LoadHandler {
    cef_load_handler_t handler;
    RefCountedState ref;
    __unsafe_unretained CEFBridge *owner;
};

struct DisplayHandler {
    cef_display_handler_t handler;
    RefCountedState ref;
    __unsafe_unretained CEFBridge *owner;
};

struct FrameHandler {
    cef_frame_handler_t handler;
    RefCountedState ref;
    __unsafe_unretained CEFBridge *owner;
};

struct BridgeClient {
    cef_client_t client;
    RefCountedState ref;
    __unsafe_unretained CEFBridge *owner;
    LifeSpanHandler *lifeSpan;
    LoadHandler *load;
    DisplayHandler *display;
    FrameHandler *frame;
};

struct CookieVisitor {
    cef_cookie_visitor_t visitor;
    RefCountedState ref;
    __strong NSMutableArray<NSDictionary *> *cookies;
    void (^completion)(NSArray<NSDictionary *> *);
    std::atomic<bool> finished;
};

struct SetCookieCallback {
    cef_set_cookie_callback_t callback;
    RefCountedState ref;
    void (^completion)(BOOL);
};

struct DeleteCookiesCallback {
    cef_delete_cookies_callback_t callback;
    RefCountedState ref;
    void (^completion)(NSInteger);
    std::atomic<bool> finished;
};

struct FlushCallback {
    cef_completion_callback_t callback;
    RefCountedState ref;
    void (^completion)(void);
};

struct DevToolsScreenshotObserver {
    cef_dev_tools_message_observer_t observer;
    RefCountedState ref;
    __strong NSMutableDictionary<NSNumber *, id> *pendingCompletions;
    std::atomic<int> nextMessageID;
    cef_registration_t *registration;
    int browserID;
};

static std::mutex sDevToolsScreenshotObserversMutex;
static std::unordered_map<int, DevToolsScreenshotObserver *> sDevToolsScreenshotObservers;

#define DEFINE_REFCOUNTED_FUNCS(Type, field, Prefix) \
    static void Prefix##AddRef(cef_base_ref_counted_t *base) { AddRefImpl<Type>(base, offsetof(Type, field)); } \
    static int Prefix##Release(cef_base_ref_counted_t *base) { return ReleaseImpl<Type>(base, offsetof(Type, field)); } \
    static int Prefix##HasOneRef(cef_base_ref_counted_t *base) { return HasOneRefImpl<Type>(base, offsetof(Type, field)); } \
    static int Prefix##HasAtLeastOneRef(cef_base_ref_counted_t *base) { return HasAtLeastOneRefImpl<Type>(base, offsetof(Type, field)); }

DEFINE_REFCOUNTED_FUNCS(LifeSpanHandler, handler, LifeSpan)
DEFINE_REFCOUNTED_FUNCS(LoadHandler, handler, Load)
DEFINE_REFCOUNTED_FUNCS(DisplayHandler, handler, Display)
DEFINE_REFCOUNTED_FUNCS(FrameHandler, handler, Frame)
DEFINE_REFCOUNTED_FUNCS(CookieVisitor, visitor, CookieVisitor)
DEFINE_REFCOUNTED_FUNCS(SetCookieCallback, callback, SetCookie)
DEFINE_REFCOUNTED_FUNCS(DeleteCookiesCallback, callback, DeleteCookies)
DEFINE_REFCOUNTED_FUNCS(FlushCallback, callback, Flush)
static void DevToolsScreenshotAddRef(cef_base_ref_counted_t *base) {
    AddRefImpl<DevToolsScreenshotObserver>(base, offsetof(DevToolsScreenshotObserver, observer));
}

static int DevToolsScreenshotRelease(cef_base_ref_counted_t *base) {
    DevToolsScreenshotObserver *observer = StructFromBase<DevToolsScreenshotObserver>(base, offsetof(DevToolsScreenshotObserver, observer));
    if (observer->ref.count.fetch_sub(1, std::memory_order_acq_rel) == 1) {
        if (observer->registration != nullptr) {
            observer->registration->base.release(&observer->registration->base);
            observer->registration = nullptr;
        }
        observer->pendingCompletions = nil;
        delete observer;
        return 1;
    }
    return 0;
}

static int DevToolsScreenshotHasOneRef(cef_base_ref_counted_t *base) {
    return HasOneRefImpl<DevToolsScreenshotObserver>(base, offsetof(DevToolsScreenshotObserver, observer));
}

static int DevToolsScreenshotHasAtLeastOneRef(cef_base_ref_counted_t *base) {
    return HasAtLeastOneRefImpl<DevToolsScreenshotObserver>(base, offsetof(DevToolsScreenshotObserver, observer));
}

static cef_life_span_handler_t *GetLifeSpanHandler(cef_client_t *self) {
    BridgeClient *client = StructFromBase<BridgeClient>(&self->base, offsetof(BridgeClient, client));
    if (client->lifeSpan == nullptr) {
        return nullptr;
    }
    client->lifeSpan->handler.base.add_ref(&client->lifeSpan->handler.base);
    return &client->lifeSpan->handler;
}

static cef_load_handler_t *GetLoadHandler(cef_client_t *self) {
    BridgeClient *client = StructFromBase<BridgeClient>(&self->base, offsetof(BridgeClient, client));
    if (client->load == nullptr) {
        return nullptr;
    }
    client->load->handler.base.add_ref(&client->load->handler.base);
    return &client->load->handler;
}

static cef_display_handler_t *GetDisplayHandler(cef_client_t *self) {
    BridgeClient *client = StructFromBase<BridgeClient>(&self->base, offsetof(BridgeClient, client));
    if (client->display == nullptr) {
        return nullptr;
    }
    client->display->handler.base.add_ref(&client->display->handler.base);
    return &client->display->handler;
}

static cef_frame_handler_t *GetFrameHandler(cef_client_t *self) {
    BridgeClient *client = StructFromBase<BridgeClient>(&self->base, offsetof(BridgeClient, client));
    if (client->frame == nullptr) {
        return nullptr;
    }
    client->frame->handler.base.add_ref(&client->frame->handler.base);
    return &client->frame->handler;
}

static void ClientAddRef(cef_base_ref_counted_t *base) {
    AddRefImpl<BridgeClient>(base, offsetof(BridgeClient, client));
}

static int ClientRelease(cef_base_ref_counted_t *base) {
    BridgeClient *client = StructFromBase<BridgeClient>(base, offsetof(BridgeClient, client));
    if (client->ref.count.fetch_sub(1, std::memory_order_acq_rel) == 1) {
        if (client->lifeSpan != nullptr) {
            client->lifeSpan->handler.base.release(&client->lifeSpan->handler.base);
            client->lifeSpan = nullptr;
        }
        if (client->load != nullptr) {
            client->load->handler.base.release(&client->load->handler.base);
            client->load = nullptr;
        }
        if (client->display != nullptr) {
            client->display->handler.base.release(&client->display->handler.base);
            client->display = nullptr;
        }
        if (client->frame != nullptr) {
            client->frame->handler.base.release(&client->frame->handler.base);
            client->frame = nullptr;
        }
        delete client;
        return 1;
    }
    return 0;
}

static int ClientHasOneRef(cef_base_ref_counted_t *base) {
    return HasOneRefImpl<BridgeClient>(base, offsetof(BridgeClient, client));
}

static int ClientHasAtLeastOneRef(cef_base_ref_counted_t *base) {
    return HasAtLeastOneRefImpl<BridgeClient>(base, offsetof(BridgeClient, client));
}

template <typename T>
static T *CreateHandler(CEFBridge *owner) {
    T *handler = new T();
    memset(handler, 0, sizeof(T));
    handler->ref.count = 1;
    handler->owner = owner;
    handler->handler.base.size = sizeof(handler->handler);
    return handler;
}

static int OnBeforePopup(cef_life_span_handler_t *, cef_browser_t *, cef_frame_t *, int, const cef_string_t *, const cef_string_t *, cef_window_open_disposition_t, int, const cef_popup_features_t *, cef_window_info_t *, cef_client_t **, cef_browser_settings_t *, cef_dictionary_value_t **, int *) {
    return 1;
}

static void OnAfterCreated(cef_life_span_handler_t *self, cef_browser_t *browser) {
    [StructFromBase<LifeSpanHandler>(&self->base, offsetof(LifeSpanHandler, handler))->owner cefBridgeDidCreateBrowser:browser];
}

static int DoClose(cef_life_span_handler_t *, cef_browser_t *) { return 0; }

static void OnBeforeClose(cef_life_span_handler_t *self, cef_browser_t *) {
    [StructFromBase<LifeSpanHandler>(&self->base, offsetof(LifeSpanHandler, handler))->owner cefBridgeWillCloseBrowser];
}

static void OnLoadingStateChange(cef_load_handler_t *self, cef_browser_t *, int isLoading, int canGoBack, int canGoForward) {
    [StructFromBase<LoadHandler>(&self->base, offsetof(LoadHandler, handler))->owner
        cefBridgeUpdateLoadingStateWithIsLoading:isLoading != 0
                                     canGoBack:canGoBack != 0
                                  canGoForward:canGoForward != 0];
}

static void OnLoadStart(cef_load_handler_t *self, cef_browser_t *, cef_frame_t *frame, cef_transition_type_t) {
    if (frame != nullptr && frame->is_main != nullptr && frame->is_main(frame)) {
        [StructFromBase<LoadHandler>(&self->base, offsetof(LoadHandler, handler))->owner
            cefBridgeUpdateCurrentURL:CEFBridgeStringFromUserFree(frame->get_url ? frame->get_url(frame) : nullptr)];
    }
}

static void OnLoadEnd(cef_load_handler_t *self, cef_browser_t *, cef_frame_t *frame, int) {
    if (frame != nullptr && frame->is_main != nullptr && frame->is_main(frame)) {
        CEFBridge *owner = StructFromBase<LoadHandler>(&self->base, offsetof(LoadHandler, handler))->owner;
        [owner cefBridgeUpdateCurrentURL:CEFBridgeStringFromUserFree(frame->get_url ? frame->get_url(frame) : nullptr)];
        [owner cefBridgeUpdateLoadingStateWithIsLoading:NO canGoBack:NO canGoForward:NO];
    }
}

static void OnAddressChange(cef_display_handler_t *self, cef_browser_t *, cef_frame_t *frame, const cef_string_t *url) {
    if (frame != nullptr && frame->is_main != nullptr && frame->is_main(frame)) {
        [StructFromBase<DisplayHandler>(&self->base, offsetof(DisplayHandler, handler))->owner
            cefBridgeUpdateCurrentURL:StringFromCEFString(url)];
    }
}

static void OnTitleChange(cef_display_handler_t *self, cef_browser_t *, const cef_string_t *title) {
    [StructFromBase<DisplayHandler>(&self->base, offsetof(DisplayHandler, handler))->owner
        cefBridgeUpdateCurrentTitle:StringFromCEFString(title)];
}

static void OnLoadingProgressChange(cef_display_handler_t *self, cef_browser_t *, double progress) {
    [StructFromBase<DisplayHandler>(&self->base, offsetof(DisplayHandler, handler))->owner
        cefBridgeUpdateLoadingProgress:progress];
}

static void LogFrameEvent(const char *event, cef_browser_t *browser, cef_frame_t *frame, int reattached) {
    const int browserID = browser != nullptr && browser->get_identifier != nullptr ? browser->get_identifier(browser) : 0;
    const int browserValid = browser != nullptr && browser->is_valid != nullptr ? browser->is_valid(browser) : 0;
    const int frameValid = frame != nullptr && frame->is_valid != nullptr ? frame->is_valid(frame) : 0;
    const int frameMain = frame != nullptr && frame->is_main != nullptr ? frame->is_main(frame) : 0;
    NSString *frameID = frame != nullptr && frame->get_identifier != nullptr
        ? CEFBridgeStringFromUserFree(frame->get_identifier(frame))
        : @"";
    NSString *frameURL = frame != nullptr && frame->get_url != nullptr
        ? CEFBridgeStringFromUserFree(frame->get_url(frame))
        : @"";
    fprintf(
        stderr,
        "[CEFFrame] %s browser=%p(id=%d valid=%d) frame=%p(valid=%d main=%d id=%s url=%s) reattached=%d\n",
        event,
        browser,
        browserID,
        browserValid,
        frame,
        frameValid,
        frameMain,
        frameID.UTF8String ?: "",
        frameURL.UTF8String ?: "",
        reattached
    );
}

static void OnFrameCreated(cef_frame_handler_t *, cef_browser_t *browser, cef_frame_t *frame) {
    LogFrameEvent("created", browser, frame, 0);
}

static void OnFrameDestroyed(cef_frame_handler_t *, cef_browser_t *browser, cef_frame_t *frame) {
    LogFrameEvent("destroyed", browser, frame, 0);
}

static void OnFrameAttached(cef_frame_handler_t *, cef_browser_t *browser, cef_frame_t *frame, int reattached) {
    LogFrameEvent("attached", browser, frame, reattached);
}

static void OnFrameDetached(cef_frame_handler_t *, cef_browser_t *browser, cef_frame_t *frame) {
    LogFrameEvent("detached", browser, frame, 0);
}

static void OnMainFrameChanged(cef_frame_handler_t *, cef_browser_t *browser, cef_frame_t *oldFrame, cef_frame_t *newFrame) {
    LogFrameEvent("main_changed_old", browser, oldFrame, 0);
    LogFrameEvent("main_changed_new", browser, newFrame, 0);
}

static int OnConsoleMessage(cef_display_handler_t *self, cef_browser_t *, cef_log_severity_t, const cef_string_t *message, const cef_string_t *source, int line) {
    [StructFromBase<DisplayHandler>(&self->base, offsetof(DisplayHandler, handler))->owner
        cefBridgeHandleConsoleMessage:StringFromCEFString(message)
                                   source:StringFromCEFString(source)
                                     line:line];
    return 0;
}

BridgeClient *CEFBridgeCreateClient(CEFBridge *owner) {
    BridgeClient *client = new BridgeClient();
    memset(client, 0, sizeof(BridgeClient));
    client->ref.count = 1;
    client->owner = owner;
    client->client.base.size = sizeof(client->client);
    client->client.base.add_ref = ClientAddRef;
    client->client.base.release = ClientRelease;
    client->client.base.has_one_ref = ClientHasOneRef;
    client->client.base.has_at_least_one_ref = ClientHasAtLeastOneRef;
    client->client.get_life_span_handler = GetLifeSpanHandler;
    client->client.get_load_handler = GetLoadHandler;
    client->client.get_display_handler = GetDisplayHandler;
    client->client.get_frame_handler = GetFrameHandler;

    client->lifeSpan = CreateHandler<LifeSpanHandler>(owner);
    client->lifeSpan->handler.base.add_ref = LifeSpanAddRef;
    client->lifeSpan->handler.base.release = LifeSpanRelease;
    client->lifeSpan->handler.base.has_one_ref = LifeSpanHasOneRef;
    client->lifeSpan->handler.base.has_at_least_one_ref = LifeSpanHasAtLeastOneRef;
    client->lifeSpan->handler.on_before_popup = OnBeforePopup;
    client->lifeSpan->handler.on_after_created = OnAfterCreated;
    client->lifeSpan->handler.do_close = DoClose;
    client->lifeSpan->handler.on_before_close = OnBeforeClose;

    client->load = CreateHandler<LoadHandler>(owner);
    client->load->handler.base.add_ref = LoadAddRef;
    client->load->handler.base.release = LoadRelease;
    client->load->handler.base.has_one_ref = LoadHasOneRef;
    client->load->handler.base.has_at_least_one_ref = LoadHasAtLeastOneRef;
    client->load->handler.on_loading_state_change = OnLoadingStateChange;
    client->load->handler.on_load_start = OnLoadStart;
    client->load->handler.on_load_end = OnLoadEnd;

    client->display = CreateHandler<DisplayHandler>(owner);
    client->display->handler.base.add_ref = DisplayAddRef;
    client->display->handler.base.release = DisplayRelease;
    client->display->handler.base.has_one_ref = DisplayHasOneRef;
    client->display->handler.base.has_at_least_one_ref = DisplayHasAtLeastOneRef;
    client->display->handler.on_address_change = OnAddressChange;
    client->display->handler.on_title_change = OnTitleChange;
    client->display->handler.on_loading_progress_change = OnLoadingProgressChange;
    client->display->handler.on_console_message = OnConsoleMessage;

    client->frame = CreateHandler<FrameHandler>(owner);
    client->frame->handler.base.add_ref = FrameAddRef;
    client->frame->handler.base.release = FrameRelease;
    client->frame->handler.base.has_one_ref = FrameHasOneRef;
    client->frame->handler.base.has_at_least_one_ref = FrameHasAtLeastOneRef;
    client->frame->handler.on_frame_created = OnFrameCreated;
    client->frame->handler.on_frame_destroyed = OnFrameDestroyed;
    client->frame->handler.on_frame_attached = OnFrameAttached;
    client->frame->handler.on_frame_detached = OnFrameDetached;
    client->frame->handler.on_main_frame_changed = OnMainFrameChanged;
    return client;
}

cef_client_t *CEFBridgeClientHandle(BridgeClient *client) {
    return client != nullptr ? &client->client : nullptr;
}

void CEFBridgeNullifyClientOwner(BridgeClient *client) {
    if (client == nullptr) { return; }
    client->owner = nil;
    if (client->lifeSpan != nullptr) { client->lifeSpan->owner = nil; }
    if (client->load     != nullptr) { client->load->owner     = nil; }
    if (client->display  != nullptr) { client->display->owner  = nil; }
    if (client->frame    != nullptr) { client->frame->owner    = nil; }
}

void CEFBridgeReleaseClient(BridgeClient *client) {
    if (client != nullptr) {
        client->client.base.release(&client->client.base);
    }
}

cef_cookie_manager_t *CEFBridgeCookieManagerFromBrowser(cef_browser_t *browser) {
    if (browser == nullptr) {
        NSLog(@"[CEFBridge] cookieManagerFromBrowser: browser is nil, falling back to global");
        return cef_cookie_manager_get_global_manager(nullptr);
    }
    cef_browser_host_t *host = browser->get_host != nullptr ? browser->get_host(browser) : nullptr;
    if (host == nullptr) {
        NSLog(@"[CEFBridge] cookieManagerFromBrowser: host is nil, falling back to global");
        return cef_cookie_manager_get_global_manager(nullptr);
    }
    cef_request_context_t *ctx = host->get_request_context != nullptr ? host->get_request_context(host) : nullptr;
    host->base.release(&host->base);
    if (ctx == nullptr) {
        NSLog(@"[CEFBridge] cookieManagerFromBrowser: request context is nil, falling back to global");
        return cef_cookie_manager_get_global_manager(nullptr);
    }
    cef_cookie_manager_t *manager = ctx->get_cookie_manager != nullptr ? ctx->get_cookie_manager(ctx, nullptr) : nullptr;
    ctx->base.base.release(&ctx->base.base);
    if (manager == nullptr) {
        NSLog(@"[CEFBridge] cookieManagerFromBrowser: cookie manager is nil, falling back to global");
        return cef_cookie_manager_get_global_manager(nullptr);
    }
    return manager;
}

static int VisitCookie(cef_cookie_visitor_t *self, const cef_cookie_t *cookie, int count, int total, int *deleteCookie) {
    CookieVisitor *visitor = StructFromBase<CookieVisitor>(&self->base, offsetof(CookieVisitor, visitor));
    if (deleteCookie != nullptr) {
        *deleteCookie = 0;
    }
    if (cookie != nullptr) {
        NSMutableDictionary *dict = [@{
            @"name": StringFromCEFString(&cookie->name),
            @"value": StringFromCEFString(&cookie->value),
            @"domain": StringFromCEFString(&cookie->domain),
            @"path": StringFromCEFString(&cookie->path),
            @"httpOnly": @(cookie->httponly != 0),
            @"secure": @(cookie->secure != 0),
        } mutableCopy];
        NSDate *expires = cookie->has_expires ? NSDateFromCEFBaseTime(cookie->expires) : nil;
        if (expires != nil) {
            dict[@"expires"] = expires;
        }
        [visitor->cookies addObject:dict];
    }
    if (count + 1 >= total && !visitor->finished.exchange(true) && visitor->completion != nil) {
        NSArray<NSDictionary *> *result = [visitor->cookies copy];
        void (^completion)(NSArray<NSDictionary *> *) = [visitor->completion copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result);
        });
    }
    return 1;
}

static void SetCookieComplete(cef_set_cookie_callback_t *self, int success) {
    SetCookieCallback *callback = StructFromBase<SetCookieCallback>(&self->base, offsetof(SetCookieCallback, callback));
    if (callback->completion != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{ callback->completion(success != 0); });
    }
}

static void DeleteCookiesComplete(cef_delete_cookies_callback_t *self, int numDeleted) {
    DeleteCookiesCallback *callback = StructFromBase<DeleteCookiesCallback>(&self->base, offsetof(DeleteCookiesCallback, callback));
    if (!callback->finished.exchange(true) && callback->completion != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{ callback->completion(numDeleted); });
    }
}

static CookieVisitor *CreateCookieVisitor(void (^completion)(NSArray<NSDictionary *> *)) {
    CookieVisitor *visitor = new CookieVisitor();
    memset(visitor, 0, sizeof(CookieVisitor));
    visitor->ref.count = 1;
    visitor->cookies = [NSMutableArray array];
    visitor->completion = [completion copy];
    visitor->finished = false;
    visitor->visitor.base.size = sizeof(visitor->visitor);
    visitor->visitor.base.add_ref = CookieVisitorAddRef;
    visitor->visitor.base.release = CookieVisitorRelease;
    visitor->visitor.base.has_one_ref = CookieVisitorHasOneRef;
    visitor->visitor.base.has_at_least_one_ref = CookieVisitorHasAtLeastOneRef;
    visitor->visitor.visit = VisitCookie;
    return visitor;
}

static SetCookieCallback *CreateSetCookieCallback(void (^completion)(BOOL)) {
    SetCookieCallback *callback = new SetCookieCallback();
    memset(callback, 0, sizeof(SetCookieCallback));
    callback->ref.count = 1;
    callback->completion = [completion copy];
    callback->callback.base.size = sizeof(callback->callback);
    callback->callback.base.add_ref = SetCookieAddRef;
    callback->callback.base.release = SetCookieRelease;
    callback->callback.base.has_one_ref = SetCookieHasOneRef;
    callback->callback.base.has_at_least_one_ref = SetCookieHasAtLeastOneRef;
    callback->callback.on_complete = SetCookieComplete;
    return callback;
}

static DeleteCookiesCallback *CreateDeleteCookiesCallback(void (^completion)(NSInteger)) {
    DeleteCookiesCallback *callback = new DeleteCookiesCallback();
    memset(callback, 0, sizeof(DeleteCookiesCallback));
    callback->ref.count = 1;
    callback->completion = [completion copy];
    callback->finished = false;
    callback->callback.base.size = sizeof(callback->callback);
    callback->callback.base.add_ref = DeleteCookiesAddRef;
    callback->callback.base.release = DeleteCookiesRelease;
    callback->callback.base.has_one_ref = DeleteCookiesHasOneRef;
    callback->callback.base.has_at_least_one_ref = DeleteCookiesHasAtLeastOneRef;
    callback->callback.on_complete = DeleteCookiesComplete;
    return callback;
}

static void FlushComplete(cef_completion_callback_t *self) {
    FlushCallback *callback = StructFromBase<FlushCallback>(&self->base, offsetof(FlushCallback, callback));
    if (callback->completion != nil) {
        void (^comp)(void) = [callback->completion copy];
        dispatch_async(dispatch_get_main_queue(), comp);
    }
}

static FlushCallback *CreateFlushCallback(void (^completion)(void)) {
    FlushCallback *callback = new FlushCallback();
    memset(callback, 0, sizeof(FlushCallback));
    callback->ref.count = 1;
    callback->completion = [completion copy];
    callback->callback.base.size = sizeof(callback->callback);
    callback->callback.base.add_ref = FlushAddRef;
    callback->callback.base.release = FlushRelease;
    callback->callback.base.has_one_ref = FlushHasOneRef;
    callback->callback.base.has_at_least_one_ref = FlushHasAtLeastOneRef;
    callback->callback.on_complete = FlushComplete;
    return callback;
}

static NSData *PNGDataFromDevToolsResult(const void *result, size_t resultSize) {
    if (result == nullptr || resultSize == 0) {
        return nil;
    }
    NSData *jsonData = [NSData dataWithBytes:result length:resultSize];
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    NSString *base64 = [payload isKindOfClass:[NSDictionary class]] ? payload[@"data"] : nil;
    if (![base64 isKindOfClass:[NSString class]] || base64.length == 0) {
        return nil;
    }
    return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

static int OnDevToolsScreenshotMessage(cef_dev_tools_message_observer_t *self,
                                       cef_browser_t *browser,
                                       const void *message,
                                       size_t messageSize);
static void OnDevToolsScreenshotResult(cef_dev_tools_message_observer_t *self,
                                       cef_browser_t *browser,
                                       int messageID,
                                       int success,
                                       const void *result,
                                       size_t resultSize);
static void OnDevToolsScreenshotEvent(cef_dev_tools_message_observer_t *self,
                                      cef_browser_t *browser,
                                      const cef_string_t *method,
                                      const void *params,
                                      size_t paramsSize);
static void OnDevToolsScreenshotAgentAttached(cef_dev_tools_message_observer_t *self,
                                              cef_browser_t *browser);
static void OnDevToolsScreenshotAgentDetached(cef_dev_tools_message_observer_t *self,
                                              cef_browser_t *browser);

static void CompletePendingDevToolsScreenshot(DevToolsScreenshotObserver *observer, int messageID, NSData *pngData) {
    if (observer == nullptr || messageID == 0) {
        return;
    }

    NSNumber *key = @(messageID);
    void (^completion)(NSData * _Nullable) = nil;
    id stored = observer->pendingCompletions[key];
    if (stored != nil) {
        completion = [stored copy];
    }
    [observer->pendingCompletions removeObjectForKey:key];

    if (completion != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(pngData);
        });
    }
}

static void CompleteAllPendingDevToolsScreenshots(DevToolsScreenshotObserver *observer, NSData *pngData) {
    if (observer == nullptr || observer->pendingCompletions.count == 0) {
        return;
    }

    NSArray<NSNumber *> *keys = observer->pendingCompletions.allKeys;
    for (NSNumber *key in keys) {
        CompletePendingDevToolsScreenshot(observer, key.intValue, pngData);
    }
}

static DevToolsScreenshotObserver *CreateDevToolsScreenshotObserver(void) {
    DevToolsScreenshotObserver *observer = new DevToolsScreenshotObserver();
    observer->ref.count = 1;
    observer->pendingCompletions = [NSMutableDictionary dictionary];
    observer->nextMessageID = 1;
    observer->registration = nullptr;
    observer->browserID = 0;
    observer->observer = {};
    observer->observer.base.size = sizeof(observer->observer);
    observer->observer.base.add_ref = DevToolsScreenshotAddRef;
    observer->observer.base.release = DevToolsScreenshotRelease;
    observer->observer.base.has_one_ref = DevToolsScreenshotHasOneRef;
    observer->observer.base.has_at_least_one_ref = DevToolsScreenshotHasAtLeastOneRef;
    observer->observer.on_dev_tools_message = OnDevToolsScreenshotMessage;
    observer->observer.on_dev_tools_method_result = OnDevToolsScreenshotResult;
    observer->observer.on_dev_tools_event = OnDevToolsScreenshotEvent;
    observer->observer.on_dev_tools_agent_attached = OnDevToolsScreenshotAgentAttached;
    observer->observer.on_dev_tools_agent_detached = OnDevToolsScreenshotAgentDetached;
    return observer;
}

static DevToolsScreenshotObserver *CopyDevToolsScreenshotObserver(cef_browser_host_t *host) {
    if (host == nullptr || host->get_browser == nullptr || host->add_dev_tools_message_observer == nullptr) {
        return nullptr;
    }

    cef_browser_t *browser = host->get_browser(host);
    if (browser == nullptr) {
        return nullptr;
    }

    const int browserID = browser->get_identifier != nullptr ? browser->get_identifier(browser) : 0;
    browser->base.release(&browser->base);
    if (browserID == 0) {
        return nullptr;
    }

    std::lock_guard<std::mutex> lock(sDevToolsScreenshotObserversMutex);
    if (auto it = sDevToolsScreenshotObservers.find(browserID); it != sDevToolsScreenshotObservers.end()) {
        it->second->observer.base.add_ref(&it->second->observer.base);
        return it->second;
    }

    DevToolsScreenshotObserver *observer = CreateDevToolsScreenshotObserver();
    observer->browserID = browserID;
    observer->registration = host->add_dev_tools_message_observer(host, &observer->observer);
    if (observer->registration == nullptr) {
        observer->observer.base.release(&observer->observer.base);
        return nullptr;
    }

    sDevToolsScreenshotObservers.emplace(browserID, observer);
    observer->observer.base.add_ref(&observer->observer.base);
    return observer;
}

static int OnDevToolsScreenshotMessage(cef_dev_tools_message_observer_t *, cef_browser_t *, const void *, size_t) {
    return 0;
}

static void OnDevToolsScreenshotResult(cef_dev_tools_message_observer_t *self,
                                       cef_browser_t *,
                                       int messageID,
                                       int success,
                                       const void *result,
                                       size_t resultSize) {
    DevToolsScreenshotObserver *observer = StructFromBase<DevToolsScreenshotObserver>(&self->base, offsetof(DevToolsScreenshotObserver, observer));
    if (!success) {
        NSString *errorText = result != nullptr && resultSize > 0
            ? [[NSString alloc] initWithBytes:result length:resultSize encoding:NSUTF8StringEncoding]
            : @"<no error payload>";
        NSLog(@"[CEFBridge] DevTools screenshot failed id=%d error=%@", messageID, errorText);
        CompletePendingDevToolsScreenshot(observer, messageID, nil);
        return;
    }
    CompletePendingDevToolsScreenshot(observer, messageID, PNGDataFromDevToolsResult(result, resultSize));
}

static void OnDevToolsScreenshotEvent(cef_dev_tools_message_observer_t *,
                                      cef_browser_t *,
                                      const cef_string_t *,
                                      const void *,
                                      size_t) {
}

static void OnDevToolsScreenshotAgentAttached(cef_dev_tools_message_observer_t *, cef_browser_t *) {
}

static void OnDevToolsScreenshotAgentDetached(cef_dev_tools_message_observer_t *self, cef_browser_t *) {
    DevToolsScreenshotObserver *observer = StructFromBase<DevToolsScreenshotObserver>(&self->base, offsetof(DevToolsScreenshotObserver, observer));
    CompleteAllPendingDevToolsScreenshots(observer, nil);
}

void CEFBridgeVisitAllCookies(cef_cookie_manager_t *manager, void (^completion)(NSArray<NSDictionary *> *cookies)) {
    if (manager == nullptr || manager->visit_all_cookies == nullptr) {
        if (completion != nil) {
            completion(@[]);
        }
        return;
    }

    void (^safeCompletion)(NSArray<NSDictionary *> *) = [completion copy];
    CookieVisitor *visitor = CreateCookieVisitor(safeCompletion ?: ^(NSArray<NSDictionary *> *_) {});
    visitor->visitor.base.add_ref(&visitor->visitor.base); // Keep the visitor alive for the timeout fallback.
    const int started = manager->visit_all_cookies(manager, &visitor->visitor);
    if (!started) {
        if (safeCompletion != nil) {
            safeCompletion(@[]);
        }
        visitor->visitor.base.release(&visitor->visitor.base);
        visitor->visitor.base.release(&visitor->visitor.base);
        return;
    }

    visitor->visitor.base.release(&visitor->visitor.base);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!visitor->finished.exchange(true) && safeCompletion != nil) {
            safeCompletion(@[]);
        }
        visitor->visitor.base.release(&visitor->visitor.base);
    });
}

void CEFBridgeSetCookie(cef_cookie_manager_t *manager,
                        NSString *name,
                        NSString *value,
                        NSString *url,
                        NSString *domain,
                        NSString *path,
                        BOOL httpOnly,
                        BOOL secure,
                        NSDate *expires,
                        void (^completion)(BOOL success)) {
    if (manager == nullptr || manager->set_cookie == nullptr) {
        if (completion != nil) { completion(NO); }
        return;
    }

    cef_cookie_t cookie = {};
    cookie.name = CEFBridgeStringCreate(name ?: @"");
    cookie.value = CEFBridgeStringCreate(value ?: @"");
    cookie.domain = CEFBridgeStringCreate(domain ?: @"");
    cookie.path = CEFBridgeStringCreate(path.length > 0 ? path : @"/");
    cookie.httponly = httpOnly ? 1 : 0;
    cookie.secure = secure ? 1 : 0;
    if (expires != nil) {
        cookie.has_expires = 1;
        cookie.expires = CEFBridgeBaseTimeFromDate(expires);
    }

    cef_string_t target = CEFBridgeStringCreate(url ?: @"about:blank");
    SetCookieCallback *callback = CreateSetCookieCallback(completion ?: ^(BOOL) {});
    const int started = manager->set_cookie(manager, &target, &cookie, &callback->callback);
    if (!started && completion != nil) { completion(NO); }

    CEFBridgeStringClear(&target);
    CEFBridgeStringClear(&cookie.name);
    CEFBridgeStringClear(&cookie.value);
    CEFBridgeStringClear(&cookie.domain);
    CEFBridgeStringClear(&cookie.path);
    callback->callback.base.release(&callback->callback.base);
}

void CEFBridgeDeleteAllCookies(cef_cookie_manager_t *manager, void (^completion)(NSInteger deleted)) {
    if (manager == nullptr || manager->delete_cookies == nullptr) {
        if (completion != nil) { completion(0); }
        return;
    }
    void (^safeCompletion)(NSInteger) = [completion copy];
    DeleteCookiesCallback *callback = CreateDeleteCookiesCallback(safeCompletion ?: ^(NSInteger) {});
    callback->callback.base.add_ref(&callback->callback.base); // Keep alive for timeout fallback.
    const int started = manager->delete_cookies(manager, nullptr, nullptr, &callback->callback);
    if (!started) {
        if (safeCompletion != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{ safeCompletion(0); });
        }
        callback->callback.base.release(&callback->callback.base);
        callback->callback.base.release(&callback->callback.base);
        return;
    }
    callback->callback.base.release(&callback->callback.base);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!callback->finished.exchange(true) && safeCompletion != nil) {
            safeCompletion(0);
        }
        callback->callback.base.release(&callback->callback.base);
    });
}

void CEFBridgeFlushCookieStore(cef_cookie_manager_t *manager, void (^completion)(void)) {
    if (manager == nullptr || manager->flush_store == nullptr) {
        if (completion != nil) { dispatch_async(dispatch_get_main_queue(), completion); }
        return;
    }
    FlushCallback *callback = CreateFlushCallback(completion ?: ^{});
    const int started = manager->flush_store(manager, &callback->callback);
    if (!started && completion != nil) {
        dispatch_async(dispatch_get_main_queue(), completion);
    }
    callback->callback.base.release(&callback->callback.base);
}

void CEFBridgeCaptureScreenshot(cef_browser_host_t *host,
                                CGSize logicalSize,
                                void (^completion)(NSData * _Nullable pngData)) {
    if (host == nullptr || logicalSize.width <= 0 || logicalSize.height <= 0) {
        if (completion != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil);
            });
        }
        return;
    }

    if (host->add_dev_tools_message_observer == nullptr || host->execute_dev_tools_method == nullptr) {
        if (completion != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil);
            });
        }
        return;
    }

    DevToolsScreenshotObserver *observer = CopyDevToolsScreenshotObserver(host);
    if (observer == nullptr) {
        if (completion != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil);
            });
        }
        return;
    }

    const int messageID = observer->nextMessageID.fetch_add(1, std::memory_order_relaxed);
    if (completion != nil) {
        observer->pendingCompletions[@(messageID)] = [completion copy];
    }

    NSString *payload = [NSString stringWithFormat:
        @"{\"id\":%d,\"method\":\"Page.captureScreenshot\",\"params\":{\"format\":\"png\",\"captureBeyondViewport\":true,\"clip\":{\"x\":0,\"y\":0,\"width\":%.0f,\"height\":%.0f,\"scale\":1}}}",
        messageID,
        logicalSize.width,
        logicalSize.height
    ];
    NSData *payloadData = [payload dataUsingEncoding:NSUTF8StringEncoding];
    const int submitted = payloadData != nil && host->send_dev_tools_message != nullptr
        ? host->send_dev_tools_message(host, payloadData.bytes, payloadData.length)
        : 0;
    if (submitted == 0) {
        NSLog(@"[CEFBridge] DevTools screenshot submit failed browserID=%d messageID=%d",
              observer->browserID,
              messageID);
        CompletePendingDevToolsScreenshot(observer, messageID, nil);
        observer->observer.base.release(&observer->observer.base);
        return;
    }

    observer->observer.base.add_ref(&observer->observer.base);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CompletePendingDevToolsScreenshot(observer, messageID, nil);
        observer->observer.base.release(&observer->observer.base);
    });

    observer->observer.base.release(&observer->observer.base);
}

void CEFBridgeInvalidateScreenshotCapture(cef_browser_t *browser) {
    if (browser == nullptr || browser->get_identifier == nullptr) {
        return;
    }

    const int browserID = browser->get_identifier(browser);
    if (browserID == 0) {
        return;
    }

    DevToolsScreenshotObserver *observer = nullptr;
    {
        std::lock_guard<std::mutex> lock(sDevToolsScreenshotObserversMutex);
        if (auto it = sDevToolsScreenshotObservers.find(browserID); it != sDevToolsScreenshotObservers.end()) {
            observer = it->second;
            sDevToolsScreenshotObservers.erase(it);
        }
    }

    if (observer == nullptr) {
        return;
    }
    CompleteAllPendingDevToolsScreenshots(observer, nil);
    if (observer->registration != nullptr) {
        observer->registration->base.release(&observer->registration->base);
        observer->registration = nullptr;
    }
    observer->observer.base.release(&observer->observer.base);
}
