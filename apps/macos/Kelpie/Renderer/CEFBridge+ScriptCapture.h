#import "CEFBridge.h"

NS_ASSUME_NONNULL_BEGIN

@interface CEFBridge (ScriptCapture)
/// Bounded current renderer surface; no clip/emulation or OS-window fallback.
- (void)takeScriptScreenshotWithMaximumPixels:(NSSize)maximum
                                  completion:(void (^ _Nonnull)(NSImage * _Nullable image))completion
    NS_SWIFT_NAME(takeScriptScreenshot(maximumPixels:completion:));
@end

NS_ASSUME_NONNULL_END
