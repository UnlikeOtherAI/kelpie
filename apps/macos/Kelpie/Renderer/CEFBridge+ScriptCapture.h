#import "CEFBridge.h"

NS_ASSUME_NONNULL_BEGIN

@interface CEFBridge (ScriptCapture)
/// Renderer-only bounded capture for script compositing; no OS-window or cached-view fallback.
- (void)takeScriptScreenshotWithViewport:(NSRect)viewport
                         maximumPixels:(NSSize)maximum
                            pixelRatio:(CGFloat)pixelRatio
                            completion:(void (^ _Nonnull)(NSData * _Nullable pngData))completion
    NS_SWIFT_NAME(takeScriptScreenshot(viewport:maximumPixels:pixelRatio:completion:));

@end

NS_ASSUME_NONNULL_END
