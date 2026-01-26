//
//  RubikStepPanelController.mm
//  RubikSolver - Step-by-Step Solving Dashboard
//
//  A slim, native "Studio Dark" sidebar: current move spotlight, transport
//  controls, the full solution list, and the primary actions. All controls
//  carry accessibility identifiers so the UI test suite can drive them.
//

#import "RubikStepPanelController.h"
#import "RubikTheme.h"
#import <QuartzCore/QuartzCore.h>

#if __has_include("../RubikCore/RubikCube.h")
#include "../RubikCore/RubikCube.h"
#else
#include "RubikCube.h"
#endif

#include <algorithm>

#pragma mark - Engine badge

/// A small capsule like `NEURAL` with a status dot. Green means Core ML
/// placement was verified on the GPU; amber means it was not verified.
@interface RubikEngineBadgeView : NSView
@property (nonatomic, strong) NSTextField* label;
@property (nonatomic, strong) NSView* dot;
- (void)setTitle:(NSString*)title verified:(BOOL)verified active:(BOOL)active;
@end

@implementation RubikEngineBadgeView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 10.0;
        self.layer.backgroundColor = [RubikTheme accentSoft].CGColor;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [[RubikTheme accent] colorWithAlphaComponent:0.28].CGColor;
        [self setAccessibilityElement:YES];
        self.accessibilityRole = NSAccessibilityStaticTextRole;
        self.accessibilityLabel = @"Solver engine";

        _dot = [[NSView alloc] initWithFrame:NSZeroRect];
        _dot.wantsLayer = YES;
        _dot.layer.cornerRadius = 3.0;
        _dot.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_dot];

        _label = [RubikTheme labelWithText:@"EXACT"
                                     font:[NSFont systemFontOfSize:9 weight:NSFontWeightBold]
                                    color:[RubikTheme textSecondary]];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_label];

        [NSLayoutConstraint activateConstraints:@[
            [_dot.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
            [_dot.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_dot.widthAnchor constraintEqualToConstant:6],
            [_dot.heightAnchor constraintEqualToConstant:6],
            [_label.leadingAnchor constraintEqualToAnchor:_dot.trailingAnchor constant:5],
            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.heightAnchor constraintEqualToConstant:21],
        ]];
    }
    return self;
}

- (void)setTitle:(NSString*)title verified:(BOOL)verified active:(BOOL)active {
    self.label.stringValue = title ?: @"SOLVER";
    self.accessibilityValue = title ?: @"SOLVER";
    NSColor* dotColor = !active
        ? [RubikTheme textTertiary]
        : (verified ? [RubikTheme success] : [RubikTheme warning]);
    self.dot.layer.backgroundColor = dotColor.CGColor;
    self.layer.borderColor = [(active ? dotColor : [RubikTheme separator])
        colorWithAlphaComponent:0.35].CGColor;
    self.layer.backgroundColor = [(active ? [RubikTheme accentSoft]
                                         : [[NSColor whiteColor] colorWithAlphaComponent:0.04])
        CGColor];
}

@end

#pragma mark - Step panel

@interface RubikStepPanelController ()
- (void)goToNextStep;
- (void)goToPreviousStep;
- (void)updateMovesCount:(NSUInteger)count;
@end

@implementation RubikStepPanelController {
  std::vector<int> _solutionMoves;
  NSInteger _currentStepIndex;
  BOOL _isAutoPlaying;
  NSTimeInterval _stepDuration;
  NSString* _emptyStateText;
  NSString* _engineDescription;
  double _solveTimeMs;
  BOOL _engineGPUVerified;
  BOOL _updatingSelection;

  NSTextField* _statsLabel;
  RubikProgressView* _progressBar;
  RubikEngineBadgeView* _engineBadge;

  NSView* _spotlightCard;
  NSTextField* _stepCaption;
  NSTextField* _stepCounter;
  NSTextField* _currentMoveLabel;
  NSTextField* _currentDescLabel;

  NSButton* _prevButton;
  NSButton* _playButton;
  NSButton* _nextButton;
  NSButton* _firstButton;
  NSSegmentedControl* _speedControl;

  NSScrollView* _tableScrollView;
  NSTableView* _tableView;
  NSTextField* _movesCountLabel;

  NSButton* _pdfButton;
  NSButton* _cameraButton;
  NSButton* _solveButton;
  NSButton* _scrambleButton;
  NSButton* _copyButton;

  CAGradientLayer* _backgroundLayer;
}

- (instancetype)initWithNibName:(NSNibName)nibNameOrNil
                         bundle:(NSBundle*)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if (self) {
    _currentStepIndex = 0;
    _isAutoPlaying = NO;
    _stepDuration = 0.30;
    _emptyStateText = @"Scramble or scan a cube, then solve it.";
    _engineDescription = @"Exact · ckociemba (CPU)";
    _engineGPUVerified = NO;
  }
  return self;
}

- (nullable instancetype)initWithCoder:(NSCoder*)coder {
  self = [super initWithCoder:coder];
  if (self) {
    _currentStepIndex = 0;
    _isAutoPlaying = NO;
    _stepDuration = 0.30;
    _emptyStateText = @"Scramble or scan a cube, then solve it.";
    _engineDescription = @"Exact · ckociemba (CPU)";
    _engineGPUVerified = NO;
  }
  return self;
}

- (instancetype)init {
  return [self initWithNibName:nil bundle:nil];
}

- (const std::vector<int>&)solutionMoves {
  return _solutionMoves;
}

- (NSInteger)currentStepIndex {
  return _currentStepIndex;
}

- (BOOL)isAutoPlaying {
  return _isAutoPlaying;
}

#pragma mark - View

- (void)loadView {
  NSView* root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 380, 760)];
  root.wantsLayer = YES;
  root.layer.backgroundColor = [RubikTheme sidebar].CGColor;
  root.accessibilityIdentifier = @"stepPanel";
  root.accessibilityLabel = @"Solving dashboard";
  if (@available(macOS 10.14, *)) {
    root.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
  }

  CAGradientLayer* gradient = [CAGradientLayer layer];
  gradient.colors = @[
    (id)[RubikTheme sidebar].CGColor,
    (id)[[RubikTheme background] colorWithAlphaComponent:0.94].CGColor,
  ];
  gradient.startPoint = CGPointMake(0.5, 1.0);
  gradient.endPoint = CGPointMake(0.5, 0.0);
  [root.layer addSublayer:gradient];
  _backgroundLayer = gradient;

  self.view = root;
  [self buildInterface];
  [self updateEngineBadge];
  [self updateStats];
}

- (void)viewDidLayout {
  [super viewDidLayout];
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  _backgroundLayer.frame = self.view.bounds;
  [CATransaction commit];
}

- (NSTextField*)labelWithText:(NSString*)text
                         font:(NSFont*)font
                        color:(NSColor*)color {
  return [RubikTheme labelWithText:text font:font color:color];
}

- (NSButton*)symbolButton:(NSString*)symbol
                  tooltip:(NSString*)tooltip
               identifier:(NSString*)identifier
                   action:(SEL)action {
  NSButton* button = [NSButton buttonWithImage:[RubikTheme symbolNamed:symbol
                                                                 size:12
                                                               weight:NSFontWeightSemibold]
                                        target:self
                                        action:action];
  button.bezelStyle = NSBezelStyleRounded;
  button.bordered = NO;
  button.wantsLayer = YES;
  button.layer.cornerRadius = 8.0;
  button.layer.backgroundColor = [[NSColor whiteColor] colorWithAlphaComponent:0.06].CGColor;
  button.layer.borderWidth = 1.0;
  button.layer.borderColor = [[NSColor whiteColor] colorWithAlphaComponent:0.06].CGColor;
  button.contentTintColor = [RubikTheme textPrimary];
  button.toolTip = tooltip;
  button.accessibilityLabel = tooltip;
  button.accessibilityIdentifier = identifier;
  return button;
}

- (NSButton*)actionButtonWithTitle:(NSString*)title
                            symbol:(NSString*)symbol
                        identifier:(NSString*)identifier
                         prominent:(BOOL)prominent
                            action:(SEL)action {
  NSButton* button = prominent
      ? [RubikTheme filledButton:title symbol:symbol target:self action:action]
      : [RubikTheme softButton:title symbol:symbol target:self action:action];
  button.accessibilityIdentifier = identifier;
  button.toolTip = title;
  return button;
}

- (void)buildInterface {
  NSView* root = self.view;
  const CGFloat side = 18.0;

  // Brand mark.
  NSView* logo = [[NSView alloc] initWithFrame:NSZeroRect];
  logo.wantsLayer = YES;
  logo.layer.cornerRadius = 10.0;
  logo.layer.backgroundColor = [RubikTheme accentSoft].CGColor;
  logo.layer.borderWidth = 1.0;
  logo.layer.borderColor = [[RubikTheme accent] colorWithAlphaComponent:0.35].CGColor;
  logo.translatesAutoresizingMaskIntoConstraints = NO;
  [root addSubview:logo];

  NSImageView* logoImage = [[NSImageView alloc] initWithFrame:NSZeroRect];
  logoImage.image = [RubikTheme symbolNamed:@"cube.transparent.fill" size:18 weight:NSFontWeightSemibold];
  logoImage.contentTintColor = [RubikTheme accent];
  logoImage.translatesAutoresizingMaskIntoConstraints = NO;
  [logo addSubview:logoImage];

  NSTextField* title = [self labelWithText:@"RubikSolver"
                                     font:[NSFont systemFontOfSize:15.5 weight:NSFontWeightBold]
                                    color:[RubikTheme textPrimary]];
  title.translatesAutoresizingMaskIntoConstraints = NO;
  title.accessibilityIdentifier = @"stepTitle";
  [root addSubview:title];

  NSTextField* subtitle = [self labelWithText:@"STUDIO DARK · VERIFIED SOLVES"
                                        font:[NSFont systemFontOfSize:8.5 weight:NSFontWeightSemibold]
                                       color:[RubikTheme textTertiary]];
  subtitle.translatesAutoresizingMaskIntoConstraints = NO;
  [root addSubview:subtitle];

  _engineBadge = [[RubikEngineBadgeView alloc] initWithFrame:NSZeroRect];
  _engineBadge.translatesAutoresizingMaskIntoConstraints = NO;
  _engineBadge.accessibilityIdentifier = @"engineBadge";
  [root addSubview:_engineBadge];
  [_engineBadge setTitle:@"EXACT" verified:NO active:NO];

  // Performance / engine line.
  _statsLabel = [self labelWithText:@"Exact · ckociemba (CPU)"
                               font:[NSFont systemFontOfSize:11 weight:NSFontWeightMedium]
                              color:[RubikTheme textSecondary]];
  _statsLabel.translatesAutoresizingMaskIntoConstraints = NO;
  _statsLabel.accessibilityIdentifier = @"stepStats";
  _statsLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
  [root addSubview:_statsLabel];

  _progressBar = [[RubikProgressView alloc] initWithFrame:NSZeroRect];
  _progressBar.translatesAutoresizingMaskIntoConstraints = NO;
  _progressBar.accessibilityIdentifier = @"stepProgress";
  [root addSubview:_progressBar];

  // Current-step spotlight.
  _spotlightCard = [[NSView alloc] initWithFrame:NSZeroRect];
  [RubikTheme applyCardStyle:_spotlightCard elevated:YES];
  _spotlightCard.translatesAutoresizingMaskIntoConstraints = NO;
  _spotlightCard.accessibilityIdentifier = @"currentStepCard";
  [root addSubview:_spotlightCard];

  _stepCaption = [self labelWithText:@"CURRENT STEP"
                                font:[NSFont systemFontOfSize:8.5 weight:NSFontWeightBold]
                               color:[RubikTheme textTertiary]];
  _stepCaption.translatesAutoresizingMaskIntoConstraints = NO;
  [_spotlightCard addSubview:_stepCaption];

  _stepCounter = [self labelWithText:@"—"
                                font:[RubikTheme monoFontOfSize:10 weight:NSFontWeightMedium]
                               color:[RubikTheme textTertiary]];
  _stepCounter.alignment = NSTextAlignmentRight;
  _stepCounter.translatesAutoresizingMaskIntoConstraints = NO;
  _stepCounter.accessibilityIdentifier = @"stepCounter";
  [_spotlightCard addSubview:_stepCounter];

  _currentMoveLabel = [self labelWithText:@"—"
                                     font:[RubikTheme monoFontOfSize:38 weight:NSFontWeightHeavy]
                                    color:[RubikTheme textPrimary]];
  _currentMoveLabel.translatesAutoresizingMaskIntoConstraints = NO;
  _currentMoveLabel.accessibilityIdentifier = @"currentMoveLabel";
  [_spotlightCard addSubview:_currentMoveLabel];

  _currentDescLabel = [self labelWithText:_emptyStateText
                                     font:[NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium]
                                    color:[RubikTheme textSecondary]];
  _currentDescLabel.translatesAutoresizingMaskIntoConstraints = NO;
  _currentDescLabel.accessibilityIdentifier = @"currentMoveDescription";
  _currentDescLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  [_spotlightCard addSubview:_currentDescLabel];

  // Transport controls.
  _firstButton = [self symbolButton:@"backward.end.fill"
                            tooltip:@"Back to the first step"
                         identifier:@"firstButton"
                             action:@selector(onFirstClicked:)];
  _prevButton = [self symbolButton:@"backward.frame.fill"
                           tooltip:@"Previous step"
                        identifier:@"prevButton"
                            action:@selector(onPrevClicked:)];
  _playButton = [RubikTheme filledButton:@"Play" symbol:@"play.fill" target:self action:@selector(onPlayClicked:)];
  _playButton.accessibilityIdentifier = @"playButton";
  _playButton.toolTip = @"Auto-play the solution";
  _nextButton = [self symbolButton:@"forward.frame.fill"
                           tooltip:@"Next step"
                        identifier:@"nextButton"
                            action:@selector(onNextClicked:)];

  NSStackView* transport = [NSStackView stackViewWithViews:@[
    _firstButton, _prevButton, _playButton, _nextButton
  ]];
  transport.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  transport.alignment = NSLayoutAttributeCenterY;
  transport.distribution = NSStackViewDistributionFill;
  transport.spacing = 8.0;
  transport.translatesAutoresizingMaskIntoConstraints = NO;
  [root addSubview:transport];

  // Speed control.
  _speedControl = [NSSegmentedControl segmentedControlWithLabels:@[ @"0.5×", @"1×", @"2×" ]
                                                   trackingMode:NSSegmentSwitchTrackingSelectOne
                                                         target:self
                                                         action:@selector(onSpeedChanged:)];
  _speedControl.selectedSegment = 1;
  _speedControl.segmentStyle = NSSegmentStyleAutomatic;
  _speedControl.translatesAutoresizingMaskIntoConstraints = NO;
  _speedControl.accessibilityIdentifier = @"speedControl";
  _speedControl.toolTip = @"Playback speed";
  [root addSubview:_speedControl];

  // Solution header.
  NSTextField* solutionTitle = [self labelWithText:@"SOLUTION"
                                              font:[NSFont systemFontOfSize:8.5 weight:NSFontWeightBold]
                                             color:[RubikTheme textTertiary]];
  solutionTitle.translatesAutoresizingMaskIntoConstraints = NO;
  [root addSubview:solutionTitle];

  _movesCountLabel = [self labelWithText:@"0 MOVES"
                                    font:[RubikTheme monoFontOfSize:9 weight:NSFontWeightMedium]
                                   color:[RubikTheme textTertiary]];
  _movesCountLabel.alignment = NSTextAlignmentRight;
  _movesCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
  _movesCountLabel.accessibilityIdentifier = @"movesCountLabel";
  [root addSubview:_movesCountLabel];

  // Solution list.
  _tableScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  _tableScrollView.hasVerticalScroller = YES;
  _tableScrollView.drawsBackground = NO;
  _tableScrollView.borderType = NSNoBorder;
  _tableScrollView.autohidesScrollers = YES;
  _tableScrollView.translatesAutoresizingMaskIntoConstraints = NO;
  _tableScrollView.accessibilityIdentifier = @"movesTableScroll";

  _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
  _tableView.dataSource = self;
  _tableView.delegate = self;
  _tableView.rowHeight = 28.0;
  _tableView.intercellSpacing = NSMakeSize(0.0, 1.0);
  _tableView.backgroundColor = [NSColor clearColor];
  _tableView.usesAlternatingRowBackgroundColors = NO;
  _tableView.allowsEmptySelection = YES;
  _tableView.allowsMultipleSelection = NO;
  _tableView.headerView = nil;
  _tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
  _tableView.style = NSTableViewStylePlain;
  _tableView.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
  _tableView.accessibilityIdentifier = @"movesTable";
  _tableView.accessibilityLabel = @"Solution moves";

  NSTableColumn* stepColumn = [[NSTableColumn alloc] initWithIdentifier:@"step"];
  stepColumn.width = 28.0;
  stepColumn.minWidth = 24.0;
  stepColumn.maxWidth = 34.0;
  [_tableView addTableColumn:stepColumn];

  NSTableColumn* moveColumn = [[NSTableColumn alloc] initWithIdentifier:@"move"];
  moveColumn.width = 48.0;
  moveColumn.minWidth = 42.0;
  moveColumn.maxWidth = 64.0;
  [_tableView addTableColumn:moveColumn];

  NSTableColumn* descriptionColumn = [[NSTableColumn alloc] initWithIdentifier:@"desc"];
  descriptionColumn.width = 220.0;
  descriptionColumn.minWidth = 120.0;
  descriptionColumn.resizingMask = NSTableColumnAutoresizingMask;
  [_tableView addTableColumn:descriptionColumn];

  _tableScrollView.documentView = _tableView;
  [root addSubview:_tableScrollView];

  // Footer actions.
  _copyButton = [self actionButtonWithTitle:@"Copy Cube State for OpenCode"
                                     symbol:@"doc.on.doc"
                                 identifier:@"copyStateButton"
                                  prominent:NO
                                     action:@selector(onCopyStateClicked:)];
  _copyButton.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
  _copyButton.translatesAutoresizingMaskIntoConstraints = NO;
  [root addSubview:_copyButton];

  _solveButton = [self actionButtonWithTitle:@"Solve Cube"
                                      symbol:@"sparkles"
                                  identifier:@"solveButton"
                                   prominent:YES
                                      action:@selector(onSolveClicked:)];
  _solveButton.translatesAutoresizingMaskIntoConstraints = NO;
  [root addSubview:_solveButton];

  _scrambleButton = [self actionButtonWithTitle:@"Scramble"
                                         symbol:@"shuffle"
                                     identifier:@"scrambleButton"
                                      prominent:NO
                                         action:@selector(onScrambleClicked:)];
  _cameraButton = [self actionButtonWithTitle:@"Camera"
                                       symbol:@"camera.fill"
                                   identifier:@"cameraButton"
                                    prominent:NO
                                       action:@selector(onCameraClicked:)];
  _pdfButton = [self actionButtonWithTitle:@"PDF"
                                    symbol:@"doc.richtext"
                                identifier:@"pdfButton"
                                 prominent:NO
                                    action:@selector(onPDFClicked:)];
  NSStackView* secondary = [NSStackView stackViewWithViews:@[
    _scrambleButton, _cameraButton, _pdfButton
  ]];
  secondary.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  secondary.distribution = NSStackViewDistributionFillEqually;
  secondary.spacing = 8.0;
  secondary.translatesAutoresizingMaskIntoConstraints = NO;
  [root addSubview:secondary];

  // Constraints.
  [NSLayoutConstraint activateConstraints:@[
    [logo.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:side],
    [logo.topAnchor constraintEqualToAnchor:root.topAnchor constant:18],
    [logo.widthAnchor constraintEqualToConstant:36],
    [logo.heightAnchor constraintEqualToConstant:36],

    [logoImage.centerXAnchor constraintEqualToAnchor:logo.centerXAnchor],
    [logoImage.centerYAnchor constraintEqualToAnchor:logo.centerYAnchor],
    [logoImage.widthAnchor constraintEqualToConstant:20],
    [logoImage.heightAnchor constraintEqualToConstant:20],

    [title.leadingAnchor constraintEqualToAnchor:logo.trailingAnchor constant:10],
    [title.topAnchor constraintEqualToAnchor:logo.topAnchor constant:-1],
    [title.trailingAnchor constraintLessThanOrEqualToAnchor:_engineBadge.leadingAnchor constant:-8],

    [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
    [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:1],
    [subtitle.trailingAnchor constraintLessThanOrEqualToAnchor:_engineBadge.leadingAnchor constant:-8],

    [_engineBadge.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-side],
    [_engineBadge.centerYAnchor constraintEqualToAnchor:logo.centerYAnchor],

    [_statsLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:side],
    [_statsLabel.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-side],
    [_statsLabel.topAnchor constraintEqualToAnchor:logo.bottomAnchor constant:14],

    [_progressBar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:side],
    [_progressBar.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-side],
    [_progressBar.topAnchor constraintEqualToAnchor:_statsLabel.bottomAnchor constant:8],
    [_progressBar.heightAnchor constraintEqualToConstant:4],

    [_spotlightCard.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:side],
    [_spotlightCard.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-side],
    [_spotlightCard.topAnchor constraintEqualToAnchor:_progressBar.bottomAnchor constant:18],
    [_spotlightCard.heightAnchor constraintEqualToConstant:122],

    [_stepCaption.leadingAnchor constraintEqualToAnchor:_spotlightCard.leadingAnchor constant:16],
    [_stepCaption.topAnchor constraintEqualToAnchor:_spotlightCard.topAnchor constant:14],
    [_stepCounter.trailingAnchor constraintEqualToAnchor:_spotlightCard.trailingAnchor constant:-16],
    [_stepCounter.centerYAnchor constraintEqualToAnchor:_stepCaption.centerYAnchor],

    [_currentMoveLabel.leadingAnchor constraintEqualToAnchor:_spotlightCard.leadingAnchor constant:16],
    [_currentMoveLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_spotlightCard.trailingAnchor constant:-16],
    [_currentMoveLabel.topAnchor constraintEqualToAnchor:_stepCaption.bottomAnchor constant:3],

    [_currentDescLabel.leadingAnchor constraintEqualToAnchor:_spotlightCard.leadingAnchor constant:16],
    [_currentDescLabel.trailingAnchor constraintEqualToAnchor:_spotlightCard.trailingAnchor constant:-16],
    [_currentDescLabel.bottomAnchor constraintEqualToAnchor:_spotlightCard.bottomAnchor constant:-13],

    [transport.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:side],
    [transport.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-side],
    [transport.topAnchor constraintEqualToAnchor:_spotlightCard.bottomAnchor constant:12],
    [transport.heightAnchor constraintEqualToConstant:34],
    [_firstButton.widthAnchor constraintEqualToConstant:38],
    [_prevButton.widthAnchor constraintEqualToConstant:70],
    [_nextButton.widthAnchor constraintEqualToConstant:70],

    [_speedControl.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:side],
    [_speedControl.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-side],
    [_speedControl.topAnchor constraintEqualToAnchor:transport.bottomAnchor constant:8],
    [_speedControl.heightAnchor constraintEqualToConstant:24],

    [solutionTitle.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:side],
    [solutionTitle.topAnchor constraintEqualToAnchor:_speedControl.bottomAnchor constant:17],
    [_movesCountLabel.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-side],
    [_movesCountLabel.centerYAnchor constraintEqualToAnchor:solutionTitle.centerYAnchor],

    [_tableScrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:side],
    [_tableScrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-side],
    [_tableScrollView.topAnchor constraintEqualToAnchor:solutionTitle.bottomAnchor constant:8],
    [_tableScrollView.bottomAnchor constraintEqualToAnchor:_copyButton.topAnchor constant:-12],
    [_tableScrollView.heightAnchor constraintGreaterThanOrEqualToConstant:70],

    [_copyButton.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:side],
    [_copyButton.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-side],
    [_copyButton.heightAnchor constraintEqualToConstant:32],
    [_copyButton.bottomAnchor constraintEqualToAnchor:_solveButton.topAnchor constant:-8],

    [_solveButton.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:side],
    [_solveButton.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-side],
    [_solveButton.heightAnchor constraintEqualToConstant:40],
    [_solveButton.bottomAnchor constraintEqualToAnchor:secondary.topAnchor constant:-8],

    [secondary.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:side],
    [secondary.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-side],
    [secondary.heightAnchor constraintEqualToConstant:32],
    [secondary.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-18],
  ]];

  [self updateStepDisplay];
}

#pragma mark - Solution state

- (void)updateStats {
  if (_solutionMoves.empty()) {
    _statsLabel.stringValue = [NSString stringWithFormat:@"%@ · Ready", _engineDescription ?: @"Solver"];
  } else {
    _statsLabel.stringValue = [NSString stringWithFormat:@"%@ · %.0f ms · %zu moves",
                               _engineDescription ?: @"Solver", _solveTimeMs,
                               _solutionMoves.size()];
  }
  _statsLabel.accessibilityValue = _statsLabel.stringValue;
}

- (void)setSolutionMoves:(const std::vector<int>&)moves
             solveTimeMs:(double)timeMs {
  [self stopAutoPlay];
  _solutionMoves = moves;
  _currentStepIndex = 0;
  _solveTimeMs = timeMs;
  _solveButton.enabled = YES;

  if (moves.empty()) {
    _progressBar.doubleValue = 0.0;
  }
  [self updateMovesCount:moves.size()];
  [self updateStats];
  [_tableView reloadData];
  [self updateStepDisplay];
}

- (void)updateMovesCount:(NSUInteger)count {
  NSString* text = [NSString stringWithFormat:@"%zu MOVES", count];
  _movesCountLabel.stringValue = text;
  // NSTextField can keep serving its initial accessibility value even after
  // stringValue changes; publish the new value explicitly for automation.
  _movesCountLabel.accessibilityValue = text;
  NSAccessibilityPostNotification(_movesCountLabel, NSAccessibilityValueChangedNotification);
}

- (void)setSolverStatusText:(NSString*)text {
  _emptyStateText = [text copy] ?: @"No solution loaded";
  if (_solutionMoves.empty()) {
    [self updateStepDisplay];
  }
}

- (void)setEngineDescription:(NSString*)description gpuVerified:(BOOL)verified {
  _engineDescription = [description copy] ?: @"Solver";
  _engineGPUVerified = verified;
  [self updateEngineBadge];
  [self updateStats];
}

- (void)updateEngineBadge {
  NSString* firstWord = [_engineDescription componentsSeparatedByString:@" "].firstObject ?: @"SOLVER";
  firstWord = [firstWord uppercaseString];
  const BOOL exact = [_engineDescription localizedCaseInsensitiveContainsString:@"exact"];
  [_engineBadge setTitle:firstWord verified:_engineGPUVerified active:!exact];
  _engineBadge.toolTip = _engineDescription;
  _engineBadge.accessibilityValue = [NSString stringWithFormat:@"%@%@",
      _engineDescription, _engineGPUVerified ? @" · GPU verified" : @""];
}

- (void)updatePlayButton {
  NSString* title = _isAutoPlaying ? @"Pause" : @"Play";
  NSString* symbol = _isAutoPlaying ? @"pause.fill" : @"play.fill";
  _playButton.title = title;
  _playButton.image = [RubikTheme symbolNamed:symbol size:12 weight:NSFontWeightBold];
  _playButton.imagePosition = NSImageLeading;
  _playButton.layer.backgroundColor = (_isAutoPlaying
      ? [RubikTheme warning]
      : [RubikTheme accent]).CGColor;
  _playButton.toolTip = _isAutoPlaying ? @"Pause auto-play" : @"Auto-play the solution";
  _playButton.accessibilityLabel = _playButton.toolTip;
}

- (void)updateStepDisplay {
  const NSInteger total = (NSInteger)_solutionMoves.size();
  [self updatePlayButton];

  if (total == 0) {
    _currentMoveLabel.stringValue = @"—";
    _stepCaption.stringValue = @"CURRENT STEP";
    _stepCounter.stringValue = @"—";
    _currentDescLabel.stringValue = _emptyStateText ?: @"No solution loaded";
    _currentDescLabel.textColor = [RubikTheme textSecondary];
    _progressBar.doubleValue = 0.0;
    _prevButton.enabled = NO;
    _nextButton.enabled = NO;
    _playButton.enabled = NO;
    _firstButton.enabled = NO;
    [self updateMovesCount:0];
    _updatingSelection = YES;
    [_tableView deselectAll:nil];
    _updatingSelection = NO;
    return;
  }

  _firstButton.enabled = (_currentStepIndex > 0);
  _prevButton.enabled = (_currentStepIndex > 0);
  _nextButton.enabled = (_currentStepIndex < total);
  _playButton.enabled = (_currentStepIndex < total || _isAutoPlaying);
  _stepCounter.stringValue = [NSString stringWithFormat:@"%ld / %ld",
      (long)MIN(_currentStepIndex + 1, total), (long)total];
  _progressBar.doubleValue = (double)_currentStepIndex / (double)total;

  if (_currentStepIndex < total) {
    const int move = _solutionMoves[_currentStepIndex];
    _stepCaption.stringValue = @"CURRENT STEP";
    _currentMoveLabel.stringValue =
        [NSString stringWithUTF8String:RubikCube::moveToString(move).c_str()];
    _currentDescLabel.stringValue =
        [NSString stringWithFormat:@"%s", RubikCube::moveDescription(move).c_str()];
    _currentDescLabel.textColor = [RubikTheme textSecondary];
  } else {
    _stepCaption.stringValue = @"COMPLETE";
    _currentMoveLabel.stringValue = @"✓";
    _currentDescLabel.stringValue =
        [NSString stringWithFormat:@"Solved — all %ld moves completed.", (long)total];
    _currentDescLabel.textColor = [RubikTheme success];
    _stepCounter.stringValue = [NSString stringWithFormat:@"%ld / %ld", (long)total, (long)total];
  }

  if (_currentStepIndex < total) {
    _updatingSelection = YES;
    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:_currentStepIndex]
            byExtendingSelection:NO];
    [_tableView scrollRowToVisible:_currentStepIndex];
    _updatingSelection = NO;
  } else if (total > 0) {
    _updatingSelection = YES;
    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:total - 1]
            byExtendingSelection:NO];
    [_tableView scrollRowToVisible:total - 1];
    _updatingSelection = NO;
  }
}

#pragma mark - Navigation

- (void)goToNextStep {
  const NSInteger total = (NSInteger)_solutionMoves.size();
  if (_currentStepIndex >= total) return;

  const int move = _solutionMoves[_currentStepIndex];
  ++_currentStepIndex;
  [self updateStepDisplay];

  if ([self.delegate respondsToSelector:@selector(stepPanelDidRequestMove:isInverse:)]) {
    [self.delegate stepPanelDidRequestMove:move isInverse:NO];
  }

  if (_currentStepIndex >= total && _isAutoPlaying) {
    [self stopAutoPlay];
  }
}

- (void)goToPreviousStep {
  if (_currentStepIndex <= 0) return;
  --_currentStepIndex;
  const int move = _solutionMoves[_currentStepIndex];
  [self updateStepDisplay];
  if ([self.delegate respondsToSelector:@selector(stepPanelDidRequestMove:isInverse:)]) {
    [self.delegate stepPanelDidRequestMove:move isInverse:YES];
  }
}

- (void)resetToStart {
  [self stopAutoPlay];
  _currentStepIndex = 0;
  [self updateStepDisplay];
  if ([self.delegate respondsToSelector:@selector(stepPanelDidJumpToStep:)]) {
    [self.delegate stepPanelDidJumpToStep:0];
  }
}

- (void)startAutoPlay {
  if (!_isAutoPlaying) [self onPlayClicked:nil];
}

- (void)stopAutoPlay {
  if (!_isAutoPlaying) return;
  _isAutoPlaying = NO;
  [self updatePlayButton];
  [self updateStepDisplay];
  if ([self.delegate respondsToSelector:@selector(stepPanelDidRequestAutoPlay:)]) {
    [self.delegate stepPanelDidRequestAutoPlay:NO];
  }
}

- (void)onFirstClicked:(id)sender {
  [self resetToStart];
}

- (void)onPrevClicked:(id)sender {
  [self stopAutoPlay];
  [self goToPreviousStep];
}

- (void)onNextClicked:(id)sender {
  [self stopAutoPlay];
  [self goToNextStep];
}

- (void)onPlayClicked:(id)sender {
  if (_isAutoPlaying) {
    [self stopAutoPlay];
    return;
  }
  if (_solutionMoves.empty()) return;

  if (_currentStepIndex >= (NSInteger)_solutionMoves.size()) {
    _currentStepIndex = 0;
    [self updateStepDisplay];
    if ([self.delegate respondsToSelector:@selector(stepPanelDidJumpToStep:)]) {
      [self.delegate stepPanelDidJumpToStep:0];
    }
  }

  _isAutoPlaying = YES;
  [self updatePlayButton];
  if ([self.delegate respondsToSelector:@selector(stepPanelDidRequestAutoPlay:)]) {
    [self.delegate stepPanelDidRequestAutoPlay:YES];
  }
  [self goToNextStep];
}

- (void)didCompleteStepMove {
  if (!_isAutoPlaying) return;
  if (_currentStepIndex >= (NSInteger)_solutionMoves.size()) {
    [self stopAutoPlay];
    return;
  }
  __weak RubikStepPanelController* weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                               (int64_t)(_stepDuration * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
    RubikStepPanelController* strongSelf = weakSelf;
    if (strongSelf && strongSelf->_isAutoPlaying) {
      [strongSelf goToNextStep];
    }
  });
}

- (void)onSpeedChanged:(NSSegmentedControl*)sender {
  switch (sender.selectedSegment) {
    case 0: _stepDuration = 0.55; break;
    case 1: _stepDuration = 0.30; break;
    case 2: _stepDuration = 0.15; break;
    default: break;
  }
  if ([self.delegate respondsToSelector:@selector(stepPanelDidChangeSpeed:)]) {
    [self.delegate stepPanelDidChangeSpeed:_stepDuration];
  }
}

#pragma mark - Requests

- (void)onSolveClicked:(id)sender {
  _solveButton.enabled = NO;
  [self setSolverStatusText:@"Solving…"];
  if ([self.delegate respondsToSelector:@selector(stepPanelDidRequestSolve)]) {
    [self.delegate stepPanelDidRequestSolve];
  }
}

- (void)onScrambleClicked:(id)sender {
  if ([self.delegate respondsToSelector:@selector(stepPanelDidRequestScramble)]) {
    [self.delegate stepPanelDidRequestScramble];
  }
}

- (void)onCameraClicked:(id)sender {
  if ([self.delegate respondsToSelector:@selector(stepPanelDidRequestCamera)]) {
    [self.delegate stepPanelDidRequestCamera];
  }
}

- (void)onPDFClicked:(id)sender {
  if ([self.delegate respondsToSelector:@selector(stepPanelDidRequestPDFExport)]) {
    [self.delegate stepPanelDidRequestPDFExport];
  }
}

- (void)onCopyStateClicked:(id)sender {
  if ([self.delegate respondsToSelector:@selector(stepPanelDidRequestCopyState)]) {
    [self.delegate stepPanelDidRequestCopyState];
  }
}

#pragma mark - Table view

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
  return (NSInteger)_solutionMoves.size();
}

- (NSView*)tableView:(NSTableView*)tableView
   viewForTableColumn:(NSTableColumn*)tableColumn
                  row:(NSInteger)row {
  if (row < 0 || row >= (NSInteger)_solutionMoves.size()) return nil;

  NSString* identifier = tableColumn.identifier;
  NSTextField* cell = [tableView makeViewWithIdentifier:identifier owner:self];
  if (!cell) {
    cell = [NSTextField labelWithString:@""];
    cell.identifier = identifier;
    cell.editable = NO;
    cell.selectable = NO;
    cell.bordered = NO;
    cell.drawsBackground = NO;
    cell.lineBreakMode = NSLineBreakByTruncatingTail;
    cell.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
  }

  const int move = _solutionMoves[row];
  if ([identifier isEqualToString:@"step"]) {
    cell.stringValue = [NSString stringWithFormat:@"%ld", (long)(row + 1)];
    cell.font = [RubikTheme monoFontOfSize:9.5 weight:NSFontWeightRegular];
    cell.textColor = [RubikTheme textTertiary];
    cell.alignment = NSTextAlignmentRight;
  } else if ([identifier isEqualToString:@"move"]) {
    cell.stringValue = [NSString stringWithUTF8String:RubikCube::moveToString(move).c_str()];
    cell.font = [RubikTheme monoFontOfSize:12.5 weight:NSFontWeightBold];
    cell.textColor = [RubikTheme textPrimary];
    cell.alignment = NSTextAlignmentLeft;
  } else {
    cell.stringValue = [NSString stringWithUTF8String:RubikCube::moveDescription(move).c_str()];
    cell.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightRegular];
    cell.textColor = [RubikTheme textSecondary];
    cell.alignment = NSTextAlignmentLeft;
  }
  return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
  if (_updatingSelection) return;
  const NSInteger selectedRow = _tableView.selectedRow;
  if (selectedRow < 0 || selectedRow >= (NSInteger)_solutionMoves.size()) return;
  if (selectedRow == _currentStepIndex) return;

  [self stopAutoPlay];
  _currentStepIndex = selectedRow;
  [self updateStepDisplay];
  if ([self.delegate respondsToSelector:@selector(stepPanelDidJumpToStep:)]) {
    [self.delegate stepPanelDidJumpToStep:selectedRow];
  }
}

@end
