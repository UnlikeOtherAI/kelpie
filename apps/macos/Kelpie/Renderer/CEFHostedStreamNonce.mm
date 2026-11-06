#import "CEFHostedStreamNonce.h"

#if defined(DEBUG) && defined(KELPIE_HOSTED_STREAM_TEST)
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#include <cmath>

BOOL CEFHostedStreamHasNonce(NSData *encoded, uint16_t nonce, double viewportWidth, double viewportHeight) {
    if (encoded.length == 0 || encoded.length > 2 * 1024 * 1024 || !std::isfinite(viewportWidth) ||
        !std::isfinite(viewportHeight) || viewportWidth < 48 || viewportHeight < 48 ||
        viewportWidth > 8192 || viewportHeight > 8192) { return NO; }
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)encoded, nullptr);
    if (!source) { return NO; }
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, nullptr));
    const double rawWidth = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue];
    const double rawHeight = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue];
    if (!std::isfinite(rawWidth) || !std::isfinite(rawHeight) || rawWidth < 48 || rawHeight < 48 ||
        rawWidth > 1920 || rawHeight > 1920 || floor(rawWidth) != rawWidth || floor(rawHeight) != rawHeight) {
        CFRelease(source); return NO;
    }
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, nullptr);
    CFRelease(source);
    if (!image) { return NO; }
    const size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    if (width != static_cast<size_t>(rawWidth) || height != static_cast<size_t>(rawHeight)) {
        CGImageRelease(image); return NO;
    }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = space ? CGBitmapContextCreate(nullptr, width, height, 8, width * 4, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big) : nullptr;
    if (space) { CGColorSpaceRelease(space); }
    if (!context) { CGImageRelease(image); return NO; }
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGImageRelease(image);
    const auto *rgba = static_cast<const uint8_t *>(CGBitmapContextGetData(context));
    bool matches = rgba != nullptr;
    for (unsigned bit = 0; bit < 16 && matches; ++bit) {
        const size_t x = static_cast<size_t>((bit % 4 * 12 + 6) * width / viewportWidth);
        const size_t topY = static_cast<size_t>((bit / 4 * 12 + 6) * height / viewportHeight);
        if (x >= width || topY >= height) { matches = false; break; }
        const size_t offset = (topY * width + x) * 4;
        const bool gray = (nonce & (1u << bit)) != 0;
        for (unsigned channel = 0; channel < 3; ++channel) {
            if (gray ? (rgba[offset + channel] < 184 || rgba[offset + channel] > 224) : rgba[offset + channel] < 239) { matches = false; }
        }
        if (rgba[offset + 3] < 250) { matches = false; }
    }
    CGContextRelease(context);
    return matches;
}
#endif
