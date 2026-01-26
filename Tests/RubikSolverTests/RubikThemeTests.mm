//
//  RubikThemeTests.mm
//  RubikSolverTests - Studio Dark Design System
//

#import <XCTest/XCTest.h>

#import "RubikTheme.h"

@interface RubikThemeTests : XCTestCase
@end

@implementation RubikThemeTests

- (void)testSemanticColoursAreOpaqueAndDistinct {
    NSArray<NSColor*>* colours = @[
        [RubikTheme background], [RubikTheme sidebar], [RubikTheme card],
        [RubikTheme cardElevated], [RubikTheme separator], [RubikTheme accent],
        [RubikTheme accentSoft], [RubikTheme success], [RubikTheme warning],
        [RubikTheme danger], [RubikTheme textPrimary], [RubikTheme textSecondary],
        [RubikTheme textTertiary],
    ];
    for (NSColor* colour in colours) {
        XCTAssertNotNil(colour);
        NSColor* rgb = [colour colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        XCTAssertNotNil(rgb);
        XCTAssertGreaterThanOrEqual(rgb.alphaComponent, 0.0);
    }

    XCTAssertNotEqualObjects([RubikTheme background], [RubikTheme accent]);
    XCTAssertNotEqualObjects([RubikTheme success], [RubikTheme danger]);
}

- (void)testTypographyAndSymbols {
    XCTAssertNotNil([RubikTheme titleFont]);
    XCTAssertNotNil([RubikTheme headingFont]);
    XCTAssertNotNil([RubikTheme bodyFont]);
    XCTAssertNotNil([RubikTheme captionFont]);
    XCTAssertNotNil([RubikTheme monoFontOfSize:13 weight:NSFontWeightBold]);

    XCTAssertGreaterThan([RubikTheme titleFont].pointSize, [RubikTheme captionFont].pointSize);

    for (NSString* symbol in @[ @"cube.transparent.fill", @"play.fill", @"camera.fill",
                                @"sparkles", @"doc.on.doc" ]) {
        XCTAssertNotNil([RubikTheme symbolNamed:symbol size:14 weight:NSFontWeightSemibold],
                        @"missing SF Symbol %@", symbol);
    }
}

- (void)testReusableControlsCarryTheirTitlesAndActions {
    NSTextField* label = [RubikTheme labelWithText:@"Hello"
                                             font:[RubikTheme bodyFont]
                                            color:[RubikTheme textPrimary]];
    XCTAssertEqualObjects(label.stringValue, @"Hello");
    XCTAssertFalse(label.isEditable);
    XCTAssertFalse(label.isBordered);

    NSButton* filled = [RubikTheme filledButton:@"Solve" symbol:@"sparkles"
                                          target:nil action:nil];
    XCTAssertEqualObjects(filled.title, @"Solve");
    XCTAssertNotNil(filled.image);
    XCTAssertTrue(filled.wantsLayer);

    NSButton* soft = [RubikTheme softButton:@"Scramble" symbol:@"shuffle"
                                      target:nil action:nil];
    XCTAssertEqualObjects(soft.title, @"Scramble");

    NSButton* symbol = [RubikTheme symbolButton:@"doc.on.doc" tooltip:@"Copy"
                                          target:nil action:nil];
    XCTAssertNotNil(symbol.image);
    XCTAssertEqualObjects(symbol.toolTip, @"Copy");

    NSView* card = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    [RubikTheme applyCardStyle:card elevated:YES];
    XCTAssertTrue(card.wantsLayer);
    XCTAssertGreaterThan(card.layer.cornerRadius, 0.0);
}

- (void)testProgressViewClampsItsValue {
    RubikProgressView* progress = [[RubikProgressView alloc] initWithFrame:NSMakeRect(0, 0, 100, 4)];
    progress.doubleValue = 0.42;
    XCTAssertEqualWithAccuracy(progress.doubleValue, 0.42, 0.0001);

    progress.doubleValue = 2.0;
    XCTAssertLessThanOrEqual(progress.doubleValue, 1.0);
    progress.doubleValue = -1.0;
    XCTAssertGreaterThanOrEqual(progress.doubleValue, 0.0);
}

@end
