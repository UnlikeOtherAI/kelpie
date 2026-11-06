#import <AppKit/AppKit.h>
#import <ImageIO/ImageIO.h>
#import "CEFHostedStreamMock.h"
#import "../../apps/macos/Kelpie/Renderer/CEFHostedStreamProbe.h"
#include <cassert>
#include <atomic>
#include <string>

static cef_browser_t browser{};
static cef_browser_t foreignBrowser{};
static cef_browser_host_t host{};
static cef_registration_t registration{};
static cef_dev_tools_message_observer_t *observer = nullptr;
static int acknowledgements = 0;
static int stops = 0;
static int eventWidth = 100;
static BOOL holdAck = NO;
static void (^heldAck)(BOOL, NSDictionary *) = nil;
static std::atomic<bool> holdIngress{false};
static std::atomic<bool> ingressReserved{false};
static dispatch_semaphore_t resumeIngress;
void CEFHostedStreamMockAfterReserve(void) {
    if (holdIngress.load()) {
        ingressReserved.store(true);
        dispatch_semaphore_wait(resumeIngress, DISPATCH_TIME_FOREVER);
    }
}
static void addRef(cef_base_ref_counted_t *) {}
static int releaseRef(cef_base_ref_counted_t *) { return 0; }
static cef_registration_t *registerObserver(cef_browser_host_t *, cef_dev_tools_message_observer_t *value) {
    observer = value;
    observer->base.add_ref(&observer->base);
    registration.base.release = [](cef_base_ref_counted_t *) {
        observer->base.release(&observer->base);
        return 0;
    };
    return &registration;
}
@implementation CEFBridge
- (cef_browser_t *)activeBrowser { return &browser; }
@end
int CEFBridgeBrowserIdentifier(cef_browser_t *value) { return value == &browser ? 7 : 0; }
cef_browser_host_t *CEFBridgeCopyBrowserHost(cef_browser_t *) { return &host; }
void CEFBridgeSendBrowserControlCommand(cef_browser_host_t *, NSString *method, NSDictionary *, void (^completion)(BOOL, NSDictionary *)) {
    if ([method isEqualToString:@"Page.screencastFrameAck"]) {
        ++acknowledgements;
        if (holdAck) { heldAck = [completion copy]; return; }
    }
    if ([method isEqualToString:@"Page.stopScreencast"]) { ++stops; }
    dispatch_async(dispatch_get_main_queue(), ^{ completion(YES, nil); });
}
static NSData *redPNG() {
    NSMutableData *data = [NSMutableData data];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(nullptr, 100, 100, 8, 400, space,
                                                kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1); CGContextFillRect(context, CGRectMake(0, 0, 100, 100));
    for (unsigned bit = 0; bit < 16; ++bit) {
        if ((0xA59Cu & (1u << bit)) == 0) { continue; }
        CGContextSetRGBFillColor(context, 0.8, 0.8, 0.8, 1);
        CGContextFillRect(context, CGRectMake((bit % 4) * 12, 100 - (bit / 4 + 1) * 12, 12, 12));
    }
    CGContextSetRGBFillColor(context, 1, 0.1, 0.1, 1); CGContextFillRect(context, CGRectMake(60, 30, 20, 20));
    CGContextSetRGBFillColor(context, 0.97, 0.87, 0.27, 1); CGContextFillRect(context, CGRectMake(60, 60, 20, 20));
    CGImageRef image = CGBitmapContextCreateImage(context); CGContextRelease(context);
    CGImageDestinationRef dest = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, CFSTR("public.png"), 1, nullptr);
    CGImageDestinationAddImage(dest, image, nullptr); CGImageDestinationFinalize(dest);
    CFRelease(dest); CGImageRelease(image); return data;
}
static void emitFrame(cef_browser_t *target = &browser, cef_dev_tools_message_observer_t *destination = observer) {
    NSString *encoded = [redPNG() base64EncodedStringWithOptions:0];
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"sessionId": @8, @"metadata": @{@"timestamp": @1.25, @"deviceWidth": @(eventWidth), @"deviceHeight": @100,
        @"pageScaleFactor": @1, @"scrollOffsetX": @0, @"scrollOffsetY": @0, @"offsetTop": @0}, @"data": encoded} options:0 error:nil];
    NSString *event = @"Page.screencastFrame";
    std::u16string methodText(event.length, 0);
    [event getCharacters:reinterpret_cast<unichar *>(methodText.data()) range:NSMakeRange(0,event.length)];
    cef_string_t method{methodText.data(), methodText.size()};
    destination->on_dev_tools_event(destination, target, &method, json.bytes, json.length);
}
static void emitNullFrame() {
    NSString *event = @"Page.screencastFrame";
    std::u16string methodText(event.length, 0);
    [event getCharacters:reinterpret_cast<unichar *>(methodText.data()) range:NSMakeRange(0,event.length)];
    cef_string_t method{methodText.data(), methodText.size()};
    observer->on_dev_tools_event(observer, &browser, &method, nullptr, 0);
}
int main() {
    @autoreleasepool {
        setenv("GITHUB_ACTIONS","true",1); setenv("RUNNER_OS","macOS",1);
        setenv("KELPIE_HOSTED_RUNTIME","1",1); setenv("KELPIE_CEF_STREAM_TEST","1",1);
        host.base.add_ref = addRef; host.base.release = releaseRef;
        host.add_dev_tools_message_observer = registerObserver;
        CEFBridge *bridge = [CEFBridge new];
        CEFHostedStreamProbe *probe = [[CEFHostedStreamProbe alloc] initWithBridge:bridge epoch:123 width:100 height:100 identity:^BOOL { return YES; }];
        [probe startWithCompletion:^(BOOL started) {
            assert(started);
            auto *lateObserver = observer;
            lateObserver->base.add_ref(&lateObserver->base);
            emitFrame(&foreignBrowser);
            emitFrame();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100 * NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
                [probe stopWithCompletion:^(BOOL stopped) {
                    assert(stopped && acknowledgements == 1 && stops == 1);
                    emitFrame(&browser, lateObserver);
                    assert(acknowledgements == 1);
                    lateObserver->base.release(&lateObserver->base);
                    NSArray *samples = [probe sealAfterAudit:YES];
                    assert(samples.count == 1 && [samples[0][@"x"] intValue] >= 28);
                    assert([probe sealAfterAudit:YES] == nil);
                    __block BOOL identity = YES;
                    CEFHostedStreamProbe *second = [[CEFHostedStreamProbe alloc] initWithBridge:bridge epoch:124 width:100 height:100 identity:^BOOL { return identity; }];
                    holdAck = YES;
                    [second startWithCompletion:^(BOOL secondStarted) {
                        assert(secondStarted);
                        emitFrame();
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100 * NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
                            assert(heldAck != nil);
                            __block BOOL callbackReturned = NO;
                            [second stopWithCompletion:^(BOOL secondStopped) {
                                callbackReturned = YES;
                                assert(secondStopped && [second sealAfterAudit:YES] == nil);
                                assert(acknowledgements == 2 && stops == 2);
                                holdAck = NO;
                                CEFHostedStreamProbe *third = [[CEFHostedStreamProbe alloc] initWithBridge:bridge epoch:125 width:100 height:100 identity:^BOOL { return YES; }];
                                [third startWithCompletion:^(BOOL thirdStarted) {
                                    assert(thirdStarted);
                                    observer->on_dev_tools_agent_detached(observer, &browser);
                                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50 * NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
                                        [third stopWithCompletion:^(BOOL) {
                                            assert([third sealAfterAudit:YES] == nil && stops == 3);
                                            CEFHostedStreamProbe *fourth = [[CEFHostedStreamProbe alloc] initWithBridge:bridge epoch:126 width:100 height:100 identity:^BOOL { return YES; }];
                                            [fourth startWithCompletion:^(BOOL fourthStarted) {
                                                assert(fourthStarted);
                                                eventWidth = 101;
                                                emitFrame();
                                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50 * NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
                                                    [fourth stopWithCompletion:^(BOOL) {
                                                        assert([fourth sealAfterAudit:YES] == nil && stops == 4 && acknowledgements == 3);
                                                        eventWidth = 100;
                                                        CEFHostedStreamProbe *fifth = [[CEFHostedStreamProbe alloc] initWithBridge:bridge epoch:127 width:100 height:100 identity:^BOOL { return YES; }];
                                                        [fifth startWithCompletion:^(BOOL fifthStarted) {
                                                            assert(fifthStarted);
                                                            emitFrame(); emitFrame(); emitFrame(); emitFrame();
                                                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100 * NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
                                                                [fifth stopWithCompletion:^(BOOL) {
                                                                    assert([fifth sealAfterAudit:YES] == nil && stops == 5);
                                                                    CEFHostedStreamProbe *sixth = [[CEFHostedStreamProbe alloc] initWithBridge:bridge epoch:128 width:100 height:100 identity:^BOOL { return YES; }];
                                                                    [sixth startWithCompletion:^(BOOL sixthStarted) {
                                                                        assert(sixthStarted);
                                                                        resumeIngress = dispatch_semaphore_create(0);
                                                                        holdIngress.store(true);
                                                                        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ emitFrame(); });
                                                                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100 * NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
                                                                            assert(ingressReserved.load());
                                                                            __block BOOL retired = NO;
                                                                            [sixth stopWithCompletion:^(BOOL stoppedSixth) {
                                                                                retired = YES;
                                                                                assert(stoppedSixth && stops == 6);
                                                                                NSArray *sealed = [sixth sealAfterAudit:YES];
                                                                                assert(sealed != nil && sealed.count == 0);
                                                                                CEFHostedStreamProbe *seventh = [[CEFHostedStreamProbe alloc] initWithBridge:bridge epoch:129 width:100 height:100 identity:^BOOL { return YES; }];
                                                                                [seventh startWithCompletion:^(BOOL seventhStarted) {
                                                                                    assert(seventhStarted);
                                                                                    emitNullFrame();
                                                                                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50 * NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
                                                                                        [seventh stopWithCompletion:^(BOOL) {
                                                                                            assert([seventh sealAfterAudit:YES] == nil && stops == 7);
                                                                                            __block int frames = 0;
                                                                                            CEFHostedStreamProbe *eighth = [[CEFHostedStreamProbe alloc] initWithBridge:bridge epoch:130 width:100 height:100 identity:^BOOL { return YES; }];
                                                                                            [eighth setFixtureNonce:0xA59C context:^id { return @42; } frame:^(NSData *image, double receipt, id context) {
                                                                                                assert(image.length > 0 && receipt > 0 && [context isEqual:@42]); ++frames;
                                                                                            }];
                                                                                            [eighth startWithCompletion:^(BOOL started) {
                                                                                                assert(started); emitFrame();
                                                                                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100 * NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
                                                                                                    [eighth stopWithCompletion:^(BOOL stopped) {
                                                                                                        assert(stopped && frames == 1 && [eighth sealAfterAudit:YES] != nil);
                                                                                                        CEFHostedStreamProbe *ninth = [[CEFHostedStreamProbe alloc] initWithBridge:bridge epoch:131 width:100 height:100 identity:^BOOL { return YES; }];
                                                                                                        [ninth setFixtureNonce:0xA59D context:^id { return @42; } frame:^(NSData *, double, id) { ++frames; }];
                                                                                                        [ninth startWithCompletion:^(BOOL started) {
                                                                                                            assert(started); emitFrame();
                                                                                                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100 * NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
                                                                                                                [ninth stopWithCompletion:^(BOOL stopped) {
                                                                                                                    assert(stopped && frames == 1 && [ninth sealAfterAudit:YES] == nil);
                                                                                                                    puts("PASS: ACK, nonce-bound frame hook, mismatch refusal, bounded ingress/decode, late events and retirement"); exit(0);
                                                                                                                }];
                                                                                                            });
                                                                                                        }];
                                                                                                    }];
                                                                                                });
                                                                                            }];
                                                                                        }];
                                                                                    });
                                                                                }];
                                                                            }];
                                                                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50 * NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
                                                                                assert(!retired);
                                                                                holdIngress.store(false);
                                                                                dispatch_semaphore_signal(resumeIngress);
                                                                            });
                                                                        });
                                                                    }];
                                                                }];
                                                            });
                                                        }];
                                                    }];
                                                });
                                            }];
                                        }];
                                    });
                                }];
                            }];
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50 * NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
                                assert(!callbackReturned);
                                identity = NO;
                                heldAck(YES,nil);
                                heldAck = nil;
                            });
                        });
                    }];
                }];
            });
        }];
        [[NSRunLoop mainRunLoop] run];
    }
}
