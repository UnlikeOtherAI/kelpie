#if !defined(KELPIE_WEBKIT_ONLY)
#import <XCTest/XCTest.h>
#import "CEFBridge.h"

@interface CEFStaticLinkTests : XCTestCase
@end

@implementation CEFStaticLinkTests
- (void)testStaticLibraryIncludesLifecycleCategory {
    XCTAssertTrue([CEFBridge respondsToSelector:@selector(initializeCEF)]);
    XCTAssertTrue([CEFBridge respondsToSelector:@selector(shutdownCEF)]);
    XCTAssertTrue([CEFBridge respondsToSelector:@selector(doMessageLoopWork)]);
}
@end
#endif
