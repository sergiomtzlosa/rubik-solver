//
//  RubikCameraGeometry.h
//  RubikSolver - Preview / Pixel-Buffer Coordinate Mapping
//
//  AVCaptureVideoPreviewLayer with AVLayerVideoGravityResizeAspectFill crops
//  the camera frame. The alignment grid is drawn in view coordinates, so the
//  classifier must sample exactly the pixels underneath that grid. These
//  helpers perform the aspect-fill and y-axis conversion in one place.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface RubikCameraGeometry : NSObject

/// The rect (in view coordinates) where an aspect-filled image is displayed.
+ (NSRect)aspectFillRectForContentSize:(CGSize)contentSize
                              inBounds:(NSRect)bounds;

/// Convert a view-space rect into a top-left-origin normalized ROI suitable
/// for `RubikColorClassifier`.
+ (CGRect)normalizedROIForViewRect:(NSRect)viewRect
                       contentSize:(CGSize)contentSize
                          inBounds:(NSRect)bounds;

/// Inverse of `normalizedROIForViewRect:contentSize:inBounds:`.
+ (NSRect)viewRectForNormalizedROI:(CGRect)roi
                       contentSize:(CGSize)contentSize
                          inBounds:(NSRect)bounds;

/// A centered square grid with a maximum side fraction and a minimum side.
+ (NSRect)squareGridRectInBounds:(NSRect)bounds
                        fraction:(CGFloat)fraction
                         minSide:(CGFloat)minSide
                   centerOffsetY:(CGFloat)offsetY;

/// Clamp a normalized ROI to 0...1.
+ (CGRect)clampNormalizedROI:(CGRect)roi;

@end

NS_ASSUME_NONNULL_END
