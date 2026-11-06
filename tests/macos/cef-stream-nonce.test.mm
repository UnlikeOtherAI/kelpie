#import <AppKit/AppKit.h>
#import <ImageIO/ImageIO.h>
#import "../../apps/macos/Kelpie/Renderer/CEFHostedStreamNonce.h"
#include <cassert>

static NSData *fixture(uint16_t nonce) {
    NSMutableData *data = [NSMutableData data];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(nullptr, 100, 100, 8, 400, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1); CGContextFillRect(context, CGRectMake(0, 0, 100, 100));
    for (unsigned bit = 0; bit < 16; ++bit) {
        if ((nonce & (1u << bit)) == 0) { continue; }
        CGContextSetRGBFillColor(context, 0.8, 0.8, 0.8, 1);
        CGContextFillRect(context, CGRectMake((bit % 4) * 12, 100 - (bit / 4 + 1) * 12, 12, 12));
    }
    CGImageRef image = CGBitmapContextCreateImage(context); CGContextRelease(context);
    CGImageDestinationRef dest = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, CFSTR("public.png"), 1, nullptr);
    CGImageDestinationAddImage(dest, image, nullptr); CGImageDestinationFinalize(dest);
    CFRelease(dest); CGImageRelease(image); return data;
}
int main() { @autoreleasepool {
    NSData *png = fixture(0xA59C);
    assert(CEFHostedStreamHasNonce(png, 0xA59C, 100, 100));
    assert(!CEFHostedStreamHasNonce(png, 0xA59D, 100, 100));
    assert(!CEFHostedStreamHasNonce(png, 0xA59C, 0, 100));
    assert(!CEFHostedStreamHasNonce([NSData data], 0xA59C, 100, 100));
    puts("PASS: fixture nonce and mismatch");
} }
