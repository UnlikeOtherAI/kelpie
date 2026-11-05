#import "CEFBridge_Internal.h"
#import "CEFBridge+ScriptCapture.h"
#import <ImageIO/ImageIO.h>
#include <cmath>

// Script recording never crops OS windows, resizes the shell or reuses a cached native bitmap.
@implementation CEFBridge (ScriptCapture)

- (void)takeScriptScreenshotWithViewport:(NSRect)viewport
                         maximumPixels:(NSSize)maximum
                            pixelRatio:(CGFloat)pixelRatio
                            completion:(void (^)(NSData * _Nullable))completion {
    if (completion == nil) { return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        cef_browser_host_t *host = CEFBridgeCopyBrowserHost([self activeBrowser]);
        if (host == nullptr || viewport.size.width <= 0 || viewport.size.height <= 0 ||
            !isfinite(pixelRatio) || pixelRatio <= 0 ||
            maximum.width < 2 || maximum.width > 1920 || maximum.height < 2 || maximum.height > 1920) {
            if (host != nullptr) { host->base.release(&host->base); }
            completion(nil);
            return;
        }
        const double scale = fmin(1.0, fmin(maximum.width / (viewport.size.width * pixelRatio),
                                          maximum.height / (viewport.size.height * pixelRatio)));
        NSDictionary *params = @{
            @"format": @"png", @"fromSurface": @YES, @"captureBeyondViewport": @NO,
            @"clip": @{@"x": @(viewport.origin.x), @"y": @(viewport.origin.y),
                       @"width": @(viewport.size.width), @"height": @(viewport.size.height), @"scale": @(scale)}
        };
        CEFBridgeSendBrowserControlCommand(host, @"Page.captureScreenshot", params, ^(BOOL success, NSDictionary *result) {
            NSString *encoded = success && [result[@"data"] isKindOfClass:NSString.class] ? result[@"data"] : nil;
            if (encoded.length == 0 || encoded.length > 24 * 1024 * 1024) { completion(nil); return; }
            NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
            CGImageSourceRef source = data != nil ? CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL) : NULL;
            NSDictionary *properties = source != NULL ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL)) : nil;
            if (source != NULL) { CFRelease(source); }
            NSInteger width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] integerValue];
            NSInteger height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] integerValue];
            completion(width > 0 && height > 0 && width <= 1920 && height <= 1920 ? data : nil);
        });
        host->base.release(&host->base);
    });
}

@end
