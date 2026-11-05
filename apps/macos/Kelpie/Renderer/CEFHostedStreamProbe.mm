#import "CEFHostedStreamProbe.h"

#if defined(DEBUG) && defined(KELPIE_HOSTED_STREAM_TEST)
#if defined(KELPIE_HOSTED_STREAM_MOCK)
#import "CEFHostedStreamMock.h"
#else
#import "CEFBridge_Internal.h"
#endif
#import "CEFHostedStreamPixels.h"
#import "CEFHostedStreamFence.h"
#import <CoreFoundation/CoreFoundation.h>
#include <atomic>
#include <memory>
#include <mutex>
#include <cmath>
#include <climits>

@class CEFHostedStreamProbe;
struct HostedStreamObserver {
    cef_dev_tools_message_observer_t api{};
    std::atomic<int> references{1};
    std::mutex ingressLock;
    dispatch_group_t ingressGroup = dispatch_group_create();
    unsigned ingress = 0;
    bool ingressOpen = true;
    bool overflowSignaled = false;
    int browserID = 0;
    __weak CEFHostedStreamProbe *owner = nil;
};

@interface CEFHostedStreamProbe () {
    __weak CEFBridge *_bridge;
    BOOL (^_identity)(void);
    uint64_t _epoch;
    double _expectedWidth;
    double _expectedHeight;
    int _browserID;
    cef_browser_host_t *_host;
    cef_registration_t *_registration;
    HostedStreamObserver *_observer;
    std::unique_ptr<CEFHostedStreamFence> _fence;
    dispatch_group_t _pending;
    NSMutableArray<void (^)(BOOL)> *_waiters;
    CEFHostedStreamProbe *_keepAlive;
    BOOL _started;
    BOOL _stopping;
    BOOL _stopped;
    BOOL _stopSucceeded;
}
- (void)consumeBrowser:(int)browser payload:(NSData *)payload;
- (void)agentDetached;
- (void)ingressOverflow;
- (void)finishStop:(BOOL)success;
- (void)releaseHandles;
@end

static HostedStreamObserver *StreamObserver(cef_base_ref_counted_t *base) {
    return reinterpret_cast<HostedStreamObserver *>(base);
}
static void StreamAddRef(cef_base_ref_counted_t *base) { StreamObserver(base)->references.fetch_add(1); }
static int StreamRelease(cef_base_ref_counted_t *base) {
    HostedStreamObserver *observer = StreamObserver(base);
    if (observer->references.fetch_sub(1) == 1) { delete observer; return 1; }
    return 0;
}
static int StreamHasOne(cef_base_ref_counted_t *base) { return StreamObserver(base)->references.load() == 1; }
static int StreamHasAny(cef_base_ref_counted_t *base) { return StreamObserver(base)->references.load() > 0; }
static int StreamRaw(cef_dev_tools_message_observer_t *, cef_browser_t *, const void *, size_t) { return 0; }
static void StreamResult(cef_dev_tools_message_observer_t *, cef_browser_t *, int, int, const void *, size_t) {}
static void StreamAttached(cef_dev_tools_message_observer_t *, cef_browser_t *) {}
static void StreamDetached(cef_dev_tools_message_observer_t *base, cef_browser_t *) {
    CEFHostedStreamProbe *owner = reinterpret_cast<HostedStreamObserver *>(base)->owner;
    dispatch_async(dispatch_get_main_queue(), ^{ [owner agentDetached]; });
}
static void StreamOverflow(HostedStreamObserver *observer, CEFHostedStreamProbe *owner) {
    bool signal = false;
    {
        std::lock_guard<std::mutex> guard(observer->ingressLock);
        if (observer->ingressOpen && !observer->overflowSignaled) {
            observer->ingressOpen = false;
            observer->overflowSignaled = true;
            signal = true;
        }
    }
    if (signal) { dispatch_async(dispatch_get_main_queue(), ^{ [owner ingressOverflow]; }); }
}
static void StreamEvent(cef_dev_tools_message_observer_t *base, cef_browser_t *browser,
                        const cef_string_t *method, const void *payload, size_t length) {
    auto *observer = reinterpret_cast<HostedStreamObserver *>(base);
    if (method == nullptr || method->str == nullptr || method->length > 64 || payload == nullptr ||
        CEFBridgeBrowserIdentifier(browser) != observer->browserID) { return; }
    NSString *name = [[NSString alloc] initWithCharacters:(const unichar *)method->str length:method->length];
    if (![name isEqualToString:@"Page.screencastFrame"]) { return; }
    CEFHostedStreamProbe *owner = observer->owner;
    if (owner == nil) { return; }
    if (length == 0 || length > 2 * 1024 * 1024 + 4096) { StreamOverflow(observer, owner); return; }

    // The closed gate cannot race a new reservation into the retirement group.
    bool overflow = false;
    {
        std::lock_guard<std::mutex> guard(observer->ingressLock);
        if (!observer->ingressOpen) { return; }
        if (observer->ingress >= 3) {
            overflow = true;
        } else {
            ++observer->ingress;
            dispatch_group_enter(observer->ingressGroup);
            observer->api.base.add_ref(&observer->api.base);
        }
    }
    if (overflow) { StreamOverflow(observer, owner); return; }
#if defined(KELPIE_HOSTED_STREAM_MOCK)
    CEFHostedStreamMockAfterReserve();
#endif
    NSData *copy = [NSData dataWithBytes:payload length:length];
    if (copy == nil) {
        { std::lock_guard<std::mutex> guard(observer->ingressLock); --observer->ingress; }
        dispatch_group_leave(observer->ingressGroup);
        StreamOverflow(observer, owner);
        observer->api.base.release(&observer->api.base);
        return;
    }
    const int browserID = observer->browserID;
    dispatch_async(dispatch_get_main_queue(), ^{
        [owner consumeBrowser:browserID payload:copy];
        { std::lock_guard<std::mutex> guard(observer->ingressLock); --observer->ingress; }
        dispatch_group_leave(observer->ingressGroup);
        observer->api.base.release(&observer->api.base);
    });
}

static BOOL StreamJSONNumber(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID();
}

@implementation CEFHostedStreamProbe

- (instancetype)initWithBridge:(CEFBridge *)bridge
                         epoch:(uint64_t)epoch
                         width:(double)width
                        height:(double)height
                      identity:(BOOL (^)(void))identity {
    if ((self = [super init])) {
        _bridge = bridge;
        _epoch = epoch;
        _expectedWidth = width;
        _expectedHeight = height;
        _identity = [identity copy];
        if (_identity == nil) { _identity = ^BOOL { return NO; }; }
        _pending = dispatch_group_create();
        _waiters = [NSMutableArray array];
    }
    return self;
}

- (void)startWithCompletion:(void (^)(BOOL))completion {
    NSCAssert(NSThread.isMainThread, @"Hosted stream must start on main thread");
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    if (_started || _stopping || ![env[@"GITHUB_ACTIONS"] isEqualToString:@"true"] ||
        ![env[@"RUNNER_OS"] isEqualToString:@"macOS"] || ![env[@"KELPIE_HOSTED_RUNTIME"] isEqualToString:@"1"] ||
        ![env[@"KELPIE_CEF_STREAM_TEST"] isEqualToString:@"1"] || !_identity() ||
        !std::isfinite(_expectedWidth) || !std::isfinite(_expectedHeight) ||
        _expectedWidth <= 0 || _expectedHeight <= 0 || _expectedWidth > 8192 || _expectedHeight > 8192) {
        completion(NO);
        return;
    }
    cef_browser_t *browser = [_bridge activeBrowser];
    _browserID = CEFBridgeBrowserIdentifier(browser);
    _host = CEFBridgeCopyBrowserHost(browser);
    if (_browserID == 0 || _host == nullptr || _host->add_dev_tools_message_observer == nullptr) {
        if (_host != nullptr) { _host->base.release(&_host->base); _host = nullptr; }
        completion(NO);
        return;
    }
    _observer = new HostedStreamObserver();
    _observer->owner = self;
    _observer->browserID = _browserID;
    _observer->api.base.size = sizeof(_observer->api);
    _observer->api.base.add_ref = StreamAddRef;
    _observer->api.base.release = StreamRelease;
    _observer->api.base.has_one_ref = StreamHasOne;
    _observer->api.base.has_at_least_one_ref = StreamHasAny;
    _observer->api.on_dev_tools_message = StreamRaw;
    _observer->api.on_dev_tools_method_result = StreamResult;
    _observer->api.on_dev_tools_event = StreamEvent;
    _observer->api.on_dev_tools_agent_attached = StreamAttached;
    _observer->api.on_dev_tools_agent_detached = StreamDetached;
    _registration = _host->add_dev_tools_message_observer(_host, &_observer->api);
    if (_registration == nullptr) { [self releaseHandles]; completion(NO); return; }
    _fence = std::make_unique<CEFHostedStreamFence>(_browserID, _epoch, NSProcessInfo.processInfo.systemUptime * 1000);
    _started = YES;
    _keepAlive = self;
    CEFBridgeSendBrowserControlCommand(_host, @"Page.startScreencast",
        @{@"format": @"png", @"maxWidth": @640, @"maxHeight": @640, @"everyNthFrame": @1},
        ^(BOOL success, NSDictionary *) {
            if (!success || self->_stopping || self->_stopped || !self->_identity()) {
                if (self->_fence) { self->_fence->invalidate(); }
                [self stopWithCompletion:^(BOOL) {}];
                completion(NO);
                return;
            }
            completion(YES);
        });
    __weak CEFHostedStreamProbe *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [weakSelf stopWithCompletion:^(BOOL) {}];
    });
}

- (void)consumeBrowser:(int)browser payload:(NSData *)payload {
    if (!_started || _stopping || _stopped || !_fence || browser != _browserID) { return; }
    NSDictionary *event = payload.length > 0 ? [NSJSONSerialization JSONObjectWithData:payload options:0 error:nil] : nil;
    if (![event isKindOfClass:NSDictionary.class]) { _fence->invalidate(); [self stopWithCompletion:^(BOOL) {}]; return; }
    id number = event[@"sessionId"];
    id data = event[@"data"];
    NSDictionary *metadata = [event[@"metadata"] isKindOfClass:NSDictionary.class] ? event[@"metadata"] : nil;
    id timestamp = metadata[@"timestamp"];
    const double session = StreamJSONNumber(number) ? [number doubleValue] : 0;
    const double protocolMs = StreamJSONNumber(timestamp) ? [timestamp doubleValue] * 1000 : NAN;
    if (!std::isfinite(session) || session < 1 || session > INT_MAX || floor(session) != session ||
        ![data isKindOfClass:NSString.class]) {
        _fence->invalidate(); [self stopWithCompletion:^(BOOL) {}]; return;
    }
    BOOL coherentMetadata = YES;
    const NSArray<NSString *> *fields = @[@"deviceWidth", @"deviceHeight", @"pageScaleFactor",
                                           @"scrollOffsetX", @"scrollOffsetY", @"offsetTop"];
    const double expected[] = {_expectedWidth, _expectedHeight, 1, 0, 0, 0};
    for (NSUInteger index = 0; index < fields.count; ++index) {
        id value = metadata[fields[index]];
        if (!StreamJSONNumber(value) || !std::isfinite([value doubleValue]) ||
            std::abs([value doubleValue] - expected[index]) > 0.01) {
            coherentMetadata = NO;
            break;
        }
    }
    uint64_t token = 0;
    const auto decision = _fence->admit(browser, _epoch, static_cast<int>(session),
        NSProcessInfo.processInfo.systemUptime * 1000, protocolMs, [data length], _identity() && coherentMetadata, &token);
    if (decision == CEFHostedStreamFence::Decision::reject) { return; }
    dispatch_group_enter(_pending);
    CEFBridgeSendBrowserControlCommand(_host, @"Page.screencastFrameAck", @{@"sessionId": number},
        ^(BOOL success, NSDictionary *) {
            if (!success && self->_fence) { self->_fence->invalidate(); }
            dispatch_group_leave(self->_pending);
        });
    if (decision == CEFHostedStreamFence::Decision::ackStop) { [self stopWithCompletion:^(BOOL) {}]; return; }
    if (decision != CEFHostedStreamFence::Decision::ackDecode) { return; }
    NSString *encoded = [data copy];
    dispatch_group_enter(_pending);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSData *image = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
        int x = 0, y = 0;
        const BOOL decoded = image != nil && CEFHostedStreamLocateRed(image, &x, &y);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_fence) { self->_fence->complete(self->_epoch, token, self->_identity(), decoded, x, y); }
            dispatch_group_leave(self->_pending);
        });
    });
}

- (void)ingressOverflow {
    if (_fence) { _fence->invalidate(); }
    [self stopWithCompletion:^(BOOL) {}];
}

- (void)agentDetached {
    if (_fence) { _fence->invalidate(); }
    [self stopWithCompletion:^(BOOL) {}];
}

- (void)stopWithCompletion:(void (^)(BOOL))completion {
    NSCAssert(NSThread.isMainThread, @"Hosted stream must stop on main thread");
    if (_stopped) { completion(_stopSucceeded); return; }
    [_waiters addObject:[completion copy]];
    if (_stopping) { return; }
    _stopping = YES;
    if (_observer != nullptr) {
        std::lock_guard<std::mutex> guard(_observer->ingressLock);
        _observer->ingressOpen = false;
    }
    if (_host == nullptr || !_started) { [self finishStop:NO]; return; }
    CEFBridgeSendBrowserControlCommand(_host, @"Page.stopScreencast", nil, ^(BOOL success, NSDictionary *) {
        if (!success && self->_fence) { self->_fence->invalidate(); }
        dispatch_group_notify(self->_pending, dispatch_get_main_queue(), ^{
            if (self->_observer == nullptr) { [self finishStop:success]; return; }
            dispatch_group_notify(self->_observer->ingressGroup, dispatch_get_main_queue(), ^{ [self finishStop:success]; });
        });
    });
}

- (void)finishStop:(BOOL)success {
    if (_stopped) { return; }
    _stopped = YES;
    _stopSucceeded = success;
    [self releaseHandles];
    NSArray<void (^)(BOOL)> *waiters = [_waiters copy];
    [_waiters removeAllObjects];
    for (void (^completion)(BOOL) in waiters) { completion(success); }
    _keepAlive = nil;
}

- (void)releaseHandles {
    if (_observer != nullptr) { _observer->owner = nil; }
    if (_registration != nullptr) { _registration->base.release(&_registration->base); _registration = nullptr; }
    if (_observer != nullptr) { _observer->api.base.release(&_observer->api.base); _observer = nullptr; }
    if (_host != nullptr) { _host->base.release(&_host->base); _host = nullptr; }
}

- (NSArray<NSDictionary *> *)sealAfterAudit:(BOOL)authorized {
    NSCAssert(NSThread.isMainThread, @"Hosted stream audit must run on main thread");
    if (!_stopped || !_stopSucceeded || !_fence) { return nil; }
    auto samples = _fence->seal(authorized && _identity());
    if (!samples) { return nil; }
    NSMutableArray<NSDictionary *> *result = [NSMutableArray arrayWithCapacity:samples->size()];
    const double firstReceipt = samples->empty() ? 0 : samples->front().receiptMs;
    const double firstProtocol = samples->empty() ? 0 : samples->front().protocolMs;
    for (const auto &sample : *samples) {
        [result addObject:@{@"receiptMs": @(sample.receiptMs - firstReceipt),
                            @"protocolMs": @(sample.protocolMs - firstProtocol),
                            @"x": @(sample.x), @"y": @(sample.y)}];
    }
    return result;
}

@end
#endif
