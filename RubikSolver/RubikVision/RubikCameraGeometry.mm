//
//  RubikCameraGeometry.mm
//  RubikSolver - Preview / Pixel-Buffer Coordinate Mapping
//

#import "RubikCameraGeometry.h"

#include <algorithm>

@implementation RubikCameraGeometry

+ (NSRect)aspectFillRectForContentSize:(CGSize)contentSize
                              inBounds:(NSRect)bounds {
    if (contentSize.width <= 0 || contentSize.height <= 0 ||
        bounds.size.width <= 0 || bounds.size.height <= 0) {
        return NSZeroRect;
    }

    const CGFloat scale = std::max(bounds.size.width / contentSize.width,
                                   bounds.size.height / contentSize.height);
    const CGFloat width = contentSize.width * scale;
    const CGFloat height = contentSize.height * scale;
    return NSMakeRect(NSMidX(bounds) - width / 2.0,
                      NSMidY(bounds) - height / 2.0,
                      width, height);
}

+ (CGRect)normalizedROIForViewRect:(NSRect)viewRect
                       contentSize:(CGSize)contentSize
                          inBounds:(NSRect)bounds {
    const NSRect fillRect = [self aspectFillRectForContentSize:contentSize inBounds:bounds];
    if (fillRect.size.width <= 0 || fillRect.size.height <= 0) return CGRectZero;

    const CGFloat x = (NSMinX(viewRect) - NSMinX(fillRect)) / fillRect.size.width;
    // NSView is bottom-up; pixel buffers are top-down.
    const CGFloat y = (NSMaxY(fillRect) - NSMaxY(viewRect)) / fillRect.size.height;
    const CGFloat w = viewRect.size.width / fillRect.size.width;
    const CGFloat h = viewRect.size.height / fillRect.size.height;
    return [self clampNormalizedROI:CGRectMake(x, y, w, h)];
}

+ (NSRect)viewRectForNormalizedROI:(CGRect)roi
                       contentSize:(CGSize)contentSize
                          inBounds:(NSRect)bounds {
    const NSRect fillRect = [self aspectFillRectForContentSize:contentSize inBounds:bounds];
    if (fillRect.size.width <= 0 || fillRect.size.height <= 0) return NSZeroRect;

    const CGFloat x = NSMinX(fillRect) + roi.origin.x * fillRect.size.width;
    const CGFloat top = NSMinY(fillRect) + roi.origin.y * fillRect.size.height;
    const CGFloat w = roi.size.width * fillRect.size.width;
    const CGFloat h = roi.size.height * fillRect.size.height;
    // Convert the top-left rect back to bottom-left view coordinates.
    return NSMakeRect(x,
                      NSMaxY(fillRect) - top - h,
                      w, h);
}

+ (NSRect)squareGridRectInBounds:(NSRect)bounds
                        fraction:(CGFloat)fraction
                         minSide:(CGFloat)minSide
                   centerOffsetY:(CGFloat)offsetY {
    CGFloat side = std::min(bounds.size.width * fraction, bounds.size.height * fraction);
    side = std::max(std::min(minSide, std::min(bounds.size.width, bounds.size.height)), side);
    return NSMakeRect((bounds.size.width - side) / 2.0,
                      (bounds.size.height - side) / 2.0 + offsetY,
                      side, side);
}

+ (CGRect)clampNormalizedROI:(CGRect)roi {
    const CGFloat x0 = std::max(0.0, std::min(1.0, CGRectGetMinX(roi)));
    const CGFloat y0 = std::max(0.0, std::min(1.0, CGRectGetMinY(roi)));
    const CGFloat x1 = std::max(0.0, std::min(1.0, CGRectGetMaxX(roi)));
    const CGFloat y1 = std::max(0.0, std::min(1.0, CGRectGetMaxY(roi)));
    return CGRectMake(x0, y0, std::max(0.0, x1 - x0), std::max(0.0, y1 - y0));
}

@end
