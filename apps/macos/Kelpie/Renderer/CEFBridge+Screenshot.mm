#import "CEFBridge_Internal.h"
#import "CEFBridge+Screenshot.h"

// Screenshot capture path for CEFBridge.
//
// Tries CEF's accelerated-surface capture first, then falls back to a
// WindowList CGImage crop, then to a cached NSView bitmap. The window-frame
// expansion helper exists because CEF's surface capture sometimes returns a
// short PNG when the view extends past the visible window content area.

static NSData *WindowCropPNGData(NSView *view, NSWindow *window, BOOL *fullyCaptured) {
    if (fullyCaptured != nullptr) {
        *fullyCaptured = NO;
    }
    if (view == nil || window == nil) {
        return nil;
    }

    NSView *frameView = window.contentView.superview;
    if (frameView == nil) {
        return nil;
    }

    // ScreenCaptureKit is not a drop-in replacement for synchronous crop capture
    // of CEF's accelerated surface, so keep the legacy call scoped and silenced
    // until the screenshot path is migrated end-to-end.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CGImageRef windowImage = CGWindowListCreateImage(
        CGRectNull,
        kCGWindowListOptionIncludingWindow,
        (CGWindowID)window.windowNumber,
        kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution
    );
#pragma clang diagnostic pop
    if (windowImage == nullptr) {
        return nil;
    }

    NSRect rectInFrameView = [view convertRect:view.bounds toView:frameView];
    NSRect backingRect = [frameView convertRectToBacking:rectInFrameView];
    CGFloat imageWidth = (CGFloat)CGImageGetWidth(windowImage);
    CGFloat imageHeight = (CGFloat)CGImageGetHeight(windowImage);
    CGRect desiredCropRect = CGRectMake(
        backingRect.origin.x,
        imageHeight - NSMaxY(backingRect),
        backingRect.size.width,
        backingRect.size.height
    );
    CGRect imageBounds = CGRectMake(0, 0, imageWidth, imageHeight);
    CGRect cropRect = CGRectIntersection(desiredCropRect, imageBounds);
    if (fullyCaptured != nullptr) {
        *fullyCaptured = CGRectEqualToRect(cropRect, desiredCropRect);
    }

    NSData *pngData = nil;
    if (!CGRectIsEmpty(cropRect)) {
        CGImageRef croppedImage = CGImageCreateWithImageInRect(windowImage, cropRect);
        if (croppedImage != nullptr) {
            NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:croppedImage];
            pngData = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            CGImageRelease(croppedImage);
        }
    }

    CGImageRelease(windowImage);
    return pngData;
}

static NSRect ExpandedWindowFrameIfNeeded(NSView *view, NSWindow *window) {
    if (view == nil || window == nil) {
        return NSZeroRect;
    }
    NSView *frameView = window.contentView.superview;
    if (frameView == nil) {
        return window.frame;
    }

    NSRect rectInFrameView = [view convertRect:view.bounds toView:frameView];
    NSRect currentFrame = window.frame;
    CGFloat requiredWidth = ceil(NSMaxX(rectInFrameView));
    CGFloat requiredHeight = ceil(NSMaxY(rectInFrameView));

    if (requiredWidth <= currentFrame.size.width + 0.5 &&
        requiredHeight <= currentFrame.size.height + 0.5) {
        return currentFrame;
    }

    NSRect expandedFrame = currentFrame;
    CGFloat widthDelta = fmax(requiredWidth - currentFrame.size.width, 0.0);
    CGFloat heightDelta = fmax(requiredHeight - currentFrame.size.height, 0.0);
    expandedFrame.size.width += widthDelta;
    expandedFrame.size.height += heightDelta;
    expandedFrame.origin.y -= heightDelta;
    return expandedFrame;
}

static NSData *CachedViewPNGData(NSView *view) {
    if (view == nil) {
        return nil;
    }

    NSRect bounds = view.bounds;
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:bounds];
    if (bitmap == nil) {
        return nil;
    }
    [view cacheDisplayInRect:bounds toBitmapImageRep:bitmap];
    return [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

static void CaptureWithExpandedWindowIfNeeded(NSView *view,
                                              NSWindow *window,
                                              void (^completion)(NSData * _Nullable pngData)) {
    if (view == nil || completion == nil) {
        if (completion != nil) {
            completion(nil);
        }
        return;
    }
    if (window == nil || (window.styleMask & NSWindowStyleMaskFullScreen) != 0) {
        completion(CachedViewPNGData(view));
        return;
    }

    NSRect originalFrame = window.frame;
    NSRect expandedFrame = ExpandedWindowFrameIfNeeded(view, window);
    if (NSEqualRects(originalFrame, expandedFrame)) {
        completion(WindowCropPNGData(view, window, nil) ?: CachedViewPNGData(view));
        return;
    }

    [window setFrame:expandedFrame display:YES];
    [window layoutIfNeeded];
    [window.contentView layoutSubtreeIfNeeded];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSData *resizedPNG = WindowCropPNGData(view, window, nil);
        [window setFrame:originalFrame display:YES];
        [window layoutIfNeeded];
        [window.contentView layoutSubtreeIfNeeded];
        completion(resizedPNG ?: CachedViewPNGData(view));
    });
}

@implementation CEFBridge (Screenshot)

- (void)takeScreenshotWithCompletion:(void (^)(NSData * _Nullable pngData))completion {
    NSView *view = _parentView;
    if (view == nil || completion == nil) {
        if (completion != nil) {
            completion(nil);
        }
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        NSWindow *window = view.window;
        cef_browser_host_t *host = CEFBridgeCopyBrowserHost([self activeBrowser]);
        if (host != nullptr) {
            const CGSize logicalSize = view.bounds.size;
            CEFBridgeCaptureScreenshot(host, logicalSize, ^(NSData * _Nullable pngData) {
                if (pngData != nil) {
                    completion(pngData);
                } else if (window != nil && (window.styleMask & NSWindowStyleMaskFullScreen) == 0) {
                    CaptureWithExpandedWindowIfNeeded(view, window, completion);
                } else if (window != nil) {
                    completion(WindowCropPNGData(view, window, nil) ?: CachedViewPNGData(view));
                } else {
                    completion(CachedViewPNGData(view));
                }
            });
            host->base.release(&host->base);
            return;
        }

        if (window != nil && (window.styleMask & NSWindowStyleMaskFullScreen) == 0) {
            CaptureWithExpandedWindowIfNeeded(view, window, completion);
            return;
        } else if (window != nil) {
            if (NSData *pngData = WindowCropPNGData(view, window, nil)) {
                completion(pngData);
                return;
            }
        }

        completion(CachedViewPNGData(view));
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
        [view layoutSubtreeIfNeeded];

        cef_browser_host_t *host = CEFBridgeCopyBrowserHost([self activeBrowser]);
        if (host != nullptr) {
            if (host->notify_move_or_resize_started != nullptr) {
                host->notify_move_or_resize_started(host);
            }
            if (host->notify_screen_info_changed != nullptr) {
                host->notify_screen_info_changed(host);
            }
            if (host->was_resized != nullptr) {
                host->was_resized(host);
            }
            if (host->set_focus != nullptr) {
                host->set_focus(host, 1);
            }
            host->base.release(&host->base);
        }
    });
}

@end
