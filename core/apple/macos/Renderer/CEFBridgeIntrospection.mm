#import "CEFBridge_Internal.h"

// Diagnostic and introspection helpers for CEF browser handles.
// Pulled out of CEFBridge.mm so the core lifecycle file stays under the
// 500-line limit. These helpers are stateless C functions; they take raw
// CEF handles and emit either an NSString summary or stderr log line.

cef_browser_host_t *CEFBridgeCopyBrowserHost(cef_browser_t *browser) {
    if (browser == nullptr || browser->get_host == nullptr) {
        return nullptr;
    }
    return browser->get_host(browser);
}

cef_frame_t *CEFBridgeCopyMainFrame(cef_browser_t *browser) {
    if (browser == nullptr || browser->get_main_frame == nullptr) {
        return nullptr;
    }
    return browser->get_main_frame(browser);
}

int CEFBridgeBrowserIdentifier(cef_browser_t *browser) {
    if (browser == nullptr || browser->get_identifier == nullptr) {
        return 0;
    }
    return browser->get_identifier(browser);
}

NSInteger CEFBridgeBrowserLivenessScore(cef_browser_t *browser) {
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

    cef_browser_host_t *host = CEFBridgeCopyBrowserHost(browser);
    if (host != nullptr) {
        score += 1;
        if (host->has_view != nullptr && host->has_view(host)) {
            score += 1;
        }
        host->base.release(&host->base);
    }

    cef_frame_t *frame = CEFBridgeCopyMainFrame(browser);
    if (frame != nullptr) {
        score += 4;
        if (frame->is_valid != nullptr && frame->is_valid(frame)) {
            score += 2;
        }
        frame->base.release(&frame->base);
    }

    return score;
}

NSString *CEFBridgeDescribeBrowser(cef_browser_t *browser) {
    if (browser == nullptr) {
        return @"nil";
    }

    const int browserID = CEFBridgeBrowserIdentifier(browser);
    const BOOL isValid = browser->is_valid != nullptr ? browser->is_valid(browser) != 0 : NO;
    const BOOL hasDocument = browser->has_document != nullptr ? browser->has_document(browser) != 0 : NO;

    cef_browser_host_t *host = CEFBridgeCopyBrowserHost(browser);
    const BOOL hasHost = host != nullptr;
    const BOOL hasView = hasHost && host->has_view != nullptr ? host->has_view(host) != 0 : NO;
    const BOOL isWindowless = hasHost && host->is_window_rendering_disabled != nullptr
        ? host->is_window_rendering_disabled(host) != 0
        : NO;

    cef_frame_t *frame = CEFBridgeCopyMainFrame(browser);
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
            (long)CEFBridgeBrowserLivenessScore(browser)];
}

void CEFBridgeLogBrowserHandles(const char *event,
                                cef_browser_t *callbackBrowser,
                                cef_browser_t *createdBrowser,
                                cef_browser_t *activeBrowser) {
    const int callbackID = CEFBridgeBrowserIdentifier(callbackBrowser);
    const int createdID = CEFBridgeBrowserIdentifier(createdBrowser);
    const int activeID = CEFBridgeBrowserIdentifier(activeBrowser);
    const long callbackScore = (long)CEFBridgeBrowserLivenessScore(callbackBrowser);
    const long createdScore = (long)CEFBridgeBrowserLivenessScore(createdBrowser);
    const long activeScore = (long)CEFBridgeBrowserLivenessScore(activeBrowser);
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

void CEFBridgeNotifyStateChange(CEFBridge *owner) {
    if (owner.onStateChange == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (owner.onStateChange != nil) {
            owner.onStateChange();
        }
    });
}
