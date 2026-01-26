//
//  RubikStepPanelControllerTests.mm
//  RubikSolverTests - Sidebar Dashboard Behaviour
//

#import <XCTest/XCTest.h>

#import "RubikStepPanelController.h"

#include "RubikTypes.h"

#include <vector>

@interface RubikStepPanelDelegateSpy : NSObject <RubikStepPanelDelegate>
@property (nonatomic) NSInteger jumpIndex;
@property (nonatomic) int lastMove;
@property (nonatomic) BOOL lastInverse;
@property (nonatomic) BOOL autoPlay;
@property (nonatomic) NSTimeInterval speed;
@property (nonatomic) NSInteger solveCount;
@property (nonatomic) NSInteger scrambleCount;
@property (nonatomic) NSInteger cameraCount;
@property (nonatomic) NSInteger pdfCount;
@property (nonatomic) NSInteger copyCount;
@property (nonatomic) NSInteger moveCount;
@end

@implementation RubikStepPanelDelegateSpy

- (instancetype)init {
    self = [super init];
    if (self) {
        _jumpIndex = -1;
        _lastMove = -1;
        _speed = -1;
    }
    return self;
}

- (void)stepPanelDidRequestMove:(int)move isInverse:(BOOL)isInverse {
    _lastMove = move;
    _lastInverse = isInverse;
    ++_moveCount;
}

- (void)stepPanelDidJumpToStep:(NSInteger)stepIndex {
    _jumpIndex = stepIndex;
}

- (void)stepPanelDidRequestAutoPlay:(BOOL)start {
    _autoPlay = start;
}

- (void)stepPanelDidChangeSpeed:(NSTimeInterval)duration {
    _speed = duration;
}

- (void)stepPanelDidRequestPDFExport {
    ++_pdfCount;
}

- (void)stepPanelDidRequestScramble {
    ++_scrambleCount;
}

- (void)stepPanelDidRequestCamera {
    ++_cameraCount;
}

- (void)stepPanelDidRequestSolve {
    ++_solveCount;
}

- (void)stepPanelDidRequestCopyState {
    ++_copyCount;
}

@end

namespace {

NSView* FindViewWithIdentifier(NSView* root, NSString* identifier) {
    if (root == nil) return nil;
    if ([root.accessibilityIdentifier isEqualToString:identifier]) return root;
    for (NSView* subview in root.subviews) {
        NSView* found = FindViewWithIdentifier(subview, identifier);
        if (found) return found;
    }
    if ([root isKindOfClass:[NSScrollView class]]) {
        NSView* document = [(NSScrollView*)root documentView];
        if (document && document != root) {
            return FindViewWithIdentifier(document, identifier);
        }
    }
    return nil;
}

NSTextField* LabelWithIdentifier(NSView* root, NSString* identifier) {
    NSView* view = FindViewWithIdentifier(root, identifier);
    return [view isKindOfClass:[NSTextField class]] ? (NSTextField*)view : nil;
}

NSButton* ButtonWithIdentifier(NSView* root, NSString* identifier) {
    NSView* view = FindViewWithIdentifier(root, identifier);
    return [view isKindOfClass:[NSButton class]] ? (NSButton*)view : nil;
}

} // namespace

@interface RubikStepPanelControllerTests : XCTestCase
@end

@implementation RubikStepPanelControllerTests

- (RubikStepPanelController*)newPanelWithDelegate:(RubikStepPanelDelegateSpy*)spy {
    RubikStepPanelController* panel = [[RubikStepPanelController alloc] init];
    panel.delegate = spy;
    XCTAssertNotNil(panel.view);
    return panel;
}

- (void)testSidebarExposesEveryControlIdentifier {
    RubikStepPanelController* panel = [self newPanelWithDelegate:nil];
    NSView* root = panel.view;

    NSArray<NSString*>* identifiers = @[
        @"stepPanel", @"stepTitle", @"stepStats", @"stepProgress",
        @"currentStepCard", @"currentMoveLabel", @"currentMoveDescription", @"stepCounter",
        @"firstButton", @"prevButton", @"playButton", @"nextButton", @"speedControl",
        @"movesTable", @"movesCountLabel", @"copyStateButton", @"solveButton",
        @"scrambleButton", @"cameraButton", @"pdfButton", @"engineBadge",
    ];
    for (NSString* identifier in identifiers) {
        XCTAssertNotNil(FindViewWithIdentifier(root, identifier),
                        @"missing accessibility identifier %@", identifier);
    }

    XCTAssertEqualObjects(root.accessibilityIdentifier, @"stepPanel");
    XCTAssertEqualObjects(root.accessibilityLabel, @"Solving dashboard");
}

- (void)testSolutionLoadingUpdatesLabelsTableAndProgress {
    RubikStepPanelController* panel = [self newPanelWithDelegate:nil];
    std::vector<int> moves = {MOVE_R, MOVE_U, MOVE_F_PRIME};
    [panel setSolutionMoves:moves solveTimeMs:12.5];

    XCTAssertEqual(panel.solutionMoves.size(), 3u);
    XCTAssertEqual(panel.solutionMoves[0], MOVE_R);
    XCTAssertEqual(panel.currentStepIndex, 0);
    XCTAssertFalse(panel.isAutoPlaying);

    NSView* root = panel.view;
    XCTAssertEqualObjects(LabelWithIdentifier(root, @"currentMoveLabel").stringValue, @"R");
    XCTAssertEqualObjects(LabelWithIdentifier(root, @"stepCounter").stringValue, @"1 / 3");
    XCTAssertEqualObjects(LabelWithIdentifier(root, @"movesCountLabel").stringValue, @"3 MOVES");
    XCTAssertTrue([LabelWithIdentifier(root, @"stepStats").stringValue containsString:@"3 moves"]);

    NSTableView* table = (NSTableView*)FindViewWithIdentifier(root, @"movesTable");
    XCTAssertNotNil(table);
    XCTAssertEqual([table numberOfRows], 3);

    NSButton* previous = ButtonWithIdentifier(root, @"prevButton");
    NSButton* next = ButtonWithIdentifier(root, @"nextButton");
    NSButton* play = ButtonWithIdentifier(root, @"playButton");
    XCTAssertFalse(previous.enabled);
    XCTAssertTrue(next.enabled);
    XCTAssertTrue(play.enabled);
}

- (void)testNavigationSendsVerifiedMovesToDelegate {
    RubikStepPanelDelegateSpy* spy = [[RubikStepPanelDelegateSpy alloc] init];
    RubikStepPanelController* panel = [self newPanelWithDelegate:spy];
    std::vector<int> moves = {MOVE_R, MOVE_U, MOVE_F_PRIME};
    [panel setSolutionMoves:moves solveTimeMs:1.0];

    [panel goToNextStep];
    XCTAssertEqual(panel.currentStepIndex, 1);
    XCTAssertEqual(spy.lastMove, MOVE_R);
    XCTAssertFalse(spy.lastInverse);

    [panel goToNextStep];
    XCTAssertEqual(panel.currentStepIndex, 2);
    XCTAssertEqual(spy.lastMove, MOVE_U);

    [panel goToPreviousStep];
    XCTAssertEqual(panel.currentStepIndex, 1);
    XCTAssertEqual(spy.lastMove, MOVE_U);
    XCTAssertTrue(spy.lastInverse);

    [panel resetToStart];
    XCTAssertEqual(panel.currentStepIndex, 0);
    XCTAssertEqual(spy.jumpIndex, 0);
    XCTAssertGreaterThanOrEqual(spy.moveCount, 3);
}

- (void)testCompletedSolutionShowsSolvedState {
    RubikStepPanelController* panel = [self newPanelWithDelegate:nil];
    [panel setSolutionMoves:{MOVE_R} solveTimeMs:0.5];

    [panel goToNextStep];
    [panel goToNextStep]; // No-op past the end.

    XCTAssertEqual(panel.currentStepIndex, 1);
    NSView* root = panel.view;
    XCTAssertEqualObjects(LabelWithIdentifier(root, @"currentMoveLabel").stringValue, @"✓");
    XCTAssertTrue([LabelWithIdentifier(root, @"currentMoveDescription").stringValue
        containsString:@"Solved"]);
    XCTAssertEqualObjects(LabelWithIdentifier(root, @"stepCounter").stringValue, @"1 / 1");
    XCTAssertFalse(ButtonWithIdentifier(root, @"nextButton").enabled);
}

- (void)testEngineBadgeReflectsExactAndVerifiedGPUEngines {
    RubikStepPanelController* panel = [self newPanelWithDelegate:nil];
    NSView* badge = FindViewWithIdentifier(panel.view, @"engineBadge");
    XCTAssertNotNil(badge);

    [panel setEngineDescription:@"Neural · Core ML GPU" gpuVerified:YES];
    XCTAssertTrue([badge.accessibilityValue containsString:@"Neural"]);
    XCTAssertTrue([badge.accessibilityValue containsString:@"GPU verified"]);
    XCTAssertTrue([LabelWithIdentifier(panel.view, @"stepStats").stringValue
        containsString:@"Neural · Core ML GPU"]);

    [panel setEngineDescription:@"Exact · ckociemba (CPU)" gpuVerified:NO];
    XCTAssertTrue([badge.accessibilityValue containsString:@"Exact"]);
    XCTAssertFalse([badge.accessibilityValue containsString:@"GPU verified"]);
}

- (void)testEmptyStateShowsSolverStatus {
    RubikStepPanelController* panel = [self newPanelWithDelegate:nil];
    [panel setSolverStatusText:@"Invalid cube state."];

    NSView* root = panel.view;
    XCTAssertEqualObjects(LabelWithIdentifier(root, @"currentMoveLabel").stringValue, @"—");
    XCTAssertEqualObjects(LabelWithIdentifier(root, @"currentMoveDescription").stringValue,
                          @"Invalid cube state.");
    XCTAssertFalse(ButtonWithIdentifier(root, @"playButton").enabled);
    XCTAssertFalse(ButtonWithIdentifier(root, @"nextButton").enabled);
    XCTAssertEqualObjects(LabelWithIdentifier(root, @"movesCountLabel").stringValue, @"0 MOVES");
}

- (void)testAutoPlayUsesDelegateAndCanBeStopped {
    RubikStepPanelDelegateSpy* spy = [[RubikStepPanelDelegateSpy alloc] init];
    RubikStepPanelController* panel = [self newPanelWithDelegate:spy];
    [panel setSolutionMoves:{MOVE_R, MOVE_U} solveTimeMs:0.1];

    [panel startAutoPlay];
    XCTAssertTrue(panel.isAutoPlaying);
    XCTAssertTrue(spy.autoPlay);
    XCTAssertEqual(panel.currentStepIndex, 1);

    [panel stopAutoPlay];
    XCTAssertFalse(panel.isAutoPlaying);
    XCTAssertFalse(spy.autoPlay);
}

- (void)testSpeedControlReportsStepDuration {
    RubikStepPanelDelegateSpy* spy = [[RubikStepPanelDelegateSpy alloc] init];
    RubikStepPanelController* panel = [self newPanelWithDelegate:spy];
    NSView* root = panel.view;

    NSSegmentedControl* speed = (NSSegmentedControl*)FindViewWithIdentifier(root, @"speedControl");
    XCTAssertNotNil(speed);
    speed.selectedSegment = 2;
    [speed sendAction:speed.action to:speed.target];
    XCTAssertEqualWithAccuracy(spy.speed, 0.15, 0.0001);

    speed.selectedSegment = 0;
    [speed sendAction:speed.action to:speed.target];
    XCTAssertEqualWithAccuracy(spy.speed, 0.55, 0.0001);
}

- (void)testFooterActionsForwardToDelegate {
    RubikStepPanelDelegateSpy* spy = [[RubikStepPanelDelegateSpy alloc] init];
    RubikStepPanelController* panel = [self newPanelWithDelegate:spy];
    NSView* root = panel.view;

    [ButtonWithIdentifier(root, @"copyStateButton") performClick:nil];
    [ButtonWithIdentifier(root, @"solveButton") performClick:nil];
    [ButtonWithIdentifier(root, @"scrambleButton") performClick:nil];
    [ButtonWithIdentifier(root, @"cameraButton") performClick:nil];
    [ButtonWithIdentifier(root, @"pdfButton") performClick:nil];

    XCTAssertEqual(spy.copyCount, 1);
    XCTAssertEqual(spy.solveCount, 1);
    XCTAssertEqual(spy.scrambleCount, 1);
    XCTAssertEqual(spy.cameraCount, 1);
    XCTAssertEqual(spy.pdfCount, 1);

    // Pressing solve puts the sidebar into a busy state.
    XCTAssertFalse(ButtonWithIdentifier(root, @"solveButton").enabled);
    XCTAssertEqualObjects(LabelWithIdentifier(root, @"currentMoveDescription").stringValue,
                          @"Solving…");
}

@end
