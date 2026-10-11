#import "CEFBridge_Internal.h"

// Reuse the bounded native CDP transport. The isolated world is created in the
// live main frame on every operation, so navigation cannot reuse a stale context.
@implementation CEFBridge (BrowserControl)

- (void)evaluateBrowserControl:(NSString *)expression
                   completion:(void (^)(id result, NSError *error))completion {
    cef_browser_host_t *host = CEFBridgeCopyBrowserHost([self activeBrowser]);
    if (host == nullptr) {
        completion(nil, [NSError errorWithDomain:@"KelpieBrowserControl" code:1 userInfo:nil]);
        return;
    }
    void (^finish)(id, NSError *) = ^(id value, NSError *error) {
        host->base.release(&host->base);
        completion(value, error);
    };
    NSError *failure = [NSError errorWithDomain:@"KelpieBrowserControl" code:2 userInfo:nil];
    CEFBridgeSendDevToolsCommand(host, @"Page.getFrameTree", nil, ^(BOOL success, NSDictionary *tree) {
        NSString *frameID = tree[@"frameTree"][@"frame"][@"id"];
        if (!success || ![frameID isKindOfClass:NSString.class]) { finish(nil, failure); return; }
        NSDictionary *world = @{@"frameId": frameID, @"worldName": @"KelpieBrowserControl", @"grantUniveralAccess": @NO};
        CEFBridgeSendDevToolsCommand(host, @"Page.createIsolatedWorld", world, ^(BOOL created, NSDictionary *context) {
            NSNumber *contextID = context[@"executionContextId"];
            if (!created || ![contextID isKindOfClass:NSNumber.class]) { finish(nil, failure); return; }
            NSDictionary *params = @{@"expression": expression, @"contextId": contextID, @"returnByValue": @YES};
            CEFBridgeSendDevToolsCommand(host, @"Runtime.evaluate", params, ^(BOOL evaluated, NSDictionary *result) {
                if (!evaluated || result[@"exceptionDetails"] != nil) { finish(nil, failure); return; }
                finish(result[@"result"][@"value"], nil);
            });
        });
    });
}

@end
