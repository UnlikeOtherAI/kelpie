#pragma once
#import <Foundation/Foundation.h>

#if defined(KELPIE_HOSTED_STREAM_TEST)
@class CEFBridge;

NS_ASSUME_NONNULL_BEGIN
// Compile-gated hosted diagnostic; it never exposes raw renderer frames.
@interface CEFHostedStreamProbe : NSObject
- (instancetype)initWithBridge:(CEFBridge *)bridge
                         epoch:(uint64_t)epoch
                      identity:(BOOL (^)(void))identity NS_SWIFT_NAME(init(bridge:epoch:identity:));
- (void)startWithCompletion:(void (^)(BOOL))completion NS_SWIFT_NAME(start(completion:));
- (void)stopWithCompletion:(void (^)(BOOL))completion NS_SWIFT_NAME(stop(completion:));
// Call only after the asynchronous grant/document audit has completed.
- (nullable NSArray<NSDictionary *> *)sealAfterAudit:(BOOL)authorized NS_SWIFT_NAME(seal(afterAudit:));
@end
NS_ASSUME_NONNULL_END
#endif
