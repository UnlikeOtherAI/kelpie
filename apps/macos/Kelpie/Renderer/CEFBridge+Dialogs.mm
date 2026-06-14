#import "CEFBridgeSupport.h"

#include <atomic>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

static NSString *StringFromCEFDialogString(const cef_string_t *value) {
    if (value == nullptr || value->str == nullptr || value->length == 0) {
        return @"";
    }
    return [[NSString alloc] initWithCharacters:(const unichar *)value->str length:value->length];
}

static NSString *DialogTypeString(cef_jsdialog_type_t dialogType) {
    switch (dialogType) {
    case JSDIALOGTYPE_ALERT:
        return @"alert";
    case JSDIALOGTYPE_CONFIRM:
        return @"confirm";
    case JSDIALOGTYPE_PROMPT:
        return @"prompt";
    default:
        return @"alert";
    }
}

@interface CEFBridgeJSDialogContinuation : NSObject
- (instancetype)initWithCallback:(cef_jsdialog_callback_t *)callback;
- (void)resolveWithAccepted:(BOOL)accepted promptText:(NSString *)promptText;
@end

@implementation CEFBridgeJSDialogContinuation {
    cef_jsdialog_callback_t *_callback;
    BOOL _resolved;
}

- (instancetype)initWithCallback:(cef_jsdialog_callback_t *)callback {
    self = [super init];
    if (self == nil) {
        return nil;
    }
    _callback = callback;
    if (_callback != nullptr && _callback->base.add_ref != nullptr) {
        _callback->base.add_ref(&_callback->base);
    }
    return self;
}

- (void)dealloc {
    [self resolveWithAccepted:NO promptText:nil];
}

- (void)resolveWithAccepted:(BOOL)accepted promptText:(NSString *)promptText {
    cef_jsdialog_callback_t *callback = nullptr;
    @synchronized (self) {
        if (_resolved) {
            return;
        }
        _resolved = YES;
        callback = _callback;
        _callback = nullptr;
    }

    if (callback == nullptr) {
        return;
    }

    cef_string_t input = CEFBridgeStringCreate(promptText ?: @"");
    if (callback->cont != nullptr) {
        callback->cont(callback, accepted ? 1 : 0, &input);
    }
    CEFBridgeStringClear(&input);
    if (callback->base.release != nullptr) {
        callback->base.release(&callback->base);
    }
}

@end

struct JSDialogHandler {
    cef_jsdialog_handler_t handler;
    std::atomic<int> refCount;
    __unsafe_unretained CEFBridge *owner;
};

static JSDialogHandler *HandlerFromBase(cef_base_ref_counted_t *base) {
    return reinterpret_cast<JSDialogHandler *>(reinterpret_cast<uint8_t *>(base) - offsetof(JSDialogHandler, handler));
}

static JSDialogHandler *HandlerFromDialog(cef_jsdialog_handler_t *handler) {
    return reinterpret_cast<JSDialogHandler *>(reinterpret_cast<uint8_t *>(handler) - offsetof(JSDialogHandler, handler));
}

static void JSDialogAddRef(cef_base_ref_counted_t *base) {
    HandlerFromBase(base)->refCount.fetch_add(1, std::memory_order_relaxed);
}

static int JSDialogRelease(cef_base_ref_counted_t *base) {
    JSDialogHandler *handler = HandlerFromBase(base);
    if (handler->refCount.fetch_sub(1, std::memory_order_acq_rel) == 1) {
        delete handler;
        return 1;
    }
    return 0;
}

static int JSDialogHasOneRef(cef_base_ref_counted_t *base) {
    return HandlerFromBase(base)->refCount.load(std::memory_order_acquire) == 1 ? 1 : 0;
}

static int JSDialogHasAtLeastOneRef(cef_base_ref_counted_t *base) {
    return HandlerFromBase(base)->refCount.load(std::memory_order_acquire) >= 1 ? 1 : 0;
}

static void RunOnMain(void (^block)(void)) {
    if (block == nil) {
        return;
    }
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

static void SendDialogToSwift(CEFBridge *owner,
                              NSString *type,
                              NSString *message,
                              NSString *defaultPromptText,
                              cef_jsdialog_callback_t *callback) {
    CEFBridgeJSDialogContinuation *continuation =
        [[CEFBridgeJSDialogContinuation alloc] initWithCallback:callback];
    CEFBridgeJavaScriptDialogHandler handler = [owner.onJavaScriptDialog copy];
    if (handler == nil) {
        [continuation resolveWithAccepted:NO promptText:nil];
        return;
    }

    CEFBridgeJavaScriptDialogResolution resolve = ^(BOOL accepted, NSString *promptText) {
        [continuation resolveWithAccepted:accepted promptText:promptText];
    };

    RunOnMain(^{
        handler(type ?: @"alert", message ?: @"", defaultPromptText, resolve);
    });
}

static int OnJSDialog(cef_jsdialog_handler_t *self,
                      cef_browser_t *,
                      const cef_string_t *,
                      cef_jsdialog_type_t dialogType,
                      const cef_string_t *messageText,
                      const cef_string_t *defaultPromptText,
                      cef_jsdialog_callback_t *callback,
                      int *suppressMessage) {
    if (suppressMessage != nullptr) {
        *suppressMessage = 0;
    }

    CEFBridge *owner = HandlerFromDialog(self)->owner;
    if (owner == nil) {
        CEFBridgeJSDialogContinuation *continuation =
            [[CEFBridgeJSDialogContinuation alloc] initWithCallback:callback];
        [continuation resolveWithAccepted:NO promptText:nil];
        return 1;
    }

    SendDialogToSwift(
        owner,
        DialogTypeString(dialogType),
        StringFromCEFDialogString(messageText),
        dialogType == JSDIALOGTYPE_PROMPT ? StringFromCEFDialogString(defaultPromptText) : nil,
        callback
    );
    return 1;
}

static int OnBeforeUnloadDialog(cef_jsdialog_handler_t *self,
                                cef_browser_t *,
                                const cef_string_t *messageText,
                                int,
                                cef_jsdialog_callback_t *callback) {
    CEFBridge *owner = HandlerFromDialog(self)->owner;
    if (owner == nil) {
        CEFBridgeJSDialogContinuation *continuation =
            [[CEFBridgeJSDialogContinuation alloc] initWithCallback:callback];
        [continuation resolveWithAccepted:NO promptText:nil];
        return 1;
    }

    SendDialogToSwift(
        owner,
        @"confirm",
        StringFromCEFDialogString(messageText),
        nil,
        callback
    );
    return 1;
}

static void OnResetDialogState(cef_jsdialog_handler_t *self, cef_browser_t *) {
    CEFBridge *owner = HandlerFromDialog(self)->owner;
    void (^reset)(void) = [owner.onJavaScriptDialogReset copy];
    if (reset != nil) {
        RunOnMain(reset);
    }
}

static void OnDialogClosed(cef_jsdialog_handler_t *, cef_browser_t *) {
}

cef_jsdialog_handler_t *CEFBridgeCreateJSDialogHandler(CEFBridge *owner) {
    JSDialogHandler *handler = new JSDialogHandler();
    memset(handler, 0, sizeof(JSDialogHandler));
    handler->refCount = 1;
    handler->owner = owner;
    handler->handler.base.size = sizeof(handler->handler);
    handler->handler.base.add_ref = JSDialogAddRef;
    handler->handler.base.release = JSDialogRelease;
    handler->handler.base.has_one_ref = JSDialogHasOneRef;
    handler->handler.base.has_at_least_one_ref = JSDialogHasAtLeastOneRef;
    handler->handler.on_jsdialog = OnJSDialog;
    handler->handler.on_before_unload_dialog = OnBeforeUnloadDialog;
    handler->handler.on_reset_dialog_state = OnResetDialogState;
    handler->handler.on_dialog_closed = OnDialogClosed;
    return &handler->handler;
}

void CEFBridgeNullifyJSDialogHandler(cef_jsdialog_handler_t *handler) {
    if (handler == nullptr) {
        return;
    }
    HandlerFromDialog(handler)->owner = nil;
}
