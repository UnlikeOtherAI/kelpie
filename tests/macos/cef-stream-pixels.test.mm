#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#include "../../apps/macos/Kelpie/Renderer/CEFHostedStreamPixels.h"

int main() {
    @autoreleasepool {
        NSMutableData *data = [NSMutableData data];
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(nullptr, 200, 120, 8, 800, space,
                                                       kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(space);
        if (context == nullptr) { return 1; }
        CGContextSetRGBFillColor(context, 1, 1, 1, 1);
        CGContextFillRect(context, CGRectMake(0, 0, 200, 120));
        CGContextSetRGBFillColor(context, 1, 0.1, 0.1, 1);
        CGContextFillRect(context, CGRectMake(20, 30, 20, 20));
        CGImageRef image = CGBitmapContextCreateImage(context);
        CGContextRelease(context);
        CGImageDestinationRef dest = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, CFSTR("public.png"), 1, nullptr);
        if (image == nullptr || dest == nullptr) { return 1; }
        CGImageDestinationAddImage(dest, image, nullptr);
        const BOOL written = CGImageDestinationFinalize(dest);
        CFRelease(dest);
        CGImageRelease(image);
        int x = -1, y = -1;
        if (!written || !CEFHostedStreamLocateRed(data, &x, &y)) { return 1; }
        if (x < 28 || x > 31 || y < 78 || y > 81) { return 1; }
        if (CEFHostedStreamLocateRed([NSData dataWithBytes:"bad" length:3], &x, &y)) { return 1; }
        if (CEFHostedStreamLocateRed([NSMutableData dataWithLength:2 * 1024 * 1024 + 1], &x, &y)) { return 1; }
        puts("PASS: bounded synthetic PNG decode and red-centroid extraction");
    }
}
