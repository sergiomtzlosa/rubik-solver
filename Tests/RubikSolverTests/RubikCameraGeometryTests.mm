//
//  RubikCameraGeometryTests.mm
//  RubikSolverTests - Preview / Pixel-Buffer Coordinate Mapping
//

#import <XCTest/XCTest.h>

#import "RubikCameraGeometry.h"

@interface RubikCameraGeometryTests : XCTestCase
@end

@implementation RubikCameraGeometryTests

- (void)testAspectFillCropsLandscapeContentToPortraitBounds {
    const NSRect bounds = NSMakeRect(0, 0, 800, 600);
    const NSRect fill = [RubikCameraGeometry aspectFillRectForContentSize:CGSizeMake(1920, 1080)
                                                                 inBounds:bounds];
    XCTAssertEqualWithAccuracy(fill.size.height, 600.0, 0.01);
    XCTAssertGreaterThan(fill.size.width, 800.0);
    XCTAssertEqualWithAccuracy(NSMidX(fill), NSMidX(bounds), 0.01);
    XCTAssertEqualWithAccuracy(NSMidY(fill), NSMidY(bounds), 0.01);
    XCTAssertLessThan(NSMinX(fill), 0.0);
}

- (void)testAspectFillCropsPortraitContentToLandscapeBounds {
    const NSRect bounds = NSMakeRect(10, 20, 800, 600);
    const NSRect fill = [RubikCameraGeometry aspectFillRectForContentSize:CGSizeMake(1080, 1920)
                                                                 inBounds:bounds];
    XCTAssertEqualWithAccuracy(fill.size.width, 800.0, 0.01);
    XCTAssertGreaterThan(fill.size.height, 600.0);
    XCTAssertEqualWithAccuracy(NSMidX(fill), 410.0, 0.01);
    XCTAssertEqualWithAccuracy(NSMidY(fill), 320.0, 0.01);
}

- (void)testDegenerateSizesReturnZeroRect {
    XCTAssertTrue(NSIsEmptyRect([RubikCameraGeometry
        aspectFillRectForContentSize:CGSizeZero
        inBounds:NSMakeRect(0, 0, 100, 100)]));
    XCTAssertTrue(NSIsEmptyRect([RubikCameraGeometry
        aspectFillRectForContentSize:CGSizeMake(100, 100)
        inBounds:NSZeroRect]));
    XCTAssertTrue(CGRectEqualToRect([RubikCameraGeometry
        normalizedROIForViewRect:NSMakeRect(0, 0, 10, 10)
        contentSize:CGSizeZero
        inBounds:NSMakeRect(0, 0, 100, 100)], CGRectZero));
}

- (void)testCenterViewRectMapsToCenteredNormalizedROI {
    const CGRect roi = [RubikCameraGeometry
        normalizedROIForViewRect:NSMakeRect(25, 25, 50, 50)
        contentSize:CGSizeMake(1000, 1000)
        inBounds:NSMakeRect(0, 0, 100, 100)];
    XCTAssertEqualWithAccuracy(roi.origin.x, 0.25, 0.0001);
    XCTAssertEqualWithAccuracy(roi.origin.y, 0.25, 0.0001);
    XCTAssertEqualWithAccuracy(roi.size.width, 0.50, 0.0001);
    XCTAssertEqualWithAccuracy(roi.size.height, 0.50, 0.0001);
}

- (void)testTopOfViewMapsToTopOfPixelBuffer {
    const CGRect roi = [RubikCameraGeometry
        normalizedROIForViewRect:NSMakeRect(0, 75, 25, 25)
        contentSize:CGSizeMake(1000, 1000)
        inBounds:NSMakeRect(0, 0, 100, 100)];
    XCTAssertEqualWithAccuracy(roi.origin.y, 0.0, 0.0001);
    XCTAssertEqualWithAccuracy(roi.size.height, 0.25, 0.0001);
}

- (void)testNormalizedROIRoundTrip {
    const CGSize content = CGSizeMake(1440, 1080);
    const NSRect bounds = NSMakeRect(0, 0, 900, 700);
    const NSRect original = NSMakeRect(220, 180, 260, 260);

    const CGRect roi = [RubikCameraGeometry normalizedROIForViewRect:original
                                                         contentSize:content
                                                            inBounds:bounds];
    const NSRect roundTrip = [RubikCameraGeometry viewRectForNormalizedROI:roi
                                                              contentSize:content
                                                                 inBounds:bounds];
    XCTAssertEqualWithAccuracy(roundTrip.origin.x, original.origin.x, 0.01);
    XCTAssertEqualWithAccuracy(roundTrip.origin.y, original.origin.y, 0.01);
    XCTAssertEqualWithAccuracy(roundTrip.size.width, original.size.width, 0.01);
    XCTAssertEqualWithAccuracy(roundTrip.size.height, original.size.height, 0.01);
}

- (void)testClampNormalizedROI {
    const CGRect clamped = [RubikCameraGeometry
        clampNormalizedROI:CGRectMake(-0.2, -0.3, 2.0, 2.0)];
    XCTAssertEqualWithAccuracy(clamped.origin.x, 0.0, 0.0001);
    XCTAssertEqualWithAccuracy(clamped.origin.y, 0.0, 0.0001);
    XCTAssertEqualWithAccuracy(clamped.size.width, 1.0, 0.0001);
    XCTAssertEqualWithAccuracy(clamped.size.height, 1.0, 0.0001);

    const CGRect corner = [RubikCameraGeometry
        clampNormalizedROI:CGRectMake(0.9, 0.9, 0.5, 0.5)];
    XCTAssertEqualWithAccuracy(corner.size.width, 0.1, 0.0001);
    XCTAssertEqualWithAccuracy(corner.size.height, 0.1, 0.0001);
}

- (void)testSquareGridUsesFractionAndOffset {
    const NSRect grid = [RubikCameraGeometry squareGridRectInBounds:NSMakeRect(0, 0, 1000, 800)
                                                          fraction:0.8
                                                           minSide:100
                                                     centerOffsetY:20];
    XCTAssertEqualWithAccuracy(grid.size.width, 640.0, 0.01);
    XCTAssertEqualWithAccuracy(grid.size.height, 640.0, 0.01);
    XCTAssertEqualWithAccuracy(grid.origin.x, 180.0, 0.01);
    XCTAssertEqualWithAccuracy(grid.origin.y, 100.0, 0.01);
}

- (void)testSquareGridHonoursMinimumSide {
    const NSRect grid = [RubikCameraGeometry squareGridRectInBounds:NSMakeRect(0, 0, 300, 200)
                                                          fraction:0.1
                                                           minSide:150
                                                     centerOffsetY:0];
    XCTAssertEqualWithAccuracy(grid.size.width, 150.0, 0.01);
    XCTAssertEqualWithAccuracy(grid.size.height, 150.0, 0.01);
    XCTAssertEqualWithAccuracy(grid.origin.x, 75.0, 0.01);
    XCTAssertEqualWithAccuracy(grid.origin.y, 25.0, 0.01);
}

@end
