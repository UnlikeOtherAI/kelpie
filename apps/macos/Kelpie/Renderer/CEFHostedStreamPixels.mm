#import "CEFHostedStreamPixels.h"

#if defined(DEBUG) && defined(KELPIE_HOSTED_STREAM_TEST)
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>

static BOOL LocateSynthetic(NSData *encoded, int *x, int *y, BOOL yellow) {
    if (encoded.length == 0 || encoded.length > 2 * 1024 * 1024 || x == nullptr || y == nullptr) { return NO; }
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)encoded, nullptr);
    if (source == nullptr) { return NO; }
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, nullptr));
    const double width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue];
    const double height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue];
    if (!isfinite(width) || !isfinite(height) || width < 2 || height < 2 || width > 1920 || height > 1920 ||
        floor(width) != width || floor(height) != height) {
        CFRelease(source);
        return NO;
    }
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, nullptr);
    CFRelease(source);
    if (image == nullptr) { return NO; }
    const size_t w = static_cast<size_t>(width), h = static_cast<size_t>(height);
    if (CGImageGetWidth(image) != w || CGImageGetHeight(image) != h) { CGImageRelease(image); return NO; }
    void *bytes = calloc(w * h, 4);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = bytes != nullptr && space != nullptr
        ? CGBitmapContextCreate(bytes, w, h, 8, w * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big)
        : nullptr;
    if (space != nullptr) { CGColorSpaceRelease(space); }
    if (context == nullptr) { free(bytes); CGImageRelease(image); return NO; }
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    const uint8_t *rgba = static_cast<const uint8_t *>(bytes);
    uint64_t count = 0, totalX = 0, totalY = 0;
    for (size_t row = 0; row < h; ++row) {
        for (size_t column = 0; column < w; ++column) {
            const size_t offset = (row * w + column) * 4;
            const BOOL color = yellow ? (rgba[offset] > 220 && rgba[offset + 1] > 190 && rgba[offset + 2] < 140)
                                      : (rgba[offset] > 180 && rgba[offset + 1] < 140 && rgba[offset + 2] < 150);
            if (color && rgba[offset + 3] > 200) {
                ++count;
                totalX += column;
                totalY += row;
            }
        }
    }
    CGContextRelease(context);
    CGImageRelease(image);
    free(bytes);
    if (count < 9) { return NO; }
    *x = static_cast<int>(totalX / count);
    *y = static_cast<int>(totalY / count);
    return YES;
}

BOOL CEFHostedStreamLocateRed(NSData *encoded, int *x, int *y) { return LocateSynthetic(encoded, x, y, NO); }
BOOL CEFHostedStreamLocateYellow(NSData *encoded, int *x, int *y) { return LocateSynthetic(encoded, x, y, YES); }
#endif
