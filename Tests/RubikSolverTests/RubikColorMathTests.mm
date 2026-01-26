//
//  RubikColorMathTests.mm
//  RubikSolverTests - Lighting-Robust CIELAB Sticker Recognition
//

#import <XCTest/XCTest.h>

#include "RubikColorMath.h"

#include <array>
#include <vector>

namespace {

constexpr float kIdealRGB[NUM_COLORS][3] = {
    {0.94f, 0.94f, 0.93f}, // white
    {0.78f, 0.12f, 0.16f}, // red
    {0.04f, 0.62f, 0.28f}, // green
    {0.96f, 0.82f, 0.09f}, // yellow
    {0.94f, 0.43f, 0.06f}, // orange
    {0.05f, 0.32f, 0.72f}, // blue
};

RubikColorReading IdealReading(uint8_t color) {
    return RubikColorMath::analyze(kIdealRGB[color][0],
                                   kIdealRGB[color][1],
                                   kIdealRGB[color][2]);
}

} // namespace

@interface RubikColorMathTests : XCTestCase
@end

@implementation RubikColorMathTests

- (void)testIdealStickerColorsClassifyToTheirFace {
    for (int color = 0; color < NUM_COLORS; ++color) {
        RubikColorReading reading = IdealReading(static_cast<uint8_t>(color));
        XCTAssertEqual(reading.colorIndex, color, @"ideal colour %d was misclassified", color);
        XCTAssertFalse(reading.background);
        XCTAssertTrue(reading.reliable, @"ideal colour %d should be reliable", color);
        XCTAssertGreaterThan(reading.confidence, 0.5f);
        XCTAssertLessThan(reading.deltaE, 1.0f);
        XCTAssertGreaterThanOrEqual(reading.h, 0.0f);
        XCTAssertLessThanOrEqual(reading.h, 360.0f);
        XCTAssertGreaterThanOrEqual(reading.s, 0.0f);
        XCTAssertLessThanOrEqual(reading.s, 1.0f);
        XCTAssertGreaterThanOrEqual(reading.v, 0.0f);
        XCTAssertLessThanOrEqual(reading.v, 1.0f);
    }
}

- (void)testDarkAndLowChromaSamplesAreRejected {
    RubikColorReading black = RubikColorMath::analyze(0.005f, 0.005f, 0.006f);
    XCTAssertTrue(black.background);
    XCTAssertFalse(black.reliable);
    XCTAssertEqual(black.colorIndex, 255);
    XCTAssertEqualWithAccuracy(black.confidence, 0.0f, 0.001f);

    RubikColorReading shadow = RubikColorMath::analyze(0.05f, 0.05f, 0.05f);
    XCTAssertTrue(shadow.background);
    XCTAssertEqual(shadow.colorIndex, 255);

    // A neutral mid-grey is the white sticker under flat light.
    RubikColorReading grey = RubikColorMath::analyze(0.55f, 0.55f, 0.55f);
    XCTAssertFalse(grey.background);
    XCTAssertEqual(grey.colorIndex, COLOR_WHITE);
}

- (void)testLabConversionAndDeltaEMetric {
    RubikLabColor white = RubikColorMath::labFromRGB(1.0f, 1.0f, 1.0f);
    XCTAssertEqualWithAccuracy(white.L, 100.0f, 0.2f);
    XCTAssertEqualWithAccuracy(white.a, 0.0f, 0.2f);
    XCTAssertEqualWithAccuracy(white.b, 0.0f, 0.2f);

    RubikLabColor black = RubikColorMath::labFromRGB(0.0f, 0.0f, 0.0f);
    XCTAssertEqualWithAccuracy(black.L, 0.0f, 0.2f);

    RubikLabColor red = RubikColorMath::labFromRGB(1.0f, 0.0f, 0.0f);
    XCTAssertGreaterThan(red.a, 50.0f);

    XCTAssertEqualWithAccuracy(RubikColorMath::deltaE(red, red), 0.0f, 0.0001f);
    RubikLabColor blue = RubikColorMath::labFromRGB(0.0f, 0.0f, 1.0f);
    XCTAssertEqualWithAccuracy(RubikColorMath::deltaE(red, blue),
                               RubikColorMath::deltaE(blue, red), 0.0001f);
    XCTAssertGreaterThan(RubikColorMath::deltaE(red, blue), 10.0f);
    XCTAssertLessThanOrEqual(RubikColorMath::deltaE(red, blue),
                             RubikColorMath::deltaE(red, white) +
                             RubikColorMath::deltaE(white, blue) + 0.001f);

    XCTAssertGreaterThan(RubikColorMath::chroma(red), 1.0f);
    XCTAssertLessThan(RubikColorMath::chroma(white), 1.0f);
}

- (void)testWhiteReferenceBalanceNeutralizesTheReference {
    RubikWhiteBalance balance = RubikWhiteBalance::fromWhiteReference(0.80f, 0.60f, 0.40f);
    XCTAssertTrue(balance.valid);
    XCTAssertEqualWithAccuracy(balance.scaleR, 0.75f, 0.01f);
    XCTAssertEqualWithAccuracy(balance.scaleG, 1.00f, 0.01f);
    XCTAssertEqualWithAccuracy(balance.scaleB, 1.50f, 0.01f);

    const float balancedR = 0.80f * balance.scaleR;
    const float balancedG = 0.60f * balance.scaleG;
    const float balancedB = 0.40f * balance.scaleB;
    XCTAssertEqualWithAccuracy(balancedR, balancedG, 0.001f);
    XCTAssertEqualWithAccuracy(balancedG, balancedB, 0.001f);
}

- (void)testInvalidWhiteReferenceIsRejected {
    RubikWhiteBalance zero = RubikWhiteBalance::fromWhiteReference(0.0f, 0.5f, 0.5f);
    XCTAssertFalse(zero.valid);

    RubikWhiteBalance empty = RubikWhiteBalance::grayWorld({});
    XCTAssertFalse(empty.valid);
}

- (void)testGrayWorldBalanceCorrectsAChannelCast {
    std::vector<std::array<float, 3>> samples(25, {1.0f, 0.80f, 0.60f});
    RubikWhiteBalance balance = RubikWhiteBalance::grayWorld(samples);
    XCTAssertTrue(balance.valid);
    XCTAssertLessThan(balance.scaleR, 1.0f);
    XCTAssertGreaterThan(balance.scaleB, 1.0f);

    const float r = 1.0f * balance.scaleR;
    const float g = 0.80f * balance.scaleG;
    const float b = 0.60f * balance.scaleB;
    XCTAssertEqualWithAccuracy(r, g, 0.001f);
    XCTAssertEqualWithAccuracy(g, b, 0.001f);

    RubikWhiteBalance combined = balance.combinedWith(balance);
    XCTAssertTrue(combined.valid);
    XCTAssertEqualWithAccuracy(combined.scaleR, balance.scaleR * balance.scaleR, 0.0001f);
    XCTAssertEqualWithAccuracy(combined.scaleG, balance.scaleG * balance.scaleG, 0.0001f);
    XCTAssertEqualWithAccuracy(combined.scaleB, balance.scaleB * balance.scaleB, 0.0001f);
}

- (void)testPrototypesFromSixCentreReadings {
    std::array<RubikColorReading, NUM_COLORS> centres;
    for (int color = 0; color < NUM_COLORS; ++color) {
        centres[color] = IdealReading(static_cast<uint8_t>(color));
    }

    std::array<RubikLabColor, NUM_COLORS> prototypes;
    XCTAssertTrue(RubikColorMath::prototypesFromCenters(centres, prototypes));
    for (int color = 0; color < NUM_COLORS; ++color) {
        XCTAssertEqualWithAccuracy(RubikColorMath::deltaE(prototypes[color], centres[color].lab),
                                   0.0f, 0.0001f);
    }

    // Duplicate centres cannot describe six distinct faces.
    std::array<RubikColorReading, NUM_COLORS> duplicates;
    duplicates.fill(IdealReading(COLOR_WHITE));
    XCTAssertFalse(RubikColorMath::prototypesFromCenters(duplicates, prototypes));

    // A rejected centre leaves fewer than six usable prototypes.
    std::array<RubikColorReading, NUM_COLORS> missing;
    for (int color = 0; color < NUM_COLORS; ++color) {
        missing[color] = IdealReading(static_cast<uint8_t>(color));
    }
    missing[3] = RubikColorMath::analyze(0.001f, 0.001f, 0.001f);
    XCTAssertFalse(RubikColorMath::prototypesFromCenters(missing, prototypes));
}

- (void)testLegacyHueClassifierCoversEveryStickerColour {
    XCTAssertEqual(RubikColorMath::legacyHSVClassify(0.0f, 0.05f, 0.9f), COLOR_WHITE);
    XCTAssertEqual(RubikColorMath::legacyHSVClassify(55.0f, 0.9f, 0.9f), COLOR_YELLOW);
    XCTAssertEqual(RubikColorMath::legacyHSVClassify(120.0f, 0.8f, 0.7f), COLOR_GREEN);
    XCTAssertEqual(RubikColorMath::legacyHSVClassify(220.0f, 0.8f, 0.8f), COLOR_BLUE);
    XCTAssertEqual(RubikColorMath::legacyHSVClassify(25.0f, 0.9f, 0.9f), COLOR_ORANGE);
    XCTAssertEqual(RubikColorMath::legacyHSVClassify(350.0f, 0.9f, 0.8f), COLOR_RED);
}

@end
