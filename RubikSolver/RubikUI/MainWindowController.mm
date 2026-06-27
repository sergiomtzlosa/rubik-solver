//
//  MainWindowController.mm
//  RubikSolver - Primary macOS Window & Application Coordinator
//

#import "MainWindowController.h"
#import "RubikHelpWindowController.h"
#import "RubikFaceUploadSheetController.h"
#import "RubikRandomGeneratorSheetController.h"
#import "RubikTheme.h"
#import "RubikCoreMLModel.h"

static NSToolbarItemIdentifier const kToolbarRandomItem = @"rubik.toolbar.random";
static NSToolbarItemIdentifier const kToolbarSolveItem = @"rubik.toolbar.solve";
static NSToolbarItemIdentifier const kToolbarCameraItem = @"rubik.toolbar.camera";
static NSToolbarItemIdentifier const kToolbarPhotoItem = @"rubik.toolbar.photo";
static NSToolbarItemIdentifier const kToolbarEngineItem = @"rubik.toolbar.engine";
static NSToolbarItemIdentifier const kToolbarCopyItem = @"rubik.toolbar.copy";
static NSToolbarItemIdentifier const kToolbarResetItem = @"rubik.toolbar.reset";
static NSToolbarItemIdentifier const kToolbarHelpItem = @"rubik.toolbar.help";

@interface MainWindowController () <NSToolbarDelegate>
- (void)applySolveResult:(const RubikSolveResult&)result;
@end

@implementation MainWindowController {
    RubikCube _cubeModel;
    RubikCube _scrambleState;
    std::vector<int> _lastScrambleMoves;
    std::vector<int> _solutionMoves;
    double _solveTimeMs;

    RubikMetalSolver* _metalSolver;
    RubikSolverKind _solverKind;
    BOOL _isSolving;
    NSInteger _solveGeneration;

    Rubik3DView* _view3D;
    RubikCameraOverlayView* _cameraOverlay;
    RubikStepPanelController* _stepPanel;
    NSSplitViewController* _splitViewController;

    NSView* _viewerPane;
    NSView* _viewerHintPill;
    NSView* _statusBar;
    NSView* _statusDot;
    NSTextField* _statusHUD;
    NSButton* _copyStatusButton;
    NSButton* _stopButton;

    NSPopUpButton* _enginePopup;
    NSButton* _solveToolbarButton;
    NSButton* _randomToolbarButton;
    NSButton* _cameraToolbarButton;
    NSButton* _photosToolbarButton;

    BOOL _gpuVerified;
    NSString* _gpuDetail;
    uint8_t _configuredFacesMask;
    id _keyMonitor;
}

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 1280, 820);
    NSWindowStyleMask style = NSWindowStyleMaskTitled |
                              NSWindowStyleMaskClosable |
                              NSWindowStyleMaskMiniaturizable |
                              NSWindowStyleMaskResizable;

    NSWindow* window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"RubikSolver";
    window.subtitle = @"Verified cube solving · exact and Core ML";
    window.minSize = NSMakeSize(1080, 700);
    window.backgroundColor = [RubikTheme background];
    window.tabbingMode = NSWindowTabbingModeDisallowed;
    window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [window center];

    self = [super initWithWindow:window];
    if (self) {
        _cubeModel.reset();
        _scrambleState = _cubeModel;
        _solveTimeMs = 0.0;
        _isSolving = NO;
        _solveGeneration = 0;
        _configuredFacesMask = 0;
        _gpuVerified = NO;
        _gpuDetail = @"Core ML placement has not been verified yet.";

        NSInteger savedEngine = [[NSUserDefaults standardUserDefaults] integerForKey:@"RubikSolverEngineKind"];
        if (savedEngine < 0 || savedEngine > 2) savedEngine = 0;
        _solverKind = (RubikSolverKind)savedEngine;

        _metalSolver = [[RubikMetalSolver alloc] init];

        [self setupSplitView];
        [self setupToolbar];
        [self setupKeyboardShortcuts];
        [self updateEngineDescription];
        [self verifyGPUInBackground];
        [self setStatus:@"Ready — scramble, scan, or solve a cube." tone:[RubikTheme textTertiary]];
    }
    return self;
}

- (void)dealloc {
    if (_keyMonitor) {
        [NSEvent removeMonitor:_keyMonitor];
        _keyMonitor = nil;
    }
}

#pragma mark - Layout

- (void)setupSplitView {
    _viewerPane = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 860, 760)];
    _viewerPane.wantsLayer = YES;
    _viewerPane.layer.backgroundColor = [RubikTheme background].CGColor;
    _viewerPane.accessibilityIdentifier = @"viewerPane";

    _view3D = [[Rubik3DView alloc] initWithFrame:_viewerPane.bounds];
    _view3D.translatesAutoresizingMaskIntoConstraints = NO;
    _view3D.rubikDelegate = self;
    _view3D.backgroundColor = [RubikTheme background];
    _view3D.accessibilityIdentifier = @"cube3DView";
    [_viewerPane addSubview:_view3D];

    [self setupViewerOverlays];
    [self setupStepPanel];

    NSViewController* viewerController = [[NSViewController alloc] init];
    viewerController.view = _viewerPane;

    NSSplitViewItem* viewerItem = [NSSplitViewItem splitViewItemWithViewController:viewerController];
    viewerItem.minimumThickness = 620;
    viewerItem.canCollapse = NO;
    viewerItem.holdingPriority = NSLayoutPriorityDefaultLow;

    NSSplitViewItem* panelItem = [NSSplitViewItem splitViewItemWithViewController:_stepPanel];
    panelItem.minimumThickness = 344;
    panelItem.maximumThickness = 440;
    panelItem.preferredThicknessFraction = 0.30;
    panelItem.canCollapse = NO;
    panelItem.holdingPriority = NSLayoutPriorityDefaultHigh;
    panelItem.titlebarSeparatorStyle = NSTitlebarSeparatorStyleLine;

    _splitViewController = [[NSSplitViewController alloc] init];
    _splitViewController.splitView.vertical = YES;
    _splitViewController.splitView.dividerStyle = NSSplitViewDividerStyleThin;
    [_splitViewController addSplitViewItem:viewerItem];
    [_splitViewController addSplitViewItem:panelItem];
    self.window.contentViewController = _splitViewController;
}

- (void)setupViewerOverlays {
    // Compact interaction hint, top-left.
    NSImageView* hintIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    hintIcon.image = [RubikTheme symbolNamed:@"rotate.3d" size:12 weight:NSFontWeightSemibold];
    hintIcon.contentTintColor = [RubikTheme textSecondary];
    hintIcon.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField* hintLabel = [RubikTheme labelWithText:@"Drag to orbit · Scroll to zoom"
                                                 font:[NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium]
                                                color:[RubikTheme textSecondary]];
    hintLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView* hintStack = [NSStackView stackViewWithViews:@[hintIcon, hintLabel]];
    hintStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    hintStack.alignment = NSLayoutAttributeCenterY;
    hintStack.spacing = 6.0;
    hintStack.translatesAutoresizingMaskIntoConstraints = NO;

    _viewerHintPill = [[NSView alloc] initWithFrame:NSZeroRect];
    _viewerHintPill.wantsLayer = YES;
    _viewerHintPill.layer.cornerRadius = 9.0;
    _viewerHintPill.layer.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.30].CGColor;
    _viewerHintPill.layer.borderWidth = 1.0;
    _viewerHintPill.layer.borderColor = [[NSColor whiteColor] colorWithAlphaComponent:0.07].CGColor;
    _viewerHintPill.translatesAutoresizingMaskIntoConstraints = NO;
    _viewerHintPill.accessibilityIdentifier = @"viewerHint";
    [_viewerHintPill addSubview:hintStack];
    [_viewerPane addSubview:_viewerHintPill];

    // Bottom status bar.
    _statusBar = [[NSView alloc] initWithFrame:NSZeroRect];
    _statusBar.wantsLayer = YES;
    _statusBar.layer.cornerRadius = 12.0;
    _statusBar.layer.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.46].CGColor;
    _statusBar.layer.borderWidth = 1.0;
    _statusBar.layer.borderColor = [[NSColor whiteColor] colorWithAlphaComponent:0.08].CGColor;
    _statusBar.translatesAutoresizingMaskIntoConstraints = NO;
    _statusBar.accessibilityIdentifier = @"statusBar";
    [_viewerPane addSubview:_statusBar];

    _statusDot = [[NSView alloc] initWithFrame:NSZeroRect];
    _statusDot.wantsLayer = YES;
    _statusDot.layer.cornerRadius = 3.5;
    _statusDot.layer.backgroundColor = [RubikTheme textTertiary].CGColor;
    _statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    [_statusBar addSubview:_statusDot];

    _statusHUD = [RubikTheme labelWithText:@"Ready"
                                     font:[NSFont systemFontOfSize:11 weight:NSFontWeightMedium]
                                    color:[RubikTheme textSecondary]];
    _statusHUD.translatesAutoresizingMaskIntoConstraints = NO;
    _statusHUD.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _statusHUD.accessibilityIdentifier = @"statusLabel";
    [_statusBar addSubview:_statusHUD];

    _copyStatusButton = [RubikTheme symbolButton:@"doc.on.doc"
                                       tooltip:@"Copy cube state for OpenCode"
                                        target:self
                                        action:@selector(copyCubeStateForOpenCode)];
    _copyStatusButton.translatesAutoresizingMaskIntoConstraints = NO;
    _copyStatusButton.accessibilityIdentifier = @"copyStateStatusButton";
    [_statusBar addSubview:_copyStatusButton];

    // Stop button floating above the status bar.
    _stopButton = [RubikTheme filledButton:@"Stop Solver" symbol:@"stop.fill"
                                   target:self action:@selector(stopSolver)];
    _stopButton.layer.backgroundColor = [RubikTheme danger].CGColor;
    _stopButton.contentTintColor = [NSColor whiteColor];
    _stopButton.translatesAutoresizingMaskIntoConstraints = NO;
    _stopButton.accessibilityIdentifier = @"stopSolverButton";
    _stopButton.hidden = YES;
    [_viewerPane addSubview:_stopButton];

    // Camera scanner covers the viewer when active.
    _cameraOverlay = [[RubikCameraOverlayView alloc] initWithFrame:_viewerPane.bounds];
    _cameraOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    _cameraOverlay.delegate = self;
    _cameraOverlay.hidden = YES;
    [_viewerPane addSubview:_cameraOverlay];

    [NSLayoutConstraint activateConstraints:@[
        [_view3D.leadingAnchor constraintEqualToAnchor:_viewerPane.leadingAnchor],
        [_view3D.trailingAnchor constraintEqualToAnchor:_viewerPane.trailingAnchor],
        [_view3D.topAnchor constraintEqualToAnchor:_viewerPane.topAnchor],
        [_view3D.bottomAnchor constraintEqualToAnchor:_viewerPane.bottomAnchor],

        [_viewerHintPill.leadingAnchor constraintEqualToAnchor:_viewerPane.leadingAnchor constant:20],
        [_viewerHintPill.topAnchor constraintEqualToAnchor:_viewerPane.topAnchor constant:18],
        [_viewerHintPill.heightAnchor constraintEqualToConstant:28],

        [hintStack.leadingAnchor constraintEqualToAnchor:_viewerHintPill.leadingAnchor constant:10],
        [hintStack.trailingAnchor constraintEqualToAnchor:_viewerHintPill.trailingAnchor constant:-11],
        [hintStack.centerYAnchor constraintEqualToAnchor:_viewerHintPill.centerYAnchor],
        [hintIcon.widthAnchor constraintEqualToConstant:14],
        [hintIcon.heightAnchor constraintEqualToConstant:14],

        [_stopButton.centerXAnchor constraintEqualToAnchor:_viewerPane.centerXAnchor],
        [_stopButton.bottomAnchor constraintEqualToAnchor:_statusBar.topAnchor constant:-12],
        [_stopButton.widthAnchor constraintEqualToConstant:150],
        [_stopButton.heightAnchor constraintEqualToConstant:36],

        [_statusBar.leadingAnchor constraintEqualToAnchor:_viewerPane.leadingAnchor constant:20],
        [_statusBar.trailingAnchor constraintEqualToAnchor:_viewerPane.trailingAnchor constant:-20],
        [_statusBar.bottomAnchor constraintEqualToAnchor:_viewerPane.bottomAnchor constant:-18],
        [_statusBar.heightAnchor constraintEqualToConstant:40],

        [_statusDot.leadingAnchor constraintEqualToAnchor:_statusBar.leadingAnchor constant:14],
        [_statusDot.centerYAnchor constraintEqualToAnchor:_statusBar.centerYAnchor],
        [_statusDot.widthAnchor constraintEqualToConstant:7],
        [_statusDot.heightAnchor constraintEqualToConstant:7],

        [_statusHUD.leadingAnchor constraintEqualToAnchor:_statusDot.trailingAnchor constant:9],
        [_statusHUD.centerYAnchor constraintEqualToAnchor:_statusBar.centerYAnchor],
        [_statusHUD.trailingAnchor constraintLessThanOrEqualToAnchor:_copyStatusButton.leadingAnchor constant:-10],

        [_copyStatusButton.trailingAnchor constraintEqualToAnchor:_statusBar.trailingAnchor constant:-8],
        [_copyStatusButton.centerYAnchor constraintEqualToAnchor:_statusBar.centerYAnchor],
        [_copyStatusButton.widthAnchor constraintEqualToConstant:26],
        [_copyStatusButton.heightAnchor constraintEqualToConstant:26],

        [_cameraOverlay.leadingAnchor constraintEqualToAnchor:_viewerPane.leadingAnchor],
        [_cameraOverlay.trailingAnchor constraintEqualToAnchor:_viewerPane.trailingAnchor],
        [_cameraOverlay.topAnchor constraintEqualToAnchor:_viewerPane.topAnchor],
        [_cameraOverlay.bottomAnchor constraintEqualToAnchor:_viewerPane.bottomAnchor],
    ]];
}

- (void)setupStepPanel {
    _stepPanel = [[RubikStepPanelController alloc] init];
    _stepPanel.delegate = self;
    _stepPanel.view.accessibilityIdentifier = @"stepPanel";
}

- (void)setStatus:(NSString*)message tone:(NSColor*)tone {
    _statusHUD.stringValue = message ?: @"";
    _statusHUD.accessibilityValue = message ?: @"";
    _statusDot.layer.backgroundColor = (tone ?: [RubikTheme textTertiary]).CGColor;
}

#pragma mark - Toolbar

- (void)setupToolbar {
    NSToolbar* toolbar = [[NSToolbar alloc] initWithIdentifier:@"RubikSolverToolbar"];
    toolbar.delegate = self;
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    toolbar.allowsUserCustomization = NO;
    toolbar.autosavesConfiguration = NO;
    self.window.toolbar = toolbar;
    self.window.toolbarStyle = NSWindowToolbarStyleUnified;
}

- (NSArray<NSToolbarItemIdentifier>*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar {
    return @[
        kToolbarRandomItem,
        kToolbarSolveItem,
        kToolbarCameraItem,
        kToolbarPhotoItem,
        NSToolbarFlexibleSpaceItemIdentifier,
        kToolbarEngineItem,
        kToolbarCopyItem,
        kToolbarResetItem,
        kToolbarHelpItem,
    ];
}

- (NSArray<NSToolbarItemIdentifier>*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar {
    return @[
        kToolbarRandomItem,
        kToolbarSolveItem,
        kToolbarCameraItem,
        kToolbarPhotoItem,
        kToolbarCopyItem,
        kToolbarResetItem,
        kToolbarHelpItem,
        kToolbarEngineItem,
        NSToolbarFlexibleSpaceItemIdentifier,
        NSToolbarSpaceItemIdentifier,
    ];
}

- (NSButton*)toolbarButtonWithSymbol:(NSString*)symbol
                                title:(NSString*)title
                             tooltip:(NSString*)tooltip
                                action:(SEL)action
                          identifier:(NSString*)identifier {
    NSButton* button;
    if (title.length > 0) {
        button = [NSButton buttonWithTitle:title target:self action:action];
        button.image = [RubikTheme symbolNamed:symbol size:12 weight:NSFontWeightSemibold];
        button.imagePosition = NSImageLeading;
        button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    } else {
        button = [NSButton buttonWithImage:[RubikTheme symbolNamed:symbol size:13 weight:NSFontWeightSemibold]
                                    target:self
                                    action:action];
    }
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.toolTip = tooltip;
    button.accessibilityLabel = tooltip;
    button.accessibilityIdentifier = identifier;
    [button setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                       forOrientation:NSLayoutConstraintOrientationHorizontal];
    return button;
}

- (NSToolbarItem*)toolbar:(NSToolbar*)toolbar
     itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];

    if ([itemIdentifier isEqualToString:kToolbarRandomItem]) {
        _randomToolbarButton = [self toolbarButtonWithSymbol:@"shuffle"
                                                       title:@"Random"
                                                    tooltip:@"Scramble the cube with a random 22-move sequence"
                                                     action:@selector(scrambleAndReset)
                                                 identifier:@"toolbarRandomButton"];
        item.view = _randomToolbarButton;
        item.label = @"Random";
        item.paletteLabel = @"Random Scramble";
    } else if ([itemIdentifier isEqualToString:kToolbarSolveItem]) {
        _solveToolbarButton = [self toolbarButtonWithSymbol:@"sparkles"
                                                      title:@"Solve"
                                                   tooltip:@"Solve the current cube (⌘S)"
                                                    action:@selector(solveWithMetalGPU)
                                                identifier:@"toolbarSolveButton"];
        _solveToolbarButton.contentTintColor = [RubikTheme accent];
        item.view = _solveToolbarButton;
        item.label = @"Solve";
        item.paletteLabel = @"Solve Cube";
    } else if ([itemIdentifier isEqualToString:kToolbarCameraItem]) {
        _cameraToolbarButton = [self toolbarButtonWithSymbol:@"camera.fill"
                                                       title:@"Scan"
                                                    tooltip:@"Scan a cube with the camera"
                                                     action:@selector(toggleCameraScanner)
                                                 identifier:@"toolbarCameraButton"];
        item.view = _cameraToolbarButton;
        item.label = @"Scan";
        item.paletteLabel = @"Camera Scanner";
    } else if ([itemIdentifier isEqualToString:kToolbarPhotoItem]) {
        _photosToolbarButton = [self toolbarButtonWithSymbol:@"photo.on.rectangle.angled"
                                                      title:@"Photos"
                                                   tooltip:@"Solve from photos: upload one image per face (⌘U)"
                                                    action:@selector(uploadFaceImage)
                                                identifier:@"toolbarPhotosButton"];
        item.view = _photosToolbarButton;
        item.label = @"Photos";
        item.paletteLabel = @"Six-Face Photo Upload";
    } else if ([itemIdentifier isEqualToString:kToolbarCopyItem]) {
        NSButton* button = [self toolbarButtonWithSymbol:@"doc.on.doc"
                                                   title:@""
                                                tooltip:@"Copy cube state for OpenCode (⇧⌘C)"
                                                 action:@selector(copyCubeStateForOpenCode)
                                             identifier:@"toolbarCopyButton"];
        item.view = button;
        item.label = @"Copy State";
        item.paletteLabel = @"Copy Cube State for OpenCode";
    } else if ([itemIdentifier isEqualToString:kToolbarResetItem]) {
        NSButton* button = [self toolbarButtonWithSymbol:@"arrow.counterclockwise"
                                                   title:@""
                                                tooltip:@"Reset the cube to solved (⌘K)"
                                                 action:@selector(resetCubeToSolved)
                                             identifier:@"toolbarResetButton"];
        item.view = button;
        item.label = @"Reset";
        item.paletteLabel = @"Reset Cube";
    } else if ([itemIdentifier isEqualToString:kToolbarHelpItem]) {
        NSButton* button = [self toolbarButtonWithSymbol:@"questionmark.circle"
                                                   title:@""
                                                tooltip:@"Open the help guide"
                                                 action:@selector(openHelpGuide)
                                             identifier:@"toolbarHelpButton"];
        item.view = button;
        item.label = @"Help";
        item.paletteLabel = @"Help";
    } else if ([itemIdentifier isEqualToString:kToolbarEngineItem]) {
        _enginePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 168, 24) pullsDown:NO];
        [_enginePopup addItemsWithTitles:@[
            @"Exact · CPU",
            @"Neural · Core ML GPU",
            @"Hybrid · GPU + exact",
        ]];
        _enginePopup.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
        _enginePopup.controlSize = NSControlSizeSmall;
        _enginePopup.target = self;
        _enginePopup.action = @selector(onEngineChanged:);
        _enginePopup.toolTip = @"Choose the exact CPU solver, the Core ML GPU solver, or hybrid fallback.";
        _enginePopup.accessibilityLabel = @"Solver engine";
        _enginePopup.accessibilityIdentifier = @"enginePopup";
        [_enginePopup selectItemAtIndex:MIN(_enginePopup.numberOfItems - 1,
                                            MAX(0, (NSInteger)_solverKind))];
        item.view = _enginePopup;
        item.label = @"Engine";
        item.paletteLabel = @"Solver Engine";
    } else {
        return nil;
    }
    return item;
}

- (void)updateSolvingUI:(BOOL)solving {
    _isSolving = solving;
    _stopButton.hidden = !solving;
    _solveToolbarButton.enabled = !solving;
    _randomToolbarButton.enabled = !solving;
    _cameraToolbarButton.enabled = !solving;
    _photosToolbarButton.enabled = !solving;
    _enginePopup.enabled = !solving;
    [self.window.toolbar validateVisibleItems];
}

- (void)onEngineChanged:(NSPopUpButton*)sender {
    NSInteger index = sender.indexOfSelectedItem;
    if (index < 0 || index > 2) index = 0;
    _solverKind = (RubikSolverKind)index;
    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:@"RubikSolverEngineKind"];
    [self updateEngineDescription];
    [self setStatus:[NSString stringWithFormat:@"Engine: %@", [self engineDescription]]
              tone:[RubikTheme accent]];
}

#pragma mark - Engine description

- (NSString*)engineDescription {
    switch (_solverKind) {
        case RubikSolverKind::Neural:
            return _gpuVerified ? @"Neural · Core ML GPU" : @"Neural · Core ML";
        case RubikSolverKind::Hybrid:
            return _gpuVerified ? @"Hybrid · GPU + exact" : @"Hybrid · exact fallback";
        case RubikSolverKind::Exact:
        default:
            return @"Exact · ckociemba (CPU)";
    }
}

- (void)updateEngineDescription {
    BOOL gpu = (_solverKind != RubikSolverKind::Exact) && _gpuVerified;
    [_stepPanel setEngineDescription:[self engineDescription] gpuVerified:gpu];
    _enginePopup.toolTip = [NSString stringWithFormat:@"%@\n%@",
                            [self engineDescription], _gpuDetail ?: @"Core ML placement pending."];
}

- (void)verifyGPUInBackground {
    __weak MainWindowController* weakSelf = self;
    [[RubikCoreMLModel sharedInstance] verifyGPUUsageWithCompletion:^(BOOL usingGPU, NSString* details) {
        dispatch_async(dispatch_get_main_queue(), ^{
            MainWindowController* strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_gpuVerified = usingGPU;
            strongSelf->_gpuDetail = [details copy] ?: @"Core ML placement unknown.";
            [strongSelf updateEngineDescription];
        });
    }];
}

#pragma mark - Keyboard

- (void)setupKeyboardShortcuts {
    __weak MainWindowController* weakSelf = self;
    _keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                        handler:^NSEvent* _Nullable(NSEvent* event) {
        MainWindowController* strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.window.isKeyWindow) return event;

        NSResponder* responder = strongSelf.window.firstResponder;
        if ([responder isKindOfClass:[NSTextView class]] && [(NSTextView*)responder isEditable]) {
            return event;
        }

        NSString* chars = event.charactersIgnoringModifiers;
        NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;

        if ((flags & NSEventModifierFlagCommand) && [chars isEqualToString:@"0"]) {
            [strongSelf resetView3DToViewport];
            return nil;
        }

        if ((flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl |
                      NSEventModifierFlagOption)) == 0) {
            if (event.keyCode == 53 && !strongSelf->_cameraOverlay.hidden) { // Escape
                [strongSelf closeCameraScanner];
                return nil;
            }
            if ([chars isEqualToString:@" "] || [chars isEqualToString:@"0"] ||
                [chars caseInsensitiveCompare:@"c"] == NSOrderedSame ||
                [chars caseInsensitiveCompare:@"v"] == NSOrderedSame) {
                [strongSelf resetView3DToViewport];
                return nil;
            }
        }
        return event;
    }];
}

#pragma mark - Actions

- (IBAction)centerView3DMenuAction:(id)sender {
    [self resetView3DToViewport];
}

- (void)resetView3DToViewport {
    [_view3D centerCubeInBounds];
    [self setStatus:@"3D view centered in the viewport (⌘0 / Space / C)."
              tone:[RubikTheme accent]];
}

- (void)cancelActiveSolveForNewState {
    if (!_isSolving) return;
    ++_solveGeneration;
    [_metalSolver cancelSolve];
    [self updateSolvingUI:NO];
    [_stepPanel setSolverStatusText:@"Solve cancelled — the cube changed."];
}

- (void)resetCubeToSolved {
    [self cancelActiveSolveForNewState];
    _cubeModel.reset();
    _scrambleState = _cubeModel;
    _lastScrambleMoves.clear();
    _solutionMoves.clear();
    _solveTimeMs = 0;
    _configuredFacesMask = 0;

    [_view3D resetCube];
    [_stepPanel setSolutionMoves:_solutionMoves solveTimeMs:0];
    [_stepPanel setSolverStatusText:@"Solved cube ready. Scramble it or scan a cube."];
    [self setStatus:@"Cube reset to the solved state." tone:[RubikTheme success]];
}

- (void)scrambleAndReset {
    [self generateRandomCubeWithMoves:22 autoSolve:NO];
}

- (void)generateRandomCubeAndSolveDefault {
    [self generateRandomCubeWithMoves:22 autoSolve:YES];
}

- (void)scrambleEasyAndSolve {
    [self generateRandomCubeWithMoves:10 autoSolve:YES];
}

- (void)scrambleHardAndSolve {
    [self generateRandomCubeWithMoves:25 autoSolve:YES];
}

- (void)openRandomCubeGeneratorSheet {
    [self cancelActiveSolveForNewState];
    __weak MainWindowController* weakSelf = self;
    [[RubikRandomGeneratorSheetController sharedController]
        showGeneratorSheetForWindow:self.window
                         completion:^(const RubikCube& scrambledCube,
                                      const std::vector<int>& scrambleMoves,
                                      BOOL autoSolve) {
        MainWindowController* strongSelf = weakSelf;
        if (!strongSelf) return;

        strongSelf->_cubeModel = scrambledCube;
        strongSelf->_scrambleState = scrambledCube;
        strongSelf->_lastScrambleMoves = scrambleMoves;
        strongSelf->_solutionMoves.clear();
        strongSelf->_configuredFacesMask = 0x3F;

        [strongSelf->_view3D updateWithCubeState:strongSelf->_cubeModel];
        [strongSelf->_stepPanel setSolutionMoves:strongSelf->_solutionMoves solveTimeMs:0];
        [strongSelf setStatus:[NSString stringWithFormat:@"Random cube generated with %zu moves.",
                                                        scrambleMoves.size()]
                        tone:[RubikTheme accent]];

        if (autoSolve) [strongSelf solveWithMetalGPU];
    }];
}

- (void)generateRandomCubeWithMoves:(int)numMoves autoSolve:(BOOL)autoSolve {
    [self cancelActiveSolveForNewState];
    _cubeModel.reset();
    std::vector<int> scrambleMoves = _cubeModel.scramble(numMoves);
    _lastScrambleMoves = scrambleMoves;
    _scrambleState = _cubeModel;
    _solutionMoves.clear();
    _configuredFacesMask = 0x3F;

    [_view3D updateWithCubeState:_cubeModel];
    [_stepPanel setSolutionMoves:_solutionMoves solveTimeMs:0];
    [_stepPanel setSolverStatusText:@"Scrambled. Solve it, or step through manually."];
    [self setStatus:[NSString stringWithFormat:@"Random %d-move scramble: %s", numMoves,
                                                      RubikCube::movesToString(scrambleMoves).c_str()]
              tone:[RubikTheme accent]];

    if (autoSolve) [self solveWithMetalGPU];
}

- (void)solveWithMetalGPU {
    if (_isSolving) return;

    if (_cubeModel.isSolved()) {
        _solutionMoves.clear();
        [self setStatus:@"The cube is already solved." tone:[RubikTheme success]];
        [_stepPanel setSolutionMoves:{} solveTimeMs:0];
        [_stepPanel setSolverStatusText:@"Cube is in the solved state."];
        return;
    }

    std::string validationError;
    if (!_cubeModel.isValidCube(&validationError)) {
        NSString* reason = [NSString stringWithUTF8String:validationError.c_str()];
        [self setStatus:[NSString stringWithFormat:@"Not solvable: %@", reason ?: @"invalid state"]
                  tone:[RubikTheme danger]];
        [_stepPanel setSolutionMoves:{} solveTimeMs:0];
        [_stepPanel setSolverStatusText:[NSString stringWithFormat:@"Invalid cube: %@",
                                                                    reason ?: @"unknown error"]];
        return;
    }

    const NSInteger generation = ++_solveGeneration;
    [self updateSolvingUI:YES];
    [self updateEngineDescription];

    RubikSolverOptions options;
    options.kind = _solverKind;
    options.timeoutSeconds = 30;
    options.maxDepth = 24;
    options.neuralBeamWidth = 512;
    options.neuralMaxDepth = 30;
    options.neuralMaxNodes = 200000;
    options.neuralPolicyWeight = 0.25f;
    options.neuralTimeBudgetSeconds = 4.0f;
    options.hybridFallsBackToExact = true;
    options.simplify = true;
    options.verify = true;

    RubikCube targetCube = _cubeModel;
    RubikMetalSolver* solver = _metalSolver;
    NSString* engine = [self engineDescription];
    NSString* solvingMessage = (_solverKind == RubikSolverKind::Exact)
        ? @"Solving with ckociemba's exact two-phase search…"
        : [NSString stringWithFormat:@"Solving with %@ — every move is replayed and verified…", engine];

    [self setStatus:solvingMessage tone:[RubikTheme warning]];
    [_stepPanel setSolverStatusText:solvingMessage];

    __weak MainWindowController* weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        RubikSolveResult result = [solver solveCubeTyped:targetCube options:options];
        dispatch_async(dispatch_get_main_queue(), ^{
            MainWindowController* strongSelf = weakSelf;
            if (!strongSelf || generation != strongSelf->_solveGeneration) return;
            [strongSelf updateSolvingUI:NO];
            [strongSelf applySolveResult:result];
        });
    });
}

- (void)applySolveResult:(const RubikSolveResult&)result {
    _solveTimeMs = result.timeMs;
    _solutionMoves = result.moves;

    NSString* usedEngine = nil;
    switch (result.engineUsed) {
        case RubikSolverKind::Neural:
            usedEngine = result.usedFallback ? @"Neural · exact fallback" : @"Neural · Core ML";
            break;
        case RubikSolverKind::Hybrid:
            usedEngine = result.usedFallback ? @"Hybrid · exact fallback" : @"Hybrid · GPU + exact";
            break;
        case RubikSolverKind::Exact:
        default:
            if (result.usedFallback) {
                usedEngine = _solverKind == RubikSolverKind::Neural
                    ? @"Neural · exact fallback"
                    : @"Hybrid · exact fallback";
            } else {
                usedEngine = @"Exact · ckociemba (CPU)";
            }
            break;
    }
    const BOOL gpuUsed = (result.engineUsed != RubikSolverKind::Exact) && !result.usedFallback &&
                         _gpuVerified;
    [_stepPanel setEngineDescription:usedEngine gpuVerified:gpuUsed];

    switch (result.status) {
        case RubikSolveStatus::Success: {
            [_stepPanel setSolutionMoves:result.moves solveTimeMs:result.timeMs];
            [self setStatus:[NSString stringWithFormat:@"Solved in %.0f ms · %zu moves · verified",
                                                       result.timeMs, result.moves.size()]
                      tone:[RubikTheme success]];
            [_view3D updateWithCubeState:_cubeModel];
            const BOOL autoPlayDisabled =
                [NSProcessInfo.processInfo.environment[@"RUBIK_DISABLE_AUTOPLAY"] isEqualToString:@"1"];
            if (!result.moves.empty() && !autoPlayDisabled) [_stepPanel startAutoPlay];
            break;
        }

        case RubikSolveStatus::AlreadySolved:
            _solutionMoves.clear();
            [self setStatus:@"The cube is already solved." tone:[RubikTheme success]];
            [_stepPanel setSolutionMoves:{} solveTimeMs:result.timeMs];
            [_stepPanel setSolverStatusText:@"Cube is in the solved state."];
            break;

        case RubikSolveStatus::InvalidState:
            _solutionMoves.clear();
            [self setStatus:[NSString stringWithFormat:@"Invalid cube state: %s", result.message.c_str()]
                      tone:[RubikTheme danger]];
            [_stepPanel setSolutionMoves:{} solveTimeMs:result.timeMs];
            [_stepPanel setSolverStatusText:@"The cube state is not solvable."];
            break;

        case RubikSolveStatus::Cancelled:
            _solutionMoves.clear();
            [self setStatus:@"Solve cancelled." tone:[RubikTheme warning]];
            [_stepPanel setSolutionMoves:{} solveTimeMs:result.timeMs];
            [_stepPanel setSolverStatusText:@"Solve cancelled."];
            break;

        case RubikSolveStatus::Timeout:
            _solutionMoves.clear();
            [self setStatus:[NSString stringWithFormat:@"Solver timed out after %.0f s.",
                                                       result.timeMs / 1000.0]
                      tone:[RubikTheme warning]];
            [_stepPanel setSolutionMoves:{} solveTimeMs:result.timeMs];
            [_stepPanel setSolverStatusText:@"The solver timed out."];
            break;

        case RubikSolveStatus::Busy:
            _solutionMoves.clear();
            [self setStatus:@"The solver is already running." tone:[RubikTheme warning]];
            [_stepPanel setSolutionMoves:{} solveTimeMs:result.timeMs];
            [_stepPanel setSolverStatusText:@"The solver is busy."];
            break;

        case RubikSolveStatus::NoSolution:
        case RubikSolveStatus::InternalError:
        default:
            _solutionMoves.clear();
            [self setStatus:[NSString stringWithFormat:@"Solve failed: %s", result.message.c_str()]
                      tone:[RubikTheme danger]];
            [_stepPanel setSolutionMoves:{} solveTimeMs:result.timeMs];
            [_stepPanel setSolverStatusText:@"Solve failed."];
            break;
    }
}

- (void)stopSolver {
    if (!_isSolving) return;
    [_metalSolver cancelSolve];
    [self setStatus:@"Cancelling the solver…" tone:[RubikTheme warning]];
}

#pragma mark - OpenCode integration

- (void)copyCubeStateForOpenCode {
    const std::string facelets = _cubeModel.toFaceletString();
    NSString* state = [NSString stringWithUTF8String:facelets.c_str()] ?: @"";
    NSString* prompt = [NSString stringWithFormat:
        @"Solve this Rubik's Cube.\n\n"
         "Facelets (U R F D L B, row-major, 54 characters):\n%@\n\n"
         "Use the rubik_solve tool to find and verify a solution.",
        state];

    NSPasteboard* pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:prompt forType:NSPasteboardTypeString];
    [pasteboard setString:state forType:@"com.rubik.facelets"];

    [self setStatus:[NSString stringWithFormat:@"Copied cube state for OpenCode · %@", state]
              tone:[RubikTheme accent]];
    [_stepPanel setSolverStatusText:@"Cube state copied. Paste it into OpenCode to solve with rubik_solve."];

    NSBeep();
}

#pragma mark - Camera

- (void)showCameraScanner {
    if (!_cameraOverlay.hidden) return;
    [self cancelActiveSolveForNewState];
    _cameraOverlay.hidden = NO;
    [_cameraOverlay resetScan];
    [_cameraOverlay startScanning];
    [self setStatus:@"Camera scanner active — capture six faces in any order."
              tone:[RubikTheme accent]];
}

- (void)closeCameraScanner {
    [_cameraOverlay stopScanning];
    _cameraOverlay.hidden = YES;
    [self setStatus:@"Camera scanner closed." tone:[RubikTheme textTertiary]];
}

- (void)toggleCameraScanner {
    if (_cameraOverlay.hidden) {
        [self showCameraScanner];
    } else {
        [self closeCameraScanner];
    }
}

#pragma mark - Photo upload

- (void)uploadFaceImage {
    [self cancelActiveSolveForNewState];
    RubikColorClassifier* classifier = [[RubikColorClassifier alloc] init];
    __weak MainWindowController* weakSelf = self;

    [[RubikFaceUploadSheetController sharedController]
        showCubeUploadSheetForWindow:self.window
                           cubeModel:_cubeModel
                          classifier:classifier
                 configuredFacesMask:_configuredFacesMask
                          completion:^(const uint8_t facelets[54], uint8_t configuredMask, BOOL autoSolve) {
        MainWindowController* strongSelf = weakSelf;
        if (!strongSelf) return;

        for (int i = 0; i < 54; ++i) {
            const int face = i / 9;
            if (configuredMask & (1 << face)) {
                strongSelf->_cubeModel.setFacelet(i, facelets[i]);
            }
        }
        strongSelf->_configuredFacesMask |= configuredMask;
        strongSelf->_scrambleState = strongSelf->_cubeModel;
        [strongSelf->_view3D updateWithCubeState:strongSelf->_cubeModel];

        int configuredCount = 0;
        for (int face = 0; face < 6; ++face) {
            if (strongSelf->_configuredFacesMask & (1 << face)) ++configuredCount;
        }

        [strongSelf setStatus:[NSString stringWithFormat:@"Applied %d/6 faces from photos.",
                                                         configuredCount]
                        tone:[RubikTheme accent]];

        if (autoSolve) {
            std::string error;
            if (strongSelf->_cubeModel.isValidCube(&error)) {
                [strongSelf solveWithMetalGPU];
            } else {
                [strongSelf setStatus:[NSString stringWithFormat:
                    @"Faces applied (%d/6). Cannot solve: %s", configuredCount, error.c_str()]
                                tone:[RubikTheme danger]];
                [strongSelf->_stepPanel setSolverStatusText:@"Cube state is not solvable."];
            }
        }
    }];
}

- (void)openHelpGuide {
    [[RubikHelpWindowController sharedHelpController] showHelpWindow];
}

#pragma mark - RubikStepPanelDelegate

- (void)stepPanelDidRequestMove:(int)move isInverse:(BOOL)isInverse {
    if (isInverse) {
        const int inverse = RubikCube::invertMove(move);
        _cubeModel.applyMove(inverse);
        [_view3D animateMove:inverse completion:nil];
    } else {
        _cubeModel.applyMove(move);
        [_view3D animateMove:move completion:nil];
    }
}

- (void)stepPanelDidJumpToStep:(NSInteger)stepIndex {
    RubikCube state = _scrambleState;
    for (NSInteger i = 0; i < stepIndex && i < (NSInteger)_solutionMoves.size(); ++i) {
        state.applyMove(_solutionMoves[i]);
    }
    _cubeModel = state;
    [_view3D updateWithCubeState:_cubeModel];
}

- (void)stepPanelDidRequestAutoPlay:(BOOL)start {
    [self setStatus:(start ? @"Auto-playing the verified solution…"
                           : @"Auto-play paused. Continue with the transport controls.")
              tone:(start ? [RubikTheme accent] : [RubikTheme textTertiary])];
}

- (void)stepPanelDidChangeSpeed:(NSTimeInterval)duration {
    _view3D.animationDuration = duration;
}

- (void)stepPanelDidRequestPDFExport {
    if (_solutionMoves.empty() && !_cubeModel.isSolved()) {
        NSAlert* alert = [[NSAlert alloc] init];
        alert.messageText = @"No Solution Computed Yet";
        alert.informativeText = @"Solve the cube first, then export the illustrated PDF guide.";
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }

    [RubikPDFExporter exportSolutionWithWindow:self.window
                                   initialCube:_scrambleState
                                         moves:_solutionMoves
                                   solveTimeMs:_solveTimeMs];
}

- (void)stepPanelDidRequestScramble {
    [self scrambleAndReset];
}

- (void)stepPanelDidRequestCamera {
    [self toggleCameraScanner];
}

- (void)stepPanelDidRequestSolve {
    [self solveWithMetalGPU];
}

- (void)stepPanelDidRequestCopyState {
    [self copyCubeStateForOpenCode];
}

#pragma mark - Rubik3DViewDelegate

- (void)rubik3DViewDidFinishMove:(int)move {
    if (_cubeModel.isSolved()) {
        [self setStatus:@"Solved — every move replayed and verified." tone:[RubikTheme success]];
    }
    [_stepPanel didCompleteStepMove];
}

#pragma mark - RubikCameraOverlayDelegate

- (void)cameraOverlayDidFinishAllFaces:(const RubikCube&)cube {
    _cameraOverlay.hidden = YES;
    _cubeModel = cube;
    _scrambleState = cube;
    _configuredFacesMask = 0x3F;
    [_view3D updateWithCubeState:_cubeModel];
    [self setStatus:@"Camera scan complete — all 54 facelets validated. Solving…"
              tone:[RubikTheme success]];
    [self solveWithMetalGPU];
}

- (void)cameraOverlayDidCancel {
    _cameraOverlay.hidden = YES;
    [self setStatus:@"Camera scan cancelled." tone:[RubikTheme textTertiary]];
}

@end
