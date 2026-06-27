//
//  RubikCameraOverlayView.mm
//  RubikSolver - Camera Viewfinder HUD & 6-Face Scanner
//

#import "RubikCameraOverlayView.h"
#import "RubikCameraGeometry.h"
#import "RubikScanSession.h"
#import "RubikValidation.h"

#import <QuartzCore/QuartzCore.h>
#include <algorithm>
#include <cmath>
#include <vector>

static NSColor* RubikAccentColor() {
    return [NSColor colorWithSRGBRed:0.20 green:0.82 blue:0.76 alpha:1.0];
}

static NSColor* RubikWarnColor() {
    return [NSColor colorWithSRGBRed:0.98 green:0.65 blue:0.20 alpha:1.0];
}

static NSColor* RubikSuccessColor() {
    return [NSColor colorWithSRGBRed:0.32 green:0.86 blue:0.52 alpha:1.0];
}

static NSColor* RubikDangerColor() {
    return [NSColor colorWithSRGBRed:0.96 green:0.34 blue:0.36 alpha:1.0];
}

static NSColor* RubikCardColor() {
    return [NSColor colorWithSRGBRed:0.09 green:0.10 blue:0.12 alpha:1.0];
}

static NSTextField* RubikLabel(NSString* text, CGFloat size, NSFontWeight weight, NSColor* color) {
    NSTextField* label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

#pragma mark - Grid overlay

@interface RubikGridOverlayView : NSView
@property (nonatomic, assign) NSRect gridRect;
@property (nonatomic, assign) std::vector<SampledPatch> patches;
@property (nonatomic, assign) BOOL cameraRunning;
@end

@implementation RubikGridOverlayView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
    }
    return self;
}

- (NSView*)hitTest:(NSPoint)point {
    return nil;
}

- (void)drawRect:(NSRect)dirtyRect {
    if (self.gridRect.size.width <= 0) return;

    // Dim everything outside the alignment grid.
    NSBezierPath* dim = [NSBezierPath bezierPathWithRect:self.bounds];
    [dim appendBezierPath:[NSBezierPath bezierPathWithRoundedRect:self.gridRect
                                                         xRadius:18 yRadius:18]];
    dim.windingRule = NSWindingRuleEvenOdd;
    [[NSColor colorWithWhite:0.0 alpha:0.52] setFill];
    [dim fill];

    // Grid plate.
    NSBezierPath* plate = [NSBezierPath bezierPathWithRoundedRect:self.gridRect
                                                         xRadius:18 yRadius:18];
    [[NSColor colorWithWhite:0.04 alpha:0.22] setFill];
    [plate fill];

    // Corner brackets.
    const CGFloat bracketLength = 26.0;
    const CGFloat bracketWidth = 3.5;
    [[RubikAccentColor() colorWithAlphaComponent:0.95] setStroke];

    const NSPoint corners[4] = {
        NSMakePoint(NSMinX(self.gridRect), NSMaxY(self.gridRect)),
        NSMakePoint(NSMaxX(self.gridRect), NSMaxY(self.gridRect)),
        NSMakePoint(NSMinX(self.gridRect), NSMinY(self.gridRect)),
        NSMakePoint(NSMaxX(self.gridRect), NSMinY(self.gridRect)),
    };
    const CGFloat dx[4] = {1, -1, 1, -1};
    const CGFloat dy[4] = {-1, -1, 1, 1};
    for (int i = 0; i < 4; ++i) {
        NSBezierPath* bracket = [NSBezierPath bezierPath];
        [bracket moveToPoint:NSMakePoint(corners[i].x, corners[i].y + dy[i] * bracketLength)];
        [bracket lineToPoint:corners[i]];
        [bracket lineToPoint:NSMakePoint(corners[i].x + dx[i] * bracketLength, corners[i].y)];
        bracket.lineWidth = bracketWidth;
        bracket.lineCapStyle = NSLineCapStyleRound;
        [bracket stroke];
    }

    // Sticker cells.
    const CGFloat cellW = self.gridRect.size.width / 3.0;
    const CGFloat cellH = self.gridRect.size.height / 3.0;
    const CGFloat inset = 5.0;

    for (int row = 0; row < 3; ++row) {
        for (int col = 0; col < 3; ++col) {
            const NSRect cellRect = NSMakeRect(
                NSMinX(self.gridRect) + col * cellW + inset,
                NSMinY(self.gridRect) + (2 - row) * cellH + inset,
                cellW - inset * 2, cellH - inset * 2);
            NSBezierPath* cellPath = [NSBezierPath bezierPathWithRoundedRect:cellRect
                                                                     xRadius:10 yRadius:10];
            const int index = row * 3 + col;
            const BOOL hasPatch = index < static_cast<int>(self.patches.size());

            if (hasPatch) {
                const SampledPatch patch = self.patches[index];
                const BOOL known = patch.colorIndex < NUM_COLORS;
                NSColor* color = known ? [RubikColorClassifier nsColorForIndex:patch.colorIndex]
                                       : [NSColor colorWithWhite:0.25 alpha:1.0];
                [[color colorWithAlphaComponent:known ? 0.72 : 0.35] setFill];
                [cellPath fill];

                [[color colorWithAlphaComponent:0.95] setStroke];
                cellPath.lineWidth = 2.0;
                [cellPath stroke];

                NSPoint center = NSMakePoint(NSMidX(cellRect), NSMidY(cellRect));
                NSString* letter = known
                    ? [@[ @"W", @"R", @"G", @"Y", @"O", @"B" ][patch.colorIndex] copy]
                    : @"?";
                const BOOL darkInk = known &&
                    (patch.colorIndex == COLOR_WHITE || patch.colorIndex == COLOR_YELLOW);
                NSDictionary* attributes = @{
                    NSFontAttributeName: [NSFont systemFontOfSize:22 weight:NSFontWeightBold],
                    NSForegroundColorAttributeName: darkInk ? [NSColor blackColor]
                                                            : [NSColor whiteColor],
                };
                NSSize size = [letter sizeWithAttributes:attributes];
                [letter drawAtPoint:NSMakePoint(center.x - size.width / 2.0,
                                                center.y - size.height / 2.0)
                     withAttributes:attributes];

                // Confidence pip in the lower-right corner.
                const CGFloat pipRadius = 3.5;
                NSRect pipRect = NSMakeRect(NSMaxX(cellRect) - 2 * pipRadius - 8,
                                            NSMinY(cellRect) + 8,
                                            pipRadius * 2, pipRadius * 2);
                NSColor* pipColor = !patch.reliable ? RubikWarnColor()
                                   : (patch.confidence > 0.55 ? RubikSuccessColor()
                                                              : RubikWarnColor());
                [pipColor setFill];
                [[NSBezierPath bezierPathWithOvalInRect:pipRect] fill];
            } else {
                [[NSColor colorWithWhite:1.0 alpha:0.05] setFill];
                [cellPath fill];
                NSBezierPath* border = [NSBezierPath bezierPathWithRoundedRect:cellRect
                                                                       xRadius:10 yRadius:10];
                [[NSColor colorWithWhite:1.0 alpha:0.22] setStroke];
                border.lineWidth = 1.0;
                const CGFloat dash[] = {5.0, 5.0};
                [border setLineDash:dash count:2 phase:0];
                [border stroke];

                const CGFloat cx = NSMidX(cellRect);
                const CGFloat cy = NSMidY(cellRect);
                NSBezierPath* cross = [NSBezierPath bezierPath];
                [cross moveToPoint:NSMakePoint(cx - 8, cy)];
                [cross lineToPoint:NSMakePoint(cx + 8, cy)];
                [cross moveToPoint:NSMakePoint(cx, cy - 8)];
                [cross lineToPoint:NSMakePoint(cx, cy + 8)];
                [[NSColor colorWithWhite:1.0 alpha:0.30] setStroke];
                cross.lineWidth = 1.2;
                [cross stroke];
            }
        }
    }

    if (!self.cameraRunning) {
        NSDictionary* attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: [NSColor colorWithWhite:1.0 alpha:0.65],
        };
        NSString* text = @"Camera is off";
        NSSize size = [text sizeWithAttributes:attrs];
        [text drawAtPoint:NSMakePoint(NSMidX(self.gridRect) - size.width / 2.0,
                                      NSMinY(self.gridRect) - 26)
           withAttributes:attrs];
    }
}

@end

#pragma mark - Review net

struct RubikNetGeometry {
    NSRect faces[6];
    NSRect stickers[6][9];
};

@interface RubikNetReviewView : NSView
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, copy) void (^onStickerSelected)(NSInteger index);
- (void)setFacelets:(const uint8_t*)facelets
        confidences:(const float*)confidences
          reliable:(const bool*)reliable;
@end

@implementation RubikNetReviewView {
    uint8_t _facelets[54];
    float _confidences[54];
    bool _reliable[54];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _selectedIndex = -1;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 12;
        self.layer.backgroundColor = [NSColor colorWithWhite:0.06 alpha:1.0].CGColor;
        [self setAccessibilityElement:YES];
        self.accessibilityRole = NSAccessibilityGroupRole;
        self.accessibilityLabel = @"Cube review net";
    }
    return self;
}

- (BOOL)isFlipped {
    return NO;
}

- (void)setFacelets:(const uint8_t*)facelets
        confidences:(const float*)confidences
          reliable:(const bool*)reliable {
    if (!facelets) return;
    for (int i = 0; i < 54; ++i) {
        _facelets[i] = facelets[i];
        _confidences[i] = confidences ? confidences[i] : 0.0f;
        _reliable[i] = reliable ? reliable[i] : false;
    }
    [self setNeedsDisplay:YES];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    if (_selectedIndex == selectedIndex) return;
    _selectedIndex = selectedIndex;
    [self setNeedsDisplay:YES];
}

- (RubikNetGeometry)netGeometry {
    RubikNetGeometry geometry;
    const CGFloat width = self.bounds.size.width;
    const CGFloat height = self.bounds.size.height;
    CGFloat sticker = std::min((width - 28.0) / 13.25, (height - 28.0) / 9.9);
    sticker = std::max<CGFloat>(5.0, sticker);
    const CGFloat faceGap = sticker * 0.40;
    const CGFloat totalW = 12.0 * sticker + 3.0 * faceGap;
    const CGFloat totalH = 9.0 * sticker + 2.0 * faceGap;
    const CGFloat originX = (width - totalW) / 2.0;
    const CGFloat originY = (height - totalH) / 2.0;

    // U, R, F, D, L, B in an unfolded net: U above F, L/F/R/B in a row, D
    // below F.
    static const int columns[6] = {1, 2, 1, 1, 0, 3};
    static const int rows[6] = {0, 1, 1, 2, 1, 1};
    const CGFloat faceSide = 3.0 * sticker;
    const CGFloat innerGap = 0.07 * sticker;
    const CGFloat innerSticker = 0.86 * sticker;
    const CGFloat margin = 0.14 * sticker;

    for (int face = 0; face < 6; ++face) {
        const CGFloat x = originX + columns[face] * (faceSide + faceGap);
        const CGFloat y = originY + totalH - rows[face] * (faceSide + faceGap) - faceSide;
        geometry.faces[face] = NSMakeRect(x, y, faceSide, faceSide);
        for (int row = 0; row < 3; ++row) {
            for (int col = 0; col < 3; ++col) {
                geometry.stickers[face][row * 3 + col] = NSMakeRect(
                    x + margin + col * (innerSticker + innerGap),
                    y + faceSide - margin - innerSticker - row * (innerSticker + innerGap),
                    innerSticker, innerSticker);
            }
        }
    }
    return geometry;
}

- (void)drawRect:(NSRect)dirtyRect {
    if (self.bounds.size.width < 40 || self.bounds.size.height < 40) return;
    const RubikNetGeometry geometry = [self netGeometry];

    static const char* faceLabels[6] = {"U", "R", "F", "D", "L", "B"};
    NSDictionary* labelAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:9 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.65 alpha:1.0],
    };

    for (int face = 0; face < 6; ++face) {
        NSBezierPath* facePath = [NSBezierPath bezierPathWithRoundedRect:geometry.faces[face]
                                                                 xRadius:8 yRadius:8];
        [[NSColor colorWithWhite:0.14 alpha:1.0] setFill];
        [facePath fill];
        [[NSColor colorWithWhite:1.0 alpha:0.08] setStroke];
        facePath.lineWidth = 1.0;
        [facePath stroke];

        NSString* label = [NSString stringWithUTF8String:faceLabels[face]];
        [label drawAtPoint:NSMakePoint(NSMinX(geometry.faces[face]) + 6,
                                       NSMaxY(geometry.faces[face]) + 2)
            withAttributes:labelAttributes];

        for (int cell = 0; cell < 9; ++cell) {
            const int index = face * 9 + cell;
            const NSRect rect = geometry.stickers[face][cell];
            NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:4 yRadius:4];
            const uint8_t color = _facelets[index];

            if (color < NUM_COLORS) {
                NSColor* fill = [RubikColorClassifier nsColorForIndex:color];
                [fill setFill];
                [path fill];
            } else {
                [[NSColor colorWithWhite:0.24 alpha:1.0] setFill];
                [path fill];
                NSDictionary* unknown = @{
                    NSFontAttributeName: [NSFont systemFontOfSize:rect.size.height * 0.55 weight:NSFontWeightBold],
                    NSForegroundColorAttributeName: [NSColor colorWithWhite:0.7 alpha:1.0],
                };
                NSString* question = @"?";
                NSSize size = [question sizeWithAttributes:unknown];
                [question drawAtPoint:NSMakePoint(NSMidX(rect) - size.width / 2.0,
                                                  NSMidY(rect) - size.height / 2.0)
                       withAttributes:unknown];
            }

            const BOOL isCentre = (cell == 4);
            if (index == _selectedIndex) {
                [RubikAccentColor() setStroke];
                path.lineWidth = 3.0;
            } else if (isCentre) {
                [[NSColor colorWithWhite:1.0 alpha:0.65] setStroke];
                path.lineWidth = 1.5;
            } else {
                [[NSColor colorWithWhite:0.0 alpha:0.35] setStroke];
                path.lineWidth = 0.8;
            }
            [path stroke];

            // Confidence marker for non-centre stickers.
            if (!isCentre) {
                NSColor* marker = _reliable[index]
                    ? [RubikSuccessColor() colorWithAlphaComponent:0.75]
                    : RubikWarnColor();
                [marker setFill];
                NSRect pip = NSMakeRect(NSMaxX(rect) - 5.5, NSMaxY(rect) - 5.5, 3.5, 3.5);
                [[NSBezierPath bezierPathWithOvalInRect:pip] fill];
            }
        }
    }
}

- (void)mouseDown:(NSEvent*)event {
    const NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    const RubikNetGeometry geometry = [self netGeometry];
    for (int face = 0; face < 6; ++face) {
        for (int cell = 0; cell < 9; ++cell) {
            if (cell == 4) continue;
            if (!NSPointInRect(point, geometry.stickers[face][cell])) continue;
            const NSInteger index = face * 9 + cell;
            self.selectedIndex = index;
            if (self.onStickerSelected) self.onStickerSelected(index);
            return;
        }
    }
}

- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:[NSCursor pointingHandCursor]];
}

- (NSString*)accessibilityValue {
    NSMutableString* summary = [NSMutableString string];
    static const char* names[6] = {"Up", "Right", "Front", "Down", "Left", "Back"};
    for (int face = 0; face < 6; ++face) {
        [summary appendFormat:@"%s: ", names[face]];
        for (int cell = 0; cell < 9; ++cell) {
            const uint8_t color = _facelets[face * 9 + cell];
            [summary appendString:color < NUM_COLORS
                ? [@[ @"white", @"red", @"green", @"yellow", @"orange", @"blue" ][color] stringByAppendingString:@" "]
                : @"unknown "];
        }
        if (face < 5) [summary appendString:@"; "];
    }
    return summary;
}

@end

#pragma mark - Overlay

@interface RubikCameraOverlayView ()
@property (nonatomic, readwrite) RubikCameraCapture* cameraCapture;
@property (nonatomic, readwrite) RubikScanSession* scanSession;
@property (nonatomic, readwrite) NSUInteger currentFaceIndex;
@property (nonatomic, readwrite) BOOL reviewVisible;
@end

@implementation RubikCameraOverlayView {
    RubikColorClassifier* _classifier;
    RubikGridOverlayView* _gridOverlay;
    RubikNetReviewView* _reviewNet;
    NSView* _videoContainer;
    NSView* _instructionPill;
    NSTextField* _instructionLabel;
    NSTextField* _statusLabel;
    NSTextField* _progressLabel;
    NSTextField* _reviewTitle;
    NSTextField* _reviewSubtitle;
    NSTextField* _paletteLabel;
    NSTextField* _rotateLabel;
    NSPopUpButton* _rotateFacePopup;
    NSButton* _captureButton;
    NSButton* _undoButton;
    NSButton* _resetButton;
    NSButton* _closeButton;
    NSButton* _retryButton;
    NSButton* _settingsButton;
    NSButton* _acceptButton;
    NSButton* _rescanButton;
    NSButton* _undoFaceButton;
    NSButton* _rotateButton;
    NSButton* _paletteButtons[NUM_COLORS];
    NSView* _errorPanel;
    NSTextField* _errorTitle;
    NSTextField* _errorMessage;
    NSView* _reviewPanel;

    std::vector<SampledPatch> _currentPatches;
    std::vector<RubikColorReading> _latestReadings;
    CGSize _bufferSize;
    NSRect _gridRect;
    NSInteger _selectedReviewIndex;
    CFTimeInterval _lastSampleTime;
    BOOL _cameraStarting;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = [NSColor blackColor].CGColor;
        self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        self.accessibilityIdentifier = @"cameraOverlay";

        _cameraCapture = [[RubikCameraCapture alloc] init];
        _cameraCapture.delegate = self;
        _classifier = [[RubikColorClassifier alloc] init];
        _scanSession = [[RubikScanSession alloc] init];
        _selectedReviewIndex = -1;

        _videoContainer = [[NSView alloc] initWithFrame:self.bounds];
        _videoContainer.wantsLayer = YES;
        _videoContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        if (_cameraCapture.previewLayer) {
            _cameraCapture.previewLayer.frame = _videoContainer.bounds;
            [_videoContainer.layer addSublayer:_cameraCapture.previewLayer];
        }
        [self addSubview:_videoContainer];

        _gridOverlay = [[RubikGridOverlayView alloc] initWithFrame:self.bounds];
        _gridOverlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self addSubview:_gridOverlay];

        [self setupUI];
        [self layoutControls];
    }
    return self;
}

- (void)dealloc {
    _cameraCapture.delegate = nil;
    [_cameraCapture stopCameraCapture];
}

#pragma mark - UI construction

- (void)setupUI {
    _instructionPill = [[NSView alloc] initWithFrame:NSZeroRect];
    _instructionPill.wantsLayer = YES;
    _instructionPill.layer.backgroundColor = [NSColor colorWithWhite:0.05 alpha:0.72].CGColor;
    _instructionPill.layer.cornerRadius = 10.0;
    _instructionPill.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.10].CGColor;
    _instructionPill.layer.borderWidth = 1.0;
    [self addSubview:_instructionPill];

    _instructionLabel = RubikLabel(@"Scan the first face", 14, NSFontWeightSemibold,
                                   [NSColor whiteColor]);
    _instructionLabel.alignment = NSTextAlignmentCenter;
    _instructionLabel.accessibilityIdentifier = @"cameraInstructionLabel";
    [_instructionPill addSubview:_instructionLabel];

    _statusLabel = RubikLabel(@"Camera is starting…", 12, NSFontWeightRegular,
                              [NSColor colorWithWhite:0.82 alpha:1.0]);
    _statusLabel.alignment = NSTextAlignmentCenter;
    _statusLabel.accessibilityIdentifier = @"cameraStatusLabel";
    [self addSubview:_statusLabel];

    _progressLabel = RubikLabel(@"0 / 6 faces", 11, NSFontWeightMedium,
                                [NSColor colorWithWhite:0.68 alpha:1.0]);
    _progressLabel.alignment = NSTextAlignmentCenter;
    _progressLabel.accessibilityIdentifier = @"cameraProgressLabel";
    [self addSubview:_progressLabel];

    _captureButton = [self makeButton:@"Capture Face" action:@selector(captureCurrentFace)
                          identifier:@"cameraCaptureButton" prominent:YES];
    [self addSubview:_captureButton];

    _undoButton = [self makeButton:@"Undo Face" action:@selector(onUndoFace:)
                      identifier:@"cameraUndoButton" prominent:NO];
    [self addSubview:_undoButton];

    _resetButton = [self makeButton:@"Reset Scan" action:@selector(resetScan)
                       identifier:@"cameraResetButton" prominent:NO];
    [self addSubview:_resetButton];

    _closeButton = [NSButton buttonWithImage:[self symbolNamed:@"xmark"]
                                      target:self
                                      action:@selector(onCloseClicked:)];
    _closeButton.bezelStyle = NSBezelStyleCircular;
    _closeButton.bordered = NO;
    _closeButton.contentTintColor = [NSColor whiteColor];
    _closeButton.accessibilityIdentifier = @"cameraCloseButton";
    _closeButton.toolTip = @"Close camera";
    [self addSubview:_closeButton];

    [self setupErrorPanel];
    [self setupReviewPanel];
    [self updateInstruction];
}

- (NSImage*)symbolNamed:(NSString*)name {
    NSImage* image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:name];
    image.size = NSMakeSize(15, 15);
    return image;
}

- (NSButton*)makeButton:(NSString*)title
                 action:(SEL)action
             identifier:(NSString*)identifier
              prominent:(BOOL)prominent {
    NSButton* button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.bordered = NO;
    button.wantsLayer = YES;
    button.layer.cornerRadius = 9.0;
    button.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    button.contentTintColor = prominent ? [NSColor colorWithWhite:0.05 alpha:1.0]
                                        : [NSColor colorWithWhite:0.92 alpha:1.0];
    button.layer.backgroundColor = prominent
        ? RubikAccentColor().CGColor
        : [NSColor colorWithWhite:1.0 alpha:0.08].CGColor;
    button.accessibilityIdentifier = identifier;
    return button;
}

- (void)setupErrorPanel {
    _errorPanel = [[NSView alloc] initWithFrame:NSZeroRect];
    _errorPanel.wantsLayer = YES;
    _errorPanel.layer.cornerRadius = 16.0;
    _errorPanel.layer.backgroundColor = RubikCardColor().CGColor;
    _errorPanel.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.12].CGColor;
    _errorPanel.layer.borderWidth = 1.0;
    _errorPanel.hidden = YES;
    _errorPanel.accessibilityIdentifier = @"cameraErrorPanel";
    [self addSubview:_errorPanel];

    _errorTitle = RubikLabel(@"Camera unavailable", 17, NSFontWeightSemibold,
                             [NSColor whiteColor]);
    [_errorPanel addSubview:_errorTitle];

    _errorMessage = RubikLabel(@"", 12, NSFontWeightRegular,
                               [NSColor colorWithWhite:0.76 alpha:1.0]);
    _errorMessage.maximumNumberOfLines = 4;
    _errorMessage.lineBreakMode = NSLineBreakByWordWrapping;
    _errorMessage.alignment = NSTextAlignmentCenter;
    [_errorPanel addSubview:_errorMessage];

    _retryButton = [self makeButton:@"Try Again" action:@selector(onRetryCamera:)
                       identifier:@"cameraRetryButton" prominent:YES];
    [_errorPanel addSubview:_retryButton];

    _settingsButton = [self makeButton:@"Open Settings" action:@selector(onOpenCameraSettings:)
                          identifier:@"cameraSettingsButton" prominent:NO];
    [_errorPanel addSubview:_settingsButton];
}

- (void)setupReviewPanel {
    _reviewPanel = [[NSView alloc] initWithFrame:NSZeroRect];
    _reviewPanel.wantsLayer = YES;
    _reviewPanel.layer.cornerRadius = 18.0;
    _reviewPanel.layer.backgroundColor =
        [NSColor colorWithSRGBRed:0.07 green:0.075 blue:0.09 alpha:0.985].CGColor;
    _reviewPanel.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.10].CGColor;
    _reviewPanel.layer.borderWidth = 1.0;
    _reviewPanel.hidden = YES;
    _reviewPanel.accessibilityIdentifier = @"cameraReviewPanel";
    [self addSubview:_reviewPanel];

    _reviewTitle = RubikLabel(@"Review your cube", 22, NSFontWeightBold, [NSColor whiteColor]);
    [_reviewPanel addSubview:_reviewTitle];

    _reviewSubtitle = RubikLabel(@"", 12, NSFontWeightRegular,
                                 [NSColor colorWithWhite:0.78 alpha:1.0]);
    _reviewSubtitle.maximumNumberOfLines = 2;
    _reviewSubtitle.lineBreakMode = NSLineBreakByWordWrapping;
    _reviewSubtitle.accessibilityIdentifier = @"cameraReviewStatusLabel";
    [_reviewPanel addSubview:_reviewSubtitle];

    _reviewNet = [[RubikNetReviewView alloc] initWithFrame:NSZeroRect];
    _reviewNet.accessibilityIdentifier = @"cameraReviewNet";
    __weak __typeof__(self) weakSelf = self;
    _reviewNet.onStickerSelected = ^(NSInteger index) {
        [weakSelf onReviewStickerSelected:index];
    };
    [_reviewPanel addSubview:_reviewNet];

    _paletteLabel = RubikLabel(@"Colour:", 11, NSFontWeightMedium,
                               [NSColor colorWithWhite:0.62 alpha:1.0]);
    [_reviewPanel addSubview:_paletteLabel];

    static NSString* const names[6] = {@"W", @"R", @"G", @"Y", @"O", @"B"};
    static NSString* const identifiers[6] = {
        @"reviewColorWhite", @"reviewColorRed", @"reviewColorGreen",
        @"reviewColorYellow", @"reviewColorOrange", @"reviewColorBlue"
    };
    for (int i = 0; i < NUM_COLORS; ++i) {
        NSButton* swatch = [NSButton buttonWithTitle:names[i] target:self
                                              action:@selector(onPaletteClicked:)];
        swatch.tag = i;
        swatch.bordered = NO;
        swatch.wantsLayer = YES;
        swatch.layer.cornerRadius = 6.0;
        swatch.layer.borderWidth = 1.0;
        swatch.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.22].CGColor;
        swatch.layer.backgroundColor = [RubikColorClassifier nsColorForIndex:i].CGColor;
        swatch.font = [NSFont systemFontOfSize:11 weight:NSFontWeightBold];
        swatch.contentTintColor = (i == COLOR_WHITE || i == COLOR_YELLOW)
            ? [NSColor blackColor] : [NSColor whiteColor];
        swatch.accessibilityIdentifier = identifiers[i];
        swatch.enabled = NO;
        _paletteButtons[i] = swatch;
        [_reviewPanel addSubview:swatch];
    }

    _rotateLabel = RubikLabel(@"Rotate:", 11, NSFontWeightMedium,
                              [NSColor colorWithWhite:0.62 alpha:1.0]);
    [_reviewPanel addSubview:_rotateLabel];

    _rotateFacePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_rotateFacePopup addItemsWithTitles:@[@"U", @"R", @"F", @"D", @"L", @"B"]];
    _rotateFacePopup.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _rotateFacePopup.accessibilityIdentifier = @"reviewRotateFacePopup";
    [_reviewPanel addSubview:_rotateFacePopup];

    _rotateButton = [self makeButton:@"Rotate 90°" action:@selector(onRotateFace:)
                        identifier:@"reviewRotateButton" prominent:NO];
    _rotateButton.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    [_reviewPanel addSubview:_rotateButton];

    _rescanButton = [self makeButton:@"Rescan All" action:@selector(onRescanAll:)
                        identifier:@"reviewRescanButton" prominent:NO];
    [_reviewPanel addSubview:_rescanButton];

    _undoFaceButton = [self makeButton:@"Undo Last Face" action:@selector(onUndoFace:)
                          identifier:@"reviewUndoFaceButton" prominent:NO];
    [_reviewPanel addSubview:_undoFaceButton];

    _acceptButton = [self makeButton:@"Use This Cube" action:@selector(onAcceptReview:)
                        identifier:@"reviewAcceptButton" prominent:YES];
    _acceptButton.enabled = NO;
    [_reviewPanel addSubview:_acceptButton];
}

#pragma mark - Layout

- (void)layout {
    [super layout];
    [self layoutControls];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self layoutControls];
}

- (void)layoutControls {
    const NSRect bounds = self.bounds;
    _videoContainer.frame = bounds;
    if (_cameraCapture.previewLayer) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _cameraCapture.previewLayer.frame = _videoContainer.bounds;
        [CATransaction commit];
    }
    _gridOverlay.frame = bounds;

    _gridRect = [RubikCameraGeometry squareGridRectInBounds:bounds
                                                   fraction:0.58
                                                    minSide:220
                                              centerOffsetY:8];
    _gridOverlay.gridRect = _gridRect;

    const CGFloat pillWidth = std::min<CGFloat>(600, bounds.size.width - 120);
    _instructionPill.frame = NSMakeRect((bounds.size.width - pillWidth) / 2.0,
                                        bounds.size.height - 60, pillWidth, 36);
    _instructionLabel.frame = NSMakeRect(14, 8, pillWidth - 28, 20);
    _statusLabel.frame = NSMakeRect(40, bounds.size.height - 88, bounds.size.width - 80, 18);

    _closeButton.frame = NSMakeRect(bounds.size.width - 48, bounds.size.height - 52, 30, 30);

    const CGFloat bottom = 22;
    const CGFloat captureWidth = 160;
    const CGFloat secondaryWidth = 104;
    const CGFloat spacing = 10;
    const CGFloat total = captureWidth + 2 * secondaryWidth + 2 * spacing;
    const CGFloat startX = (bounds.size.width - total) / 2.0;
    _undoButton.frame = NSMakeRect(startX, bottom, secondaryWidth, 36);
    _captureButton.frame = NSMakeRect(startX + secondaryWidth + spacing, bottom, captureWidth, 36);
    _resetButton.frame = NSMakeRect(startX + secondaryWidth + captureWidth + 2 * spacing,
                                    bottom, secondaryWidth, 36);
    _progressLabel.frame = NSMakeRect((bounds.size.width - 220) / 2.0, bottom + 46, 220, 16);

    const CGFloat errorWidth = std::min<CGFloat>(440, bounds.size.width - 60);
    const CGFloat errorHeight = 250;
    _errorPanel.frame = NSMakeRect((bounds.size.width - errorWidth) / 2.0,
                                   (bounds.size.height - errorHeight) / 2.0,
                                   errorWidth, errorHeight);
    _errorTitle.frame = NSMakeRect(24, errorHeight - 50, errorWidth - 48, 24);
    _errorTitle.alignment = NSTextAlignmentCenter;
    _errorMessage.frame = NSMakeRect(32, 92, errorWidth - 64, 90);
    _retryButton.frame = NSMakeRect(errorWidth / 2.0 - 112, 28, 104, 34);
    _settingsButton.frame = NSMakeRect(errorWidth / 2.0 + 8, 28, 120, 34);

    [self layoutReviewPanel];
    [_gridOverlay setNeedsDisplay:YES];
}

- (void)layoutReviewPanel {
    _reviewPanel.frame = NSInsetRect(self.bounds, 12, 12);
    const CGFloat width = _reviewPanel.bounds.size.width;
    const CGFloat height = _reviewPanel.bounds.size.height;

    _reviewTitle.frame = NSMakeRect(26, height - 46, width - 52, 28);
    _reviewSubtitle.frame = NSMakeRect(26, height - 82, width - 52, 30);

    _reviewNet.frame = NSMakeRect(18, 112, width - 36, std::max<CGFloat>(220, height - 206));

    _paletteLabel.frame = NSMakeRect(26, 76, 52, 18);
    CGFloat x = 80;
    for (int i = 0; i < NUM_COLORS; ++i) {
        _paletteButtons[i].frame = NSMakeRect(x, 71, 38, 28);
        x += 44;
    }

    _rotateLabel.frame = NSMakeRect(width - 260, 76, 48, 18);
    _rotateFacePopup.frame = NSMakeRect(width - 208, 71, 62, 28);
    _rotateButton.frame = NSMakeRect(width - 138, 71, 112, 28);

    _rescanButton.frame = NSMakeRect(26, 22, 118, 34);
    _undoFaceButton.frame = NSMakeRect(154, 22, 138, 34);
    _acceptButton.frame = NSMakeRect(width - 168, 22, 142, 34);
}

#pragma mark - State

- (NSUInteger)currentFaceIndex {
    return _scanSession.capturedFaceCount;
}

- (void)updateInstruction {
    const NSUInteger count = _scanSession.capturedFaceCount;
    _progressLabel.stringValue = [NSString stringWithFormat:@"%lu / 6 faces",
                                  (unsigned long)count];
    _undoButton.enabled = count > 0;
    if (count == 0) {
        _instructionLabel.stringValue = @"Scan the first face — any face, any rotation";
    } else if (count < 6) {
        _instructionLabel.stringValue = [NSString stringWithFormat:
            @"Captured %lu of 6 — scan another face", (unsigned long)count];
    } else {
        _instructionLabel.stringValue = @"All six faces captured — review the net";
    }
    [self updateProgressAccessibility];
}

- (void)updateProgressAccessibility {
    _progressLabel.accessibilityValue = _progressLabel.stringValue;
}

- (void)setStatus:(NSString*)message color:(NSColor*)color {
    _statusLabel.stringValue = message ?: @"";
    _statusLabel.textColor = color ?: [NSColor colorWithWhite:0.82 alpha:1.0];
    _statusLabel.accessibilityValue = message ?: @"";
}

- (void)showCameraError:(NSError*)error {
    _cameraStarting = NO;
    _errorPanel.hidden = NO;
    _cameraCapture.delegate = self;
    _errorTitle.stringValue = @"Camera unavailable";
    _errorMessage.stringValue = error.localizedDescription ?: @"The camera could not be started.";
    _errorPanel.accessibilityValue = _errorMessage.stringValue;
    _gridOverlay.cameraRunning = NO;
    [self setStatus:_errorMessage.stringValue color:RubikDangerColor()];
    [self addSubview:_errorPanel positioned:NSWindowAbove relativeTo:nil];
}

- (void)hideCameraError {
    _errorPanel.hidden = YES;
}

#pragma mark - Public actions

- (void)startScanning {
    [self hideCameraError];
    _reviewPanel.hidden = YES;
    _reviewVisible = NO;
    _cameraStarting = YES;
    _gridOverlay.cameraRunning = NO;
    [self setStatus:@"Requesting camera access…" color:[NSColor colorWithWhite:0.82 alpha:1.0]];
    __weak __typeof__(self) weakSelf = self;
    [_cameraCapture startCameraCaptureWithCompletion:^(BOOL started, NSError* error) {
        __typeof__(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_cameraStarting = NO;
        if (!started) {
            [strongSelf showCameraError:error ?: [NSError errorWithDomain:RubikCameraErrorDomain
                                                                    code:RubikCameraErrorRuntime
                                                                userInfo:@{NSLocalizedDescriptionKey:
                                                                    @"The camera could not be started."}]];
        } else {
            [strongSelf hideCameraError];
            strongSelf->_gridOverlay.cameraRunning = YES;
            [strongSelf setStatus:@"Camera ready — fill the grid with one face"
                            color:[NSColor colorWithWhite:0.82 alpha:1.0]];
        }
    }];
}

- (void)stopScanning {
    _cameraStarting = NO;
    [_cameraCapture stopCameraCapture];
    _gridOverlay.cameraRunning = NO;
}

- (void)resetScan {
    [_scanSession reset];
    _latestReadings.clear();
    _currentPatches.clear();
    _gridOverlay.patches.clear();
    _reviewPanel.hidden = YES;
    _reviewVisible = NO;
    _selectedReviewIndex = -1;
    [self updateInstruction];
    [self setStatus:@"Scan reset. Capture six faces in any order."
             color:[NSColor colorWithWhite:0.82 alpha:1.0]];
    [_gridOverlay setNeedsDisplay:YES];
}

- (void)captureCurrentFace {
    if (_cameraStarting) {
        [self setStatus:@"The camera is still starting…" color:RubikWarnColor()];
        return;
    }
    if (_latestReadings.size() != 9) {
        [self setStatus:@"No frame yet — make sure the camera is running and a face fills the grid."
                 color:RubikWarnColor()];
        NSBeep();
        return;
    }

    NSError* error = nil;
    if (![_scanSession addFaceFromReadings:_latestReadings error:&error]) {
        [self setStatus:error.localizedDescription ?: @"That face could not be captured."
                 color:RubikDangerColor()];
        NSBeep();
        return;
    }

    const NSUInteger count = _scanSession.capturedFaceCount;
    const uint8_t center = _scanSession.capturedFaceCount > 0
        ? [_scanSession centerColorForCapturedFace:static_cast<NSInteger>(count - 1)]
        : 255;
    NSString* colorName = center < NUM_COLORS
        ? [RubikColorClassifier colorNameForIndex:center]
        : @"face";
    _latestReadings.clear();
    _currentPatches.clear();
    _gridOverlay.patches.clear();

    [self updateInstruction];
    if (_scanSession.hasAllFaces) {
        [self showReview];
    } else {
        [self setStatus:[NSString stringWithFormat:@"Captured the %@ (%lu/6). Scan any other face.",
                                                   colorName, (unsigned long)count]
                 color:RubikSuccessColor()];
    }
    [_gridOverlay setNeedsDisplay:YES];
}

- (BOOL)addSyntheticFaceReadings:(const std::vector<RubikColorReading>&)readings {
    NSError* error = nil;
    if (![_scanSession addFaceFromReadings:readings error:&error]) {
        [self setStatus:error.localizedDescription ?: @"Synthetic face rejected."
                 color:RubikDangerColor()];
        return NO;
    }
    [self updateInstruction];
    if (_scanSession.hasAllFaces) [self showReview];
    return YES;
}

#pragma mark - Review

- (void)showReview {
    _reviewVisible = YES;
    _reviewPanel.hidden = NO;
    _reviewNet.selectedIndex = -1;
    _selectedReviewIndex = -1;
    [self refreshReview];
    [self addSubview:_reviewPanel positioned:NSWindowAbove relativeTo:nil];
    NSAccessibilityPostNotification(_reviewPanel, NSAccessibilityCreatedNotification);
}

- (void)refreshReview {
    [_reviewNet setFacelets:_scanSession.facelets
               confidences:_scanSession.confidences
                 reliable:_scanSession.reliableFlags];

    RubikValidationResult validation = _scanSession.validation;
    if (_scanSession.valid) {
        _reviewSubtitle.stringValue = @"Cube validated. Correct any sticker you disagree with, then use it.";
        _reviewSubtitle.textColor = RubikSuccessColor();
    } else if (_scanSession.manualEdits) {
        NSString* message = [NSString stringWithUTF8String:validation.message.c_str()];
        _reviewSubtitle.stringValue = message.length > 0
            ? [NSString stringWithFormat:@"Not solvable yet — %@", message]
            : @"Not solvable yet. Tap a sticker, then choose its colour.";
        _reviewSubtitle.textColor = RubikWarnColor();
    } else {
        NSString* message = [NSString stringWithUTF8String:validation.message.c_str()];
        _reviewSubtitle.stringValue = message.length > 0
            ? [NSString stringWithFormat:@"Review the illuminated stickers — %@", message]
            : @"Review every sticker. Tap one, then choose the correct colour from the palette.";
        _reviewSubtitle.textColor = [NSColor colorWithWhite:0.78 alpha:1.0];
    }
    _acceptButton.enabled = _scanSession.valid;
    for (int i = 0; i < NUM_COLORS; ++i) _paletteButtons[i].enabled = NO;
}

- (void)onReviewStickerSelected:(NSInteger)index {
    _selectedReviewIndex = index;
    const BOOL editable = index >= 0 && index % 9 != 4;
    for (int i = 0; i < NUM_COLORS; ++i) _paletteButtons[i].enabled = editable;
    if (editable) {
        [self setStatus:@"Choose the correct colour for the selected sticker."
                 color:[NSColor colorWithWhite:0.82 alpha:1.0]];
    }
}

- (void)onPaletteClicked:(NSButton*)sender {
    if (_selectedReviewIndex < 0) return;
    [_scanSession setFacelet:static_cast<uint8_t>(sender.tag) atIndex:_selectedReviewIndex];
    [_reviewNet setFacelets:_scanSession.facelets
               confidences:_scanSession.confidences
                 reliable:_scanSession.reliableFlags];
    _acceptButton.enabled = _scanSession.valid;
    if (_scanSession.valid) {
        _reviewSubtitle.stringValue = @"Cube validated. Correct any sticker you disagree with, then use it.";
        _reviewSubtitle.textColor = RubikSuccessColor();
    } else {
        RubikValidationResult validation = _scanSession.validation;
        _reviewSubtitle.stringValue = [NSString stringWithFormat:@"Not solvable yet — %s",
                                                                   validation.message.c_str()];
        _reviewSubtitle.textColor = RubikWarnColor();
    }
}

- (void)onRotateFace:(id)sender {
    const NSInteger face = _rotateFacePopup.indexOfSelectedItem;
    [_scanSession rotateFace:face clockwise:YES];
    [_reviewNet setFacelets:_scanSession.facelets
               confidences:_scanSession.confidences
                 reliable:_scanSession.reliableFlags];
    RubikValidationResult validation = _scanSession.validation;
    _acceptButton.enabled = _scanSession.valid;
    _reviewSubtitle.stringValue = _scanSession.valid
        ? @"Face rotated. The cube is valid."
        : [NSString stringWithFormat:@"Face rotated — %s", validation.message.c_str()];
    _reviewSubtitle.textColor = _scanSession.valid ? RubikSuccessColor() : RubikWarnColor();
}

- (void)onRescanAll:(id)sender {
    [self resetScan];
}

- (void)onUndoFace:(id)sender {
    [_scanSession removeLastFace];
    _reviewPanel.hidden = YES;
    _reviewVisible = NO;
    [self updateInstruction];
    [self setStatus:[NSString stringWithFormat:@"Removed a face. %lu/6 captured.",
                                               (unsigned long)_scanSession.capturedFaceCount]
             color:[NSColor colorWithWhite:0.82 alpha:1.0]];
}

- (void)onAcceptReview:(id)sender {
    if (!_scanSession.valid) {
        NSBeep();
        return;
    }
    RubikCube cube = _scanSession.cube;
    [self stopScanning];
    _reviewPanel.hidden = YES;
    _reviewVisible = NO;
    if ([self.delegate respondsToSelector:@selector(cameraOverlayDidFinishAllFaces:)]) {
        [self.delegate cameraOverlayDidFinishAllFaces:cube];
    }
}

- (void)onCloseClicked:(id)sender {
    [self stopScanning];
    if ([self.delegate respondsToSelector:@selector(cameraOverlayDidCancel)]) {
        [self.delegate cameraOverlayDidCancel];
    }
}

- (void)onRetryCamera:(id)sender {
    [self startScanning];
}

- (void)onOpenCameraSettings:(id)sender {
    NSURL* url = [NSURL URLWithString:
        @"x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

#pragma mark - Camera delegate

- (void)cameraCaptureDidOutputPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!pixelBuffer || _reviewVisible) return;

    const CFTimeInterval now = CACurrentMediaTime();
    if (now - _lastSampleTime < 0.08) return;
    _lastSampleTime = now;

    CVPixelBufferRetain(pixelBuffer);
    __weak __typeof__(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __typeof__(self) strongSelf = weakSelf;
        if (!strongSelf) {
            CVPixelBufferRelease(pixelBuffer);
            return;
        }
        const CGSize content = CGSizeMake(CVPixelBufferGetWidth(pixelBuffer),
                                           CVPixelBufferGetHeight(pixelBuffer));
        strongSelf->_bufferSize = content;
        const CGRect roi = [RubikCameraGeometry normalizedROIForViewRect:strongSelf->_gridRect
                                                              contentSize:content
                                                                 inBounds:strongSelf.bounds];
        std::vector<RubikColorReading> readings =
            [strongSelf->_classifier readingsFromPixelBuffer:pixelBuffer normalizedROI:roi];
        CVPixelBufferRelease(pixelBuffer);
        if (readings.size() != 9) return;

        std::vector<SampledPatch> patches;
        patches.reserve(9);
        for (const RubikColorReading& reading : readings) {
            SampledPatch patch;
            patch.colorIndex = reading.colorIndex;
            patch.r = reading.r;
            patch.g = reading.g;
            patch.b = reading.b;
            patch.h = reading.h;
            patch.s = reading.s;
            patch.v = reading.v;
            patch.labL = reading.lab.L;
            patch.labA = reading.lab.a;
            patch.labB = reading.lab.b;
            patch.confidence = reading.confidence;
            patch.reliable = reading.reliable;
            patch.background = reading.background;
            patches.push_back(patch);
        }

        strongSelf->_latestReadings = readings;
        strongSelf->_currentPatches = patches;
        strongSelf->_gridOverlay.patches = patches;
        [strongSelf->_gridOverlay setNeedsDisplay:YES];

        if (!strongSelf->_scanSession.hasAllFaces && !strongSelf->_cameraStarting) {
            int reliable = 0;
            for (const auto& patch : patches) if (patch.reliable) ++reliable;
            if (reliable >= 7) {
                [strongSelf setStatus:@"Good lighting — capture when the grid is aligned."
                                color:[NSColor colorWithWhite:0.82 alpha:1.0]];
            }
        }
    });
}

- (void)cameraCaptureDidFailWithError:(NSError*)error {
    [self showCameraError:error];
}

- (void)cameraCaptureDidChangeRunning:(BOOL)running {
    _gridOverlay.cameraRunning = running;
    if (running) {
        [self hideCameraError];
        [self setStatus:@"Camera ready — fill the grid with one face"
                 color:[NSColor colorWithWhite:0.82 alpha:1.0]];
    } else if (!_cameraStarting) {
        [self setStatus:@"Camera is off." color:[NSColor colorWithWhite:0.65 alpha:1.0]];
    }
}

@end
