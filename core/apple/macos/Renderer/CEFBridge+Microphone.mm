#import "CEFBridge_Internal.h"

int CEFBridgeRequestMicrophoneAccess(CEFBridge *owner, NSString *origin, uint32_t permissions,
                                    cef_media_access_callback_t *callback) {
    constexpr uint32_t microphone = CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE;
    if ((permissions & microphone) == 0) return 0;

    // Chromium has already checked the secure context and Permissions Policy.
    // This handler can approve only a microphone-only request from a visible tab.
    NSView *view = owner ? owner->_parentView : nil;
    NSWindow *window = view.window;
    CEFBridgeMicrophoneHandler handler = owner.onMicrophoneRequest;
    if (permissions != microphone || origin.length == 0 || !window.isKeyWindow ||
        view.isHiddenOrHasHiddenAncestor || owner->_cancelMicrophoneRequest || !handler) {
        callback->cancel(callback);
        return 1;
    }

    callback->base.add_ref(&callback->base);
    __block cef_media_access_callback_t *pending = callback;
    __weak CEFBridge *weakOwner = owner;
    void (^finish)(BOOL) = ^(BOOL allowed) {
        if (!pending) return;
        auto *decision = pending;
        pending = nullptr;
        CEFBridge *bridge = weakOwner;
        if (bridge) bridge->_cancelMicrophoneRequest = nil;
        if (allowed) {
            decision->cont(decision, microphone);
        } else {
            decision->cancel(decision);
        }
        decision->base.release(&decision->base);
    };

    owner->_cancelMicrophoneRequest = ^{ finish(NO); };
    handler(origin, ^BOOL {
        CEFBridge *bridge = weakOwner;
        NSView *currentView = bridge ? bridge->_parentView : nil;
        return pending && currentView.window.isVisible && !currentView.isHiddenOrHasHiddenAncestor;
    }, finish);
    return 1;
}
