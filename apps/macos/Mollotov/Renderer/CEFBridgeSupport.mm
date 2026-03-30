#import "CEFBridgeSupport.h"

#import <crt_externs.h>

#include <atomic>
#include <stddef.h>
#include <string.h>

static inline NSString *StringFromCEFString(const cef_string_t *value) {
    if (value == nullptr || value->str == nullptr || value->length == 0) {
        return @"";
    }
    return [[NSString alloc] initWithCharacters:(const unichar *)value->str length:value->length];
}

static char **sAugmentedArgv = nullptr;
static int sAugmentedArgc = 0;

cef_main_args_t CEFBridgeMainArgs(void) {
    if (sAugmentedArgv == nullptr) {
        int origArgc = *_NSGetArgc();
        char **origArgv = *_NSGetArgv();
        // Inject --use-mock-keychain to prevent Keychain password prompts
        sAugmentedArgc = origArgc + 1;
        sAugmentedArgv = (char **)calloc(sAugmentedArgc + 1, sizeof(char *));
        for (int i = 0; i < origArgc; i++) {
            sAugmentedArgv[i] = origArgv[i];
        }
        sAugmentedArgv[origArgc] = (char *)"--use-mock-keychain";
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

struct BridgeClient {
    cef_client_t client;
    RefCountedState ref;
    __unsafe_unretained CEFBridge *owner;
    LifeSpanHandler lifeSpan;
    LoadHandler load;
    DisplayHandler display;
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
};

#define DEFINE_REFCOUNTED_FUNCS(Type, field, Prefix) \
    static void Prefix##AddRef(cef_base_ref_counted_t *base) { AddRefImpl<Type>(base, offsetof(Type, field)); } \
    static int Prefix##Release(cef_base_ref_counted_t *base) { return ReleaseImpl<Type>(base, offsetof(Type, field)); } \
    static int Prefix##HasOneRef(cef_base_ref_counted_t *base) { return HasOneRefImpl<Type>(base, offsetof(Type, field)); }

DEFINE_REFCOUNTED_FUNCS(BridgeClient, client, Client)
DEFINE_REFCOUNTED_FUNCS(LifeSpanHandler, handler, LifeSpan)
DEFINE_REFCOUNTED_FUNCS(LoadHandler, handler, Load)
DEFINE_REFCOUNTED_FUNCS(DisplayHandler, handler, Display)
DEFINE_REFCOUNTED_FUNCS(CookieVisitor, visitor, CookieVisitor)
DEFINE_REFCOUNTED_FUNCS(SetCookieCallback, callback, SetCookie)
DEFINE_REFCOUNTED_FUNCS(DeleteCookiesCallback, callback, DeleteCookies)

static cef_life_span_handler_t *GetLifeSpanHandler(cef_client_t *self) {
    return &StructFromBase<BridgeClient>(&self->base, offsetof(BridgeClient, client))->lifeSpan.handler;
}

static cef_load_handler_t *GetLoadHandler(cef_client_t *self) {
    return &StructFromBase<BridgeClient>(&self->base, offsetof(BridgeClient, client))->load.handler;
}

static cef_display_handler_t *GetDisplayHandler(cef_client_t *self) {
    return &StructFromBase<BridgeClient>(&self->base, offsetof(BridgeClient, client))->display.handler;
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
    client->client.get_life_span_handler = GetLifeSpanHandler;
    client->client.get_load_handler = GetLoadHandler;
    client->client.get_display_handler = GetDisplayHandler;

    client->lifeSpan.ref.count = 1;
    client->lifeSpan.owner = owner;
    client->lifeSpan.handler.base.size = sizeof(client->lifeSpan.handler);
    client->lifeSpan.handler.base.add_ref = LifeSpanAddRef;
    client->lifeSpan.handler.base.release = LifeSpanRelease;
    client->lifeSpan.handler.base.has_one_ref = LifeSpanHasOneRef;
    client->lifeSpan.handler.on_before_popup = OnBeforePopup;
    client->lifeSpan.handler.on_after_created = OnAfterCreated;
    client->lifeSpan.handler.do_close = DoClose;
    client->lifeSpan.handler.on_before_close = OnBeforeClose;

    client->load.ref.count = 1;
    client->load.owner = owner;
    client->load.handler.base.size = sizeof(client->load.handler);
    client->load.handler.base.add_ref = LoadAddRef;
    client->load.handler.base.release = LoadRelease;
    client->load.handler.base.has_one_ref = LoadHasOneRef;
    client->load.handler.on_loading_state_change = OnLoadingStateChange;
    client->load.handler.on_load_start = OnLoadStart;
    client->load.handler.on_load_end = OnLoadEnd;

    client->display.ref.count = 1;
    client->display.owner = owner;
    client->display.handler.base.size = sizeof(client->display.handler);
    client->display.handler.base.add_ref = DisplayAddRef;
    client->display.handler.base.release = DisplayRelease;
    client->display.handler.base.has_one_ref = DisplayHasOneRef;
    client->display.handler.on_address_change = OnAddressChange;
    client->display.handler.on_title_change = OnTitleChange;
    client->display.handler.on_loading_progress_change = OnLoadingProgressChange;
    client->display.handler.on_console_message = OnConsoleMessage;
    return client;
}

cef_client_t *CEFBridgeClientHandle(BridgeClient *client) {
    return client != nullptr ? &client->client : nullptr;
}

void CEFBridgeReleaseClient(BridgeClient *client) {
    if (client != nullptr) {
        client->client.base.release(&client->client.base);
    }
}

static cef_cookie_manager_t *GlobalCookieManager(void) {
    return cef_cookie_manager_get_global_manager(nullptr);
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
        dispatch_async(dispatch_get_main_queue(), ^{ visitor->completion(result); });
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
    if (callback->completion != nil) {
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
    callback->callback.on_complete = SetCookieComplete;
    return callback;
}

static DeleteCookiesCallback *CreateDeleteCookiesCallback(void (^completion)(NSInteger)) {
    DeleteCookiesCallback *callback = new DeleteCookiesCallback();
    memset(callback, 0, sizeof(DeleteCookiesCallback));
    callback->ref.count = 1;
    callback->completion = [completion copy];
    callback->callback.base.size = sizeof(callback->callback);
    callback->callback.base.add_ref = DeleteCookiesAddRef;
    callback->callback.base.release = DeleteCookiesRelease;
    callback->callback.base.has_one_ref = DeleteCookiesHasOneRef;
    callback->callback.on_complete = DeleteCookiesComplete;
    return callback;
}

void CEFBridgeVisitAllCookies(void (^completion)(NSArray<NSDictionary *> *cookies)) {
    cef_cookie_manager_t *manager = GlobalCookieManager();
    if (manager == nullptr || manager->visit_all_cookies == nullptr) {
        if (completion != nil) {
            completion(@[]);
        }
        return;
    }

    CookieVisitor *visitor = CreateCookieVisitor(completion ?: ^(NSArray<NSDictionary *> *_) {});
    const int started = manager->visit_all_cookies(manager, &visitor->visitor);
    if (!started) {
        if (completion != nil) {
            completion(@[]);
        }
        visitor->visitor.base.release(&visitor->visitor.base);
        manager->base.release(&manager->base);
        return;
    }

    manager->base.release(&manager->base);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!visitor->finished.exchange(true) && completion != nil) {
            completion([visitor->cookies copy]);
        }
        visitor->visitor.base.release(&visitor->visitor.base);
    });
}

void CEFBridgeSetCookie(NSString *name,
                        NSString *value,
                        NSString *domain,
                        NSString *path,
                        BOOL httpOnly,
                        BOOL secure,
                        NSDate *expires,
                        void (^completion)(BOOL success)) {
    cef_cookie_manager_t *manager = GlobalCookieManager();
    if (manager == nullptr || manager->set_cookie == nullptr) {
        if (completion != nil) {
            completion(NO);
        }
        return;
    }

    NSString *url = [NSString stringWithFormat:@"%@://%@%@", secure ? @"https" : @"http", domain ?: @"localhost", path.length > 0 ? path : @"/"];
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

    cef_string_t target = CEFBridgeStringCreate(url);
    SetCookieCallback *callback = CreateSetCookieCallback(completion ?: ^(BOOL) {});
    const int started = manager->set_cookie(manager, &target, &cookie, &callback->callback);
    if (!started && completion != nil) {
        completion(NO);
    }

    CEFBridgeStringClear(&target);
    CEFBridgeStringClear(&cookie.name);
    CEFBridgeStringClear(&cookie.value);
    CEFBridgeStringClear(&cookie.domain);
    CEFBridgeStringClear(&cookie.path);
    manager->base.release(&manager->base);
    callback->callback.base.release(&callback->callback.base);
}

void CEFBridgeDeleteAllCookies(void (^completion)(NSInteger deleted)) {
    cef_cookie_manager_t *manager = GlobalCookieManager();
    if (manager == nullptr || manager->delete_cookies == nullptr) {
        if (completion != nil) {
            completion(0);
        }
        return;
    }

    DeleteCookiesCallback *callback = CreateDeleteCookiesCallback(completion ?: ^(NSInteger) {});
    manager->delete_cookies(manager, nullptr, nullptr, &callback->callback);
    manager->base.release(&manager->base);
    callback->callback.base.release(&callback->callback.base);
}
