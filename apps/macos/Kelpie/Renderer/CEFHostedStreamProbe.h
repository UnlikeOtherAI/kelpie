#pragma once
#import <Foundation/Foundation.h>

#if defined(DEBUG) && defined(KELPIE_HOSTED_STREAM_TEST)
@class CEFBridge;

NS_ASSUME_NONNULL_BEGIN
// Compile-gated hosted diagnostic; it never exposes raw renderer frames.
@interface CEFHostedStreamProbe : NSObject
- (instancetype)initWithBridge:(CEFBridge *)bridge
                         epoch:(uint64_t)epoch
                         width:(double)width
                        height:(double)height
                      identity:(BOOL (^)(void))identity NS_SWIFT_NAME(init(bridge:epoch:width:height:identity:));
// Optional, fixture-only private consumer. Context is captured on the main thread at receipt;
// the frame callback runs on main only after nonce validation, before retirement joins.
- (void)setFixtureNonce:(uint16_t)nonce
               context:(id _Nullable (^)(void))context
                 frame:(void (^)(NSData *, double, id))frame NS_SWIFT_NAME(setFixtureNonce(_:context:frame:));
- (void)startWithCompletion:(void (^)(BOOL))completion NS_SWIFT_NAME(start(completion:));
- (void)stopWithCompletion:(void (^)(BOOL))completion NS_SWIFT_NAME(stop(completion:));
// Call only after the asynchronous grant/document audit has completed.
- (nullable NSArray<NSDictionary *> *)sealAfterAudit:(BOOL)authorized NS_SWIFT_NAME(seal(afterAudit:));
@end
NS_ASSUME_NONNULL_END
#endif
