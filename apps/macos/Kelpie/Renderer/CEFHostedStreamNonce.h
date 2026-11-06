#pragma once
#import <Foundation/Foundation.h>

#if defined(DEBUG) && defined(KELPIE_HOSTED_STREAM_TEST)
// Synthetic fixture only. Inspect the sixteen binary cells without exporting pixels.
BOOL CEFHostedStreamHasNonce(NSData *encoded, uint16_t nonce, double viewportWidth, double viewportHeight);
#endif
