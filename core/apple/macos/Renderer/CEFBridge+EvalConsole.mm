#import "CEFBridge_Internal.h"

static NSString *const kCEFBridgeEvalErrorDomain = @"com.kelpie.browser.cef";
static NSString *const kCEFBridgeEvalConsolePrefix = @"__kelpie_eval__:";

static void FinishEval(CEFBridge *owner, NSString *identifier, NSString *result, NSError *error) {
    if (owner == nil || identifier.length == 0) {
        return;
    }
    [owner _finishEvalWithIdentifier:identifier result:result error:error];
}

@implementation CEFBridge (EvalConsole)

- (void)cefBridgeHandleConsoleMessage:(NSString *)message
                               source:(NSString *)source
                                 line:(NSInteger)line {
    if ([message hasPrefix:kCEFBridgeEvalConsolePrefix]) {
        NSString *payload = [message substringFromIndex:kCEFBridgeEvalConsolePrefix.length];
        NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *decoded = data != nil ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *identifier = decoded[@"id"];
        if ([decoded[@"ok"] boolValue]) {
            FinishEval(self, identifier, CEFBridgeJSONStringForValue(decoded[@"value"]), nil);
        } else {
            NSString *messageText = decoded[@"error"] ?: @"JavaScript evaluation failed";
            NSError *error = [NSError errorWithDomain:kCEFBridgeEvalErrorDomain code:3 userInfo:@{NSLocalizedDescriptionKey: messageText}];
            FinishEval(self, identifier, nil, error);
        }
        return;
    }

    if (self.onConsoleMessage != nil) {
        NSDictionary *payload = @{
            @"message": message ?: @"",
            @"source": source ?: @"",
            @"line": @(line),
        };
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.onConsoleMessage != nil) {
                self.onConsoleMessage(payload);
            }
        });
    }
}

@end
