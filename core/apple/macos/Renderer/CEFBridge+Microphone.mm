#import "CEFBridge_Internal.h"
#import <AVFoundation/AVFoundation.h>

int CEFBridgeRequestMicrophoneAccess(CEFBridge *owner, NSString *origin, uint32_t permissions,
                                    cef_media_access_callback_t *callback) {
    constexpr uint32_t microphone = CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE;
    if ((permissions & microphone) == 0) return 0;

    // Chromium has already checked the secure context and Permissions Policy.
    // This handler can approve only a microphone-only request from a visible tab.
    NSView *view = owner ? owner->_parentView : nil;
    NSWindow *window = view.window;
    NSString *usage = [NSBundle.mainBundle objectForInfoDictionaryKey:@"NSMicrophoneUsageDescription"];
    if (permissions != microphone || origin.length == 0 || !window.isVisible ||
        view.isHiddenOrHasHiddenAncestor || window.attachedSheet ||
        owner->_cancelMicrophonePrompt || usage.length == 0) {
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
        if (bridge) bridge->_cancelMicrophonePrompt = nil;
        if (allowed) {
            decision->cont(decision, microphone);
        } else {
            decision->cancel(decision);
        }
        decision->base.release(&decision->base);
    };

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Allow microphone access?";
    alert.informativeText = [NSString stringWithFormat:@"%@ wants to use your microphone.", origin];
    [alert addButtonWithTitle:@"Deny"];
    [alert addButtonWithTitle:@"Allow"];
    owner->_cancelMicrophonePrompt = ^{
        finish(NO);
        [alert.window.sheetParent endSheet:alert.window returnCode:NSAlertFirstButtonReturn];
    };
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        if (!pending || response != NSAlertSecondButtonReturn) {
            finish(NO);
            return;
        }
        // The CEF callback consumes the site decision directly. Request TCC
        // authorization separately, after the user has allowed this origin.
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                CEFBridge *bridge = weakOwner;
                NSView *currentView = bridge ? bridge->_parentView : nil;
                finish(granted && currentView.window.isVisible && !currentView.isHiddenOrHasHiddenAncestor);
            });
        }];
    }];
    return 1;
}
