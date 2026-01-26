//
//  LaunchUITests.mm
//  RubikSolverUITests - End-to-End macOS Interface Coverage
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

@interface LaunchUITests : XCTestCase
@property (nonatomic, strong) XCUIApplication* app;
@end

@implementation LaunchUITests

- (void)setUp {
    self.continueAfterFailure = NO;
    [super setUp];
}

- (void)tearDown {
    [self.app terminate];
    self.app = nil;
    [super tearDown];
}

#pragma mark - Helpers

- (XCUIApplication*)launchAppWithEnvironment:(NSDictionary<NSString*, NSString*>*)environment {
    XCUIApplication* app = [[XCUIApplication alloc] init];
    // Force the deterministic exact engine and reset any persisted selection.
    app.launchArguments = @[ @"-RubikSolverEngineKind", @"0" ];
    NSMutableDictionary<NSString*, NSString*>* merged = [@{
        // Stop the continuous auto-play animation so accessibility snapshots refresh promptly.
        @"RUBIK_DISABLE_AUTOPLAY" : @"1",
    } mutableCopy];
    [merged addEntriesFromDictionary:environment];
    app.launchEnvironment = merged;
    [app launch];
    XCTAssertTrue([app.windows.firstMatch waitForExistenceWithTimeout:20.0],
                  @"the main window did not appear");
    self.app = app;
    return app;
}

- (XCUIElement*)elementWithIdentifier:(NSString*)identifier inApp:(XCUIApplication*)app {
    return [[app descendantsMatchingType:XCUIElementTypeAny] objectForKeyedSubscript:identifier];
}

- (BOOL)element:(XCUIElement*)element containsText:(NSString*)text {
    return [[self textForElement:element] containsString:text];
}

- (NSString*)textForElement:(XCUIElement*)element {
    NSString* label = element.label ?: @"";
    id value = element.value;
    NSString* valueString = [value isKindOfClass:[NSString class]] ? (NSString*)value : @"";
    return [label stringByAppendingString:valueString];
}

- (BOOL)waitForText:(NSString*)text inElement:(XCUIElement*)element timeout:(NSTimeInterval)timeout {
    NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while ([deadline timeIntervalSinceNow] > 0.0) {
        if ([self element:element containsText:text]) return YES;
        [NSThread sleepForTimeInterval:0.15];
    }
    return [self element:element containsText:text];
}

- (BOOL)waitForSolutionInApp:(XCUIApplication*)app timeout:(NSTimeInterval)timeout {
    // The status HUD reflects the solve result reliably, while some sidebar
    // labels can keep serving a cached accessibility value after a background
    // solve completes. Poll the HUD instead of the move counter.
    XCUIElement* status = [self elementWithIdentifier:@"statusLabel" inApp:app];
    NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while ([deadline timeIntervalSinceNow] > 0.0) {
        NSString* text = [self textForElement:status];
        if ([text containsString:@"Solved in"] || [text containsString:@"Auto-playing"]) return YES;
        [NSThread sleepForTimeInterval:0.2];
    }
    return NO;
}

#pragma mark - Tests

- (void)testAppLaunches {
    XCUIApplication* app = [self launchAppWithEnvironment:nil];
    XCTAssertTrue(app.windows.firstMatch.exists);
    XCTAssertTrue([app.staticTexts[@"stepTitle"] waitForExistenceWithTimeout:5.0]);
}

- (void)testDashboardAndToolbarExposeCoreControls {
    XCUIApplication* app = [self launchAppWithEnvironment:nil];

    NSArray<NSString*>* sidebarIdentifiers = @[
        @"stepTitle", @"stepStats", @"stepProgress", @"currentMoveLabel",
        @"currentMoveDescription", @"stepCounter", @"firstButton", @"prevButton",
        @"playButton", @"nextButton", @"speedControl", @"movesTable",
        @"movesCountLabel", @"copyStateButton", @"solveButton", @"scrambleButton",
        @"cameraButton", @"pdfButton", @"engineBadge",
    ];
    for (NSString* identifier in sidebarIdentifiers) {
        XCTAssertTrue([[self elementWithIdentifier:identifier inApp:app]
                          waitForExistenceWithTimeout:5.0],
                      @"missing sidebar control %@", identifier);
    }

    NSArray<NSString*>* toolbarIdentifiers = @[
        @"toolbarRandomButton", @"toolbarSolveButton", @"toolbarCameraButton",
        @"toolbarPhotosButton", @"toolbarCopyButton", @"toolbarResetButton",
        @"toolbarHelpButton", @"enginePopup",
    ];
    for (NSString* identifier in toolbarIdentifiers) {
        XCTAssertTrue([[self elementWithIdentifier:identifier inApp:app]
                          waitForExistenceWithTimeout:5.0],
                      @"missing toolbar control %@", identifier);
    }

    XCTAssertTrue([[self elementWithIdentifier:@"statusLabel" inApp:app]
        waitForExistenceWithTimeout:5.0]);
    XCTAssertTrue([[self elementWithIdentifier:@"copyStateStatusButton" inApp:app]
        waitForExistenceWithTimeout:5.0]);
    XCTAssertTrue([[self elementWithIdentifier:@"cube3DView" inApp:app]
        waitForExistenceWithTimeout:5.0]);
}

- (void)testScrambleThenSolveProducesAVerifiedSolution {
    XCUIApplication* app = [self launchAppWithEnvironment:nil];
    XCUIElement* status = [self elementWithIdentifier:@"statusLabel" inApp:app];
    XCTAssertTrue([status waitForExistenceWithTimeout:5.0]);

    XCUIElement* scramble = [self elementWithIdentifier:@"scrambleButton" inApp:app];
    [scramble click];
    XCTAssertTrue([self waitForText:@"scramble" inElement:status timeout:10.0],
                  @"scramble did not run: %@", status.label);

    XCUIElement* solve = [self elementWithIdentifier:@"solveButton" inApp:app];
    [solve click];

    XCTAssertTrue([self waitForSolutionInApp:app timeout:90.0],
                  @"solver did not produce a solution: %@", [self textForElement:status]);
    XCTAssertTrue([[self textForElement:status] containsString:@"verified"]);

    XCUIElement* currentMove = [self elementWithIdentifier:@"currentMoveLabel" inApp:app];
    XCTAssertTrue(currentMove.exists);
    XCTAssertGreaterThan([self textForElement:currentMove].length, 0u);

    XCTAssertTrue([self elementWithIdentifier:@"playButton" inApp:app].exists);
    XCTAssertTrue([self elementWithIdentifier:@"nextButton" inApp:app].exists);
}

- (void)testToolbarRandomOnlyScramblesWithoutSolving {
    XCUIApplication* app = [self launchAppWithEnvironment:nil];
    XCUIElement* status = [self elementWithIdentifier:@"statusLabel" inApp:app];

    XCUIElement* random = [self elementWithIdentifier:@"toolbarRandomButton" inApp:app];
    XCTAssertTrue([random waitForExistenceWithTimeout:5.0]);
    [random click];

    XCTAssertTrue([self waitForText:@"Random 22-move scramble" inElement:status timeout:10.0],
                  @"toolbar Random did not scramble the cube: %@", [self textForElement:status]);

    XCUIElement* description = [self elementWithIdentifier:@"currentMoveDescription" inApp:app];
    XCTAssertTrue([self waitForText:@"Scrambled" inElement:description timeout:5.0],
                  @"the step panel did not show the scrambled state: %@",
                  [self textForElement:description]);

    // A solve would replace the HUD text within a few seconds. Watch it for a
    // short window to prove that Random only scrambles the cube.
    NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:3.0];
    while ([deadline timeIntervalSinceNow] > 0.0) {
        NSString* text = [self textForElement:status];
        XCTAssertFalse([text containsString:@"Solved in"],
                       @"toolbar Random auto-solved the cube: %@", text);
        XCTAssertFalse([text containsString:@"Solving"],
                       @"toolbar Random started the solver: %@", text);
        [NSThread sleepForTimeInterval:0.2];
    }
    XCTAssertTrue([[self textForElement:status] containsString:@"Random 22-move scramble"],
                  @"toolbar Random status changed unexpectedly: %@", [self textForElement:status]);
}

- (void)testToolbarResetRestoresTheSolvedState {
    XCUIApplication* app = [self launchAppWithEnvironment:nil];
    XCUIElement* status = [self elementWithIdentifier:@"statusLabel" inApp:app];

    [[self elementWithIdentifier:@"toolbarRandomButton" inApp:app] click];
    // The toolbar scramble leaves a scrambled cube; reset should restore the
    // solved state without any solve having been started.
    [NSThread sleepForTimeInterval:1.0];

    [[self elementWithIdentifier:@"toolbarResetButton" inApp:app] click];
    XCTAssertTrue([self waitForText:@"Cube reset" inElement:status timeout:20.0],
                  @"reset did not run: %@", [self textForElement:status]);
    XCTAssertTrue([self waitForText:@"Solved cube ready"
                           inElement:[self elementWithIdentifier:@"currentMoveDescription" inApp:app]
                             timeout:5.0]);
}

- (void)testCopyCubeStateForOpenCodeUsesTheFaceletPasteboardType {
    XCUIApplication* app = [self launchAppWithEnvironment:nil];
    XCUIElement* status = [self elementWithIdentifier:@"statusLabel" inApp:app];

    [[self elementWithIdentifier:@"scrambleButton" inApp:app] click];
    XCTAssertTrue([self waitForText:@"scramble" inElement:status timeout:10.0]);

    [[self elementWithIdentifier:@"toolbarCopyButton" inApp:app] click];
    XCTAssertTrue([self waitForText:@"Copied cube state" inElement:status timeout:10.0],
                  @"copy action did not report success: %@", status.label);

    NSPasteboard* pasteboard = [NSPasteboard generalPasteboard];
    NSString* facelets = [pasteboard stringForType:@"com.rubik.facelets"];
    XCTAssertEqual(facelets.length, 54u, @"unexpected facelet string: %@", facelets);
    NSString* allowed = @"URFDLB";
    for (NSUInteger i = 0; i < facelets.length; ++i) {
        unichar c = [facelets characterAtIndex:i];
        NSString* faceChar = [NSString stringWithFormat:@"%C", c];
        XCTAssertTrue([allowed containsString:faceChar],
                      @"facelet %lu (%C) is not a valid face letter", (unsigned long)i, c);
    }

    NSString* prompt = [pasteboard stringForType:NSPasteboardTypeString];
    XCTAssertTrue([prompt containsString:facelets]);
    XCTAssertTrue([prompt containsString:@"rubik_solve"]);
}

- (void)testEngineSelectorUpdatesTheSidebar {
    XCUIApplication* app = [self launchAppWithEnvironment:nil];
    XCUIElement* popup = [self elementWithIdentifier:@"enginePopup" inApp:app];
    XCTAssertTrue([popup waitForExistenceWithTimeout:5.0]);

    [popup click];
    XCUIElement* neural = app.menuItems[@"Neural · Core ML GPU"];
    XCTAssertTrue([neural waitForExistenceWithTimeout:5.0]);
    [neural click];

    XCUIElement* badge = [self elementWithIdentifier:@"engineBadge" inApp:app];
    XCTAssertTrue([self waitForText:@"Neural" inElement:badge timeout:5.0],
                  @"engine badge did not update: %@ / %@", badge.label, badge.value);

    [popup click];
    XCUIElement* exact = app.menuItems[@"Exact · CPU"];
    XCTAssertTrue([exact waitForExistenceWithTimeout:5.0]);
    [exact click];
    XCTAssertTrue([self waitForText:@"Exact" inElement:badge timeout:5.0]);
}

- (void)testCameraScannerOpensAndCloses {
    XCUIApplication* app = [self launchAppWithEnvironment:@{ @"RUBIK_DISABLE_CAMERA": @"1" }];

    XCUIElement* capture = [self elementWithIdentifier:@"cameraCaptureButton" inApp:app];
    XCTAssertFalse(capture.exists);

    [[self elementWithIdentifier:@"toolbarCameraButton" inApp:app] click];
    XCTAssertTrue([capture waitForExistenceWithTimeout:10.0]);
    XCTAssertTrue([[self elementWithIdentifier:@"cameraCloseButton" inApp:app]
        waitForExistenceWithTimeout:5.0]);
    XCTAssertTrue([[self elementWithIdentifier:@"cameraInstructionLabel" inApp:app]
        waitForExistenceWithTimeout:5.0]);

    [[self elementWithIdentifier:@"cameraCloseButton" inApp:app] click];
    XCTAssertTrue([capture waitForNonExistenceWithTimeout:5.0]);
}

- (void)testPhotoUploadUsesBundledSamplesAndSolvesTheCube {
    XCUIApplication* app = [self launchAppWithEnvironment:nil];
    XCUIElement* status = [self elementWithIdentifier:@"statusLabel" inApp:app];

    XCUIElement* photos = [self elementWithIdentifier:@"toolbarPhotosButton" inApp:app];
    XCTAssertTrue([photos waitForExistenceWithTimeout:5.0],
                  @"the six-face photo button is missing from the toolbar");
    [photos click];

    XCUIElement* loadSamples = [self elementWithIdentifier:@"loadSamplePhotosButton" inApp:app];
    XCTAssertTrue([loadSamples waitForExistenceWithTimeout:10.0],
                  @"the photo upload sheet did not open");
    [loadSamples click];

    XCUIElement* progress = [self elementWithIdentifier:@"uploadProgressLabel" inApp:app];
    XCTAssertTrue([self waitForText:@"6 / 6" inElement:progress timeout:20.0],
                  @"the bundled sample faces did not load: %@", [self textForElement:progress]);

    XCUIElement* validation = [self elementWithIdentifier:@"uploadValidationLabel" inApp:app];
    XCTAssertTrue([self waitForText:@"All 6 faces recognized" inElement:validation timeout:10.0],
                  @"the recognized sample faces were not valid: %@", [self textForElement:validation]);

    XCUIElement* applyAndSolve = [self elementWithIdentifier:@"applyAndSolveButton" inApp:app];
    XCTAssertTrue([applyAndSolve waitForExistenceWithTimeout:5.0]);
    [applyAndSolve click];

    XCTAssertTrue([self waitForSolutionInApp:app timeout:90.0],
                  @"photo upload did not lead to a solution: %@", [self textForElement:status]);
    XCTAssertTrue([[self textForElement:status] containsString:@"verified"]);
}

- (void)testHelpWindowOpensFromTheToolbar {
    XCUIApplication* app = [self launchAppWithEnvironment:nil];

    [[self elementWithIdentifier:@"toolbarHelpButton" inApp:app] click];
    XCUIElement* help = app.windows[@"Rubik's Solver - User Guide & Help"];
    XCTAssertTrue([help waitForExistenceWithTimeout:10.0]);
    [help.buttons[XCUIIdentifierCloseWindow] click];
    XCTAssertTrue([help waitForNonExistenceWithTimeout:5.0]);
}

@end
