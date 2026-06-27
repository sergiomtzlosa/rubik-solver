//
//  RubikRandomGeneratorSheetController.mm
//  RubikSolver - Random Cube Generator & Metal Solver Sheet
//

#import "RubikRandomGeneratorSheetController.h"

@implementation RubikRandomGeneratorSheetController {
    NSWindow* _sheetWindow;
    NSWindow* _parentWindow;
    RubikRandomGeneratorCompletion _completion;

    NSSegmentedControl* _difficultySegment;
    NSSlider* _movesSlider;
    NSTextField* _movesLabel;
    NSTextField* _algorithmView;

    RubikCube _currentScrambledCube;
    std::vector<int> _currentScrambleMoves;
    int _currentMoveCount;
}

+ (instancetype)sharedController {
    static RubikRandomGeneratorSheetController* sInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sInstance = [[RubikRandomGeneratorSheetController alloc] init];
    });
    return sInstance;
}

- (void)showGeneratorSheetForWindow:(NSWindow*)parentWindow
                         completion:(RubikRandomGeneratorCompletion)completion
{
    _parentWindow = parentWindow;
    _completion = completion;
    _currentMoveCount = 22;

    NSRect frame = NSMakeRect(0, 0, 560, 380);
    _sheetWindow = [[NSWindow alloc] initWithContentRect:frame
                                               styleMask:NSWindowStyleMaskTitled
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
    _sheetWindow.title = @"Generate Random Rubik's Cube";
    _sheetWindow.backgroundColor = [NSColor colorWithCalibratedRed:0.11
                                                             green:0.12
                                                              blue:0.15
                                                             alpha:1.0];

    NSView* content = _sheetWindow.contentView;
    content.wantsLayer = YES;
    content.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.11
                                                              green:0.12
                                                               blue:0.15
                                                              alpha:1.0].CGColor;

    // Title
    NSTextField* titleLabel = [NSTextField labelWithString:@"🎲 Generate Random Rubik's Cube"];
    titleLabel.font = [NSFont systemFontOfSize:18 weight:NSFontWeightBold];
    titleLabel.textColor = [NSColor whiteColor];
    titleLabel.frame = NSMakeRect(24, 335, 510, 26);
    [content addSubview:titleLabel];

    NSTextField* subLabel = [NSTextField labelWithString:@"Configure scramble complexity to solve with the exact two-phase CPU solver."];
    subLabel.font = [NSFont systemFontOfSize:12];
    subLabel.textColor = [NSColor whiteColor];
    subLabel.frame = NSMakeRect(24, 310, 510, 20);
    [content addSubview:subLabel];

    // Difficulty Presets
    NSTextField* diffHeader = [NSTextField labelWithString:@"Difficulty Preset:"];
    diffHeader.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    diffHeader.textColor = [NSColor whiteColor];
    diffHeader.frame = NSMakeRect(24, 274, 200, 18);
    [content addSubview:diffHeader];

    _difficultySegment = [NSSegmentedControl segmentedControlWithLabels:@[@"🟢 Easy (10)", @"🟡 Medium (16)", @"🔴 Standard (22)", @"🏆 Competition (25)"]
                                                           trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                 target:self
                                                                 action:@selector(onDifficultyChanged:)];
    _difficultySegment.frame = NSMakeRect(24, 240, 512, 28);
    _difficultySegment.selectedSegment = 2; // Standard (22)
    
    // Force white text for dark background
    if (@available(macOS 10.14, *)) {
        _difficultySegment.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    }
    
    [content addSubview:_difficultySegment];

    // Move Count Slider
    _movesLabel = [NSTextField labelWithString:@"Scramble Depth: 22 moves"];
    _movesLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    _movesLabel.textColor = [NSColor whiteColor];
    _movesLabel.frame = NSMakeRect(24, 200, 250, 18);
    [content addSubview:_movesLabel];

    _movesSlider = [NSSlider sliderWithValue:22 minValue:3 maxValue:25 target:self action:@selector(onSliderChanged:)];
    _movesSlider.numberOfTickMarks = 23;
    _movesSlider.allowsTickMarkValuesOnly = YES;
    _movesSlider.frame = NSMakeRect(24, 172, 512, 24);
    [content addSubview:_movesSlider];

    // Scramble Algorithm Preview Card
    NSTextField* algoHeader = [NSTextField labelWithString:@"Generated Scramble Sequence:"];
    algoHeader.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    algoHeader.textColor = [NSColor whiteColor];
    algoHeader.frame = NSMakeRect(24, 138, 250, 18);
    [content addSubview:algoHeader];

    NSButton* btnReroll = [NSButton buttonWithTitle:@"🎲 Re-roll" target:self action:@selector(onRerollClicked:)];
    btnReroll.bezelStyle = NSBezelStyleInline;
    btnReroll.frame = NSMakeRect(460, 135, 76, 22);
    NSMutableAttributedString* attrReroll = [[NSMutableAttributedString alloc] initWithString:@"🎲 Re-roll"];
    [attrReroll addAttribute:NSForegroundColorAttributeName value:[NSColor whiteColor] range:NSMakeRange(0, attrReroll.length)];
    btnReroll.attributedTitle = attrReroll;
    [content addSubview:btnReroll];

    NSView* cardView = [[NSView alloc] initWithFrame:NSMakeRect(24, 76, 512, 54)];
    cardView.wantsLayer = YES;
    cardView.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.07 green:0.08 blue:0.10 alpha:1.0].CGColor;
    cardView.layer.cornerRadius = 8;
    cardView.layer.borderWidth = 1.0;
    cardView.layer.borderColor = [NSColor colorWithCalibratedWhite:0.22 alpha:1.0].CGColor;
    [content addSubview:cardView];

    _algorithmView = [NSTextField labelWithString:@""];
    _algorithmView.font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightMedium];
    _algorithmView.textColor = [NSColor colorWithCalibratedRed:0.35 green:0.85 blue:0.65 alpha:1.0];
    _algorithmView.frame = NSMakeRect(12, 12, 488, 30);
    [cardView addSubview:_algorithmView];

    // Action Buttons
    NSButton* btnCancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(onCancelClicked:)];
    btnCancel.bezelStyle = NSBezelStyleRounded;
    btnCancel.frame = NSMakeRect(24, 18, 90, 32);
    NSMutableAttributedString* attrCancel = [[NSMutableAttributedString alloc] initWithString:@"Cancel"];
    [attrCancel addAttribute:NSForegroundColorAttributeName value:[NSColor whiteColor] range:NSMakeRange(0, attrCancel.length)];
    btnCancel.attributedTitle = attrCancel;
    [content addSubview:btnCancel];

    NSButton* btnApplyOnly = [NSButton buttonWithTitle:@"Scramble Only" target:self action:@selector(onApplyOnlyClicked:)];
    btnApplyOnly.bezelStyle = NSBezelStyleRounded;
    btnApplyOnly.frame = NSMakeRect(220, 18, 130, 32);
    NSMutableAttributedString* attrApplyOnly = [[NSMutableAttributedString alloc] initWithString:@"Scramble Only"];
    [attrApplyOnly addAttribute:NSForegroundColorAttributeName value:[NSColor whiteColor] range:NSMakeRange(0, attrApplyOnly.length)];
    btnApplyOnly.attributedTitle = attrApplyOnly;
    [content addSubview:btnApplyOnly];

    NSButton* btnApplySolve = [NSButton buttonWithTitle:@"⚡ Scramble & Solve" target:self action:@selector(onApplyAndSolveClicked:)];
    btnApplySolve.bezelStyle = NSBezelStyleRounded;
    btnApplySolve.keyEquivalent = @"\r";
    btnApplySolve.frame = NSMakeRect(358, 18, 180, 32);
    NSMutableAttributedString* attrApplySolve = [[NSMutableAttributedString alloc] initWithString:@"⚡ Scramble & Solve"];
    [attrApplySolve addAttribute:NSForegroundColorAttributeName value:[NSColor whiteColor] range:NSMakeRange(0, attrApplySolve.length)];
    btnApplySolve.attributedTitle = attrApplySolve;
    [content addSubview:btnApplySolve];

    // Generate initial algorithm
    [self generateScrambleWithMoves:_currentMoveCount];

    [_parentWindow beginSheet:_sheetWindow completionHandler:nil];
}

#pragma mark - Scramble Generation

- (void)generateScrambleWithMoves:(int)numMoves {
    _currentMoveCount = numMoves;
    _currentScrambledCube.reset();
    _currentScrambleMoves = _currentScrambledCube.scramble(numMoves);

    std::string moveStr = RubikCube::movesToString(_currentScrambleMoves);
    _algorithmView.stringValue = [NSString stringWithUTF8String:moveStr.c_str()];
    _movesLabel.stringValue = [NSString stringWithFormat:@"Scramble Depth: %d moves", numMoves];
    _movesSlider.integerValue = numMoves;
}

- (void)onDifficultyChanged:(NSSegmentedControl*)sender {
    switch (sender.selectedSegment) {
        case 0: [self generateScrambleWithMoves:10]; break;
        case 1: [self generateScrambleWithMoves:16]; break;
        case 2: [self generateScrambleWithMoves:22]; break;
        case 3: [self generateScrambleWithMoves:25]; break;
    }
}

- (void)onSliderChanged:(NSSlider*)slider {
    int moves = (int)slider.integerValue;
    _difficultySegment.selectedSegment = -1; // Deselect preset
    if (moves == 10) _difficultySegment.selectedSegment = 0;
    else if (moves == 16) _difficultySegment.selectedSegment = 1;
    else if (moves == 22) _difficultySegment.selectedSegment = 2;
    else if (moves == 25) _difficultySegment.selectedSegment = 3;

    [self generateScrambleWithMoves:moves];
}

- (void)onRerollClicked:(id)sender {
    [self generateScrambleWithMoves:_currentMoveCount];
}

#pragma mark - Actions

- (void)onCancelClicked:(id)sender {
    [_parentWindow endSheet:_sheetWindow];
    _sheetWindow = nil;
}

- (void)onApplyOnlyClicked:(id)sender {
    RubikCube cube = _currentScrambledCube;
    std::vector<int> moves = _currentScrambleMoves;
    RubikRandomGeneratorCompletion comp = _completion;

    [_parentWindow endSheet:_sheetWindow];
    _sheetWindow = nil;

    if (comp) {
        comp(cube, moves, NO);
    }
}

- (void)onApplyAndSolveClicked:(id)sender {
    RubikCube cube = _currentScrambledCube;
    std::vector<int> moves = _currentScrambleMoves;
    RubikRandomGeneratorCompletion comp = _completion;

    [_parentWindow endSheet:_sheetWindow];
    _sheetWindow = nil;

    if (comp) {
        comp(cube, moves, YES);
    }
}

@end
