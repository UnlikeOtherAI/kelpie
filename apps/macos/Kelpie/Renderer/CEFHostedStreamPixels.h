#pragma once
#import <Foundation/Foundation.h>

#if defined(KELPIE_HOSTED_STREAM_TEST)
// Only for the bounded synthetic hosted fixture. No decoded pixels leave this function.
BOOL CEFHostedStreamLocateRed(NSData *encoded, int *x, int *y);
#endif
