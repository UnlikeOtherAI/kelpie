#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#include "../../apps/macos/Kelpie/Renderer/CEFHostedStreamPixels.h"
#include <cassert>

static NSData *fixture(bool yellow) {
    NSMutableData *data = [NSMutableData data];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(nullptr, 200, 120, 8, 800, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    assert(context);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1); CGContextFillRect(context, CGRectMake(0, 0, 200, 120));
    if (yellow) { CGContextSetRGBFillColor(context, 0.97, 0.87, 0.27, 1); }
    else { CGContextSetRGBFillColor(context, 1, 0.1, 0.1, 1); }
    CGContextFillRect(context, CGRectMake(20, 30, 20, 20));
    CGImageRef image = CGBitmapContextCreateImage(context); CGContextRelease(context);
    CGImageDestinationRef dest = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, CFSTR("public.png"), 1, nullptr);
    assert(image && dest); CGImageDestinationAddImage(dest, image, nullptr);
    assert(CGImageDestinationFinalize(dest)); CFRelease(dest); CGImageRelease(image);
    return data;
}
int main() { @autoreleasepool {
    int x = -1, y = -1;
    NSData *red = fixture(false), *yellow = fixture(true);
    assert(CEFHostedStreamLocateRed(red, &x, &y) && x >= 28 && x <= 31 && y >= 78 && y <= 81);
    assert(!CEFHostedStreamLocateYellow(red, &x, &y));
    assert(CEFHostedStreamLocateYellow(yellow, &x, &y) && x >= 28 && x <= 31 && y >= 78 && y <= 81);
    assert(!CEFHostedStreamLocateRed(yellow, &x, &y));
    assert(!CEFHostedStreamLocateYellow([NSData dataWithBytes:"bad" length:3], &x, &y));
    assert(!CEFHostedStreamLocateYellow([NSMutableData dataWithLength:2 * 1024 * 1024 + 1], &x, &y));
    puts("PASS: bounded distinct red/yellow synthetic PNG centroids and negative controls");
} }
