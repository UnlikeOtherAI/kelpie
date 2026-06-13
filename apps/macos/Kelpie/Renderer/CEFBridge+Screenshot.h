#import "CEFBridge.h"

NS_ASSUME_NONNULL_BEGIN

/// Screenshot capture and view resize operations implemented in
/// CEFBridge+Screenshot.mm. Factored into a category so the primary
/// `CEFBridge.mm` translation unit stays within the project's 500-line
/// file limit.
@interface CEFBridge (Screenshot)

/// Take a screenshot. Returns PNG data via callback.
- (void)takeScreenshotWithCompletion:(void (^ _Nonnull)(NSData * _Nullable pngData))completion;

/// Resize the browser view.
- (void)resizeTo:(NSSize)size;

@end

NS_ASSUME_NONNULL_END
