#pragma once
#import <Foundation/Foundation.h>

#if defined(KELPIE_HOSTED_STREAM_TEST)
@class CEFBridge;

NS_ASSUME_NONNULL_BEGIN
// Compile-gated hosted diagnostic; it never exposes raw renderer frames.
@interface CEFHostedStreamProbe : NSObject
- (instancetype)initWithBridge:(CEFBridge *)bridge
                         epoch:(uint64_t)epoch
                      identity:(BOOL (^)(void))identity;
- (void)startWithCompletion:(void (^)(BOOL))completion;
- (void)stopWithCompletion:(void (^)(BOOL))completion;
// Call only after the asynchronous grant/document audit has completed.
- (nullable NSArray<NSDictionary *> *)sealAfterAudit:(BOOL)authorized;
@end
NS_ASSUME_NONNULL_END
#endif
