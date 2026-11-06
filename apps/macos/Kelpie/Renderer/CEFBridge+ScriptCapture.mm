#import "CEFBridge_Internal.h"
#import "CEFBridge+ScriptCapture.h"
#import "ScriptCaptureSourceLimits.h"
#import <ImageIO/ImageIO.h>

// No clip: CDP must capture the current compositor surface without viewport emulation.
@implementation CEFBridge (ScriptCapture)

- (void)takeScriptScreenshotWithMaximumPixels:(NSSize)maximum
                                  completion:(void (^)(NSImage * _Nullable))completion {
    if (completion == nil) { return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSView *view = self->_parentView;
        if (view == nil) { completion(nil); return; }
        const NSSize sourcePixels = [view convertSizeToBacking:view.bounds.size];
        if (view.window == nil || view.isHiddenOrHasHiddenAncestor ||
            !kelpie_mac_capture::AdmitsSource(sourcePixels.width, sourcePixels.height) ||
            !isfinite(maximum.width) || !isfinite(maximum.height) ||
            maximum.width < 2 || maximum.width > 1920 || maximum.height < 2 || maximum.height > 1920) {
            completion(nil);
            return;
        }
        cef_browser_host_t *host = CEFBridgeCopyBrowserHost([self activeBrowser]);
        if (host == nullptr) { completion(nil); return; }
        NSDictionary *params = @{@"format": @"png", @"fromSurface": @YES, @"captureBeyondViewport": @NO};
#if DEBUG && defined(KELPIE_HOSTED_PNG_EQUIVALENCE_TEST)
        // Compiled only for the isolated hosted equivalence experiment.
        if ([NSProcessInfo.processInfo.environment[@"KELPIE_CEF_PNG_SPEED_TEST"] isEqualToString:@"1"]) {
            params = @{@"format": @"png", @"fromSurface": @YES, @"captureBeyondViewport": @NO,
                       @"optimizeForSpeed": @YES};
        }
#endif
        CEFBridgeSendBrowserControlCommand(host, @"Page.captureScreenshot", params, ^(BOOL success, NSDictionary *result) {
            NSString *encoded = success && [result[@"data"] isKindOfClass:NSString.class] ? result[@"data"] : nil;
            if (encoded.length == 0 || encoded.length > kelpie_mac_capture::kMaximumBase64Characters) { completion(nil); return; }
            NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
            if (data == nil || data.length > kelpie_mac_capture::kMaximumPngBytes) { completion(nil); return; }
            NSDictionary *options = @{(__bridge NSString *)kCGImageSourceShouldCache: @NO};
            CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, (__bridge CFDictionaryRef)options);
            NSDictionary *properties = source != NULL ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL)) : nil;
            const double width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue];
            const double height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue];
            const NSSize current = [view convertSizeToBacking:view.bounds.size];
            if (source == NULL || self->_parentView != view || view.window == nil || !NSEqualSizes(current, sourcePixels) ||
                !kelpie_mac_capture::AdmitsSource(width, height)) {
                if (source != NULL) { CFRelease(source); }
                completion(nil);
                return;
            }
            const double scale = fmin(1.0, fmin(maximum.width / width, maximum.height / height));
            const NSInteger longest = MAX(2, (NSInteger)floor(MAX(width, height) * scale));
            NSDictionary *thumbnailOptions = @{
                (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(longest),
                (__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES
            };
            CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)thumbnailOptions);
            CFRelease(source);
            if (thumbnail == NULL) { completion(nil); return; }
            const size_t outputWidth = CGImageGetWidth(thumbnail), outputHeight = CGImageGetHeight(thumbnail);
            NSImage *image = outputWidth <= maximum.width && outputHeight <= maximum.height
                ? [[NSImage alloc] initWithCGImage:thumbnail size:NSMakeSize(outputWidth, outputHeight)] : nil;
            CGImageRelease(thumbnail);
            completion(image);
        });
        host->base.release(&host->base);
    });
}

@end
