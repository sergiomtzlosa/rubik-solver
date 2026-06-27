//
//  RubikFaceUploadSheetController.mm
//  RubikSolver - 6-Face Photo Upload & Recognition Sheet
//

#import "RubikFaceUploadSheetController.h"
#import "RubikColorClassifier.h"
#import "RubikCube.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <QuartzCore/QuartzCore.h>
#include <algorithm>
#include <cmath>
#include <vector>
#include <string>

@protocol RubikFaceImagePreviewDelegate <NSObject>
- (void)previewViewDidUpdateROI:(CGRect)normalizedROI;
@end

#pragma mark - RubikFaceImagePreviewView (Image Overlap UI for Fine Adjustment)

@interface RubikFaceImagePreviewView : NSView
@property (nonatomic, weak) id<RubikFaceImagePreviewDelegate> delegate;
@property (nonatomic, strong) NSImage* image;
@property (nonatomic, assign) std::vector<SampledPatch> patches;
@property (nonatomic, assign) CGRect normalizedROI;

- (void)resetDefaultROI;
- (void)setGridScale:(CGFloat)scale;
@end

@implementation RubikFaceImagePreviewView {
    BOOL _isPanning;
    BOOL _isResizing;
    NSPoint _dragStartPoint;
    CGRect _startROI;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _normalizedROI = CGRectMake(0.12, 0.12, 0.76, 0.76);
        _isPanning = NO;
        _isResizing = NO;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)resetDefaultROI {
    if (!_image) {
        _normalizedROI = CGRectMake(0.12, 0.12, 0.76, 0.76);
        [self setNeedsDisplay:YES];
        return;
    }

    NSSize imgSize = _image.size;
    if (imgSize.width <= 0 || imgSize.height <= 0) return;
    CGFloat minDim = std::min(imgSize.width, imgSize.height);

    CGFloat normW = (minDim * 0.76) / imgSize.width;
    CGFloat normH = (minDim * 0.76) / imgSize.height;
    CGFloat normX = (1.0 - normW) / 2.0;
    CGFloat normY = (1.0 - normH) / 2.0;

    _normalizedROI = CGRectMake(normX, normY, normW, normH);
    [self setNeedsDisplay:YES];
}

- (void)setGridScale:(CGFloat)scale {
    if (!_image) return;
    NSSize imgSize = _image.size;
    if (imgSize.width <= 0 || imgSize.height <= 0) return;
    CGFloat minDim = std::min(imgSize.width, imgSize.height);
    CGFloat targetPixelSize = minDim * scale;

    CGFloat normW = targetPixelSize / imgSize.width;
    CGFloat normH = targetPixelSize / imgSize.height;

    CGFloat cx = _normalizedROI.origin.x + _normalizedROI.size.width / 2.0;
    CGFloat cy = _normalizedROI.origin.y + _normalizedROI.size.height / 2.0;

    CGFloat newX = std::max(0.0, std::min(1.0 - normW, cx - normW / 2.0));
    CGFloat newY = std::max(0.0, std::min(1.0 - normH, cy - normH / 2.0));

    _normalizedROI = CGRectMake(newX, newY, normW, normH);
    [self setNeedsDisplay:YES];
    [self.delegate previewViewDidUpdateROI:_normalizedROI];
}

- (NSRect)calculateImageDrawRect {
    if (!_image) return self.bounds;
    NSSize imgSize = _image.size;
    if (imgSize.width <= 0 || imgSize.height <= 0) return self.bounds;

    NSRect bounds = self.bounds;
    CGFloat scaleX = bounds.size.width / imgSize.width;
    CGFloat scaleY = bounds.size.height / imgSize.height;
    CGFloat scale = std::min(scaleX, scaleY);

    CGFloat drawW = imgSize.width * scale;
    CGFloat drawH = imgSize.height * scale;
    CGFloat drawX = (bounds.size.width - drawW) / 2.0;
    CGFloat drawY = (bounds.size.height - drawH) / 2.0;

    return NSMakeRect(drawX, drawY, drawW, drawH);
}

- (NSRect)calculateViewROIRectWithImageRect:(NSRect)imageRect {
    CGFloat rx = imageRect.origin.x + _normalizedROI.origin.x * imageRect.size.width;
    CGFloat ry = imageRect.origin.y + _normalizedROI.origin.y * imageRect.size.height;
    CGFloat rw = _normalizedROI.size.width * imageRect.size.width;
    CGFloat rh = _normalizedROI.size.height * imageRect.size.height;
    return NSMakeRect(rx, ry, rw, rh);
}

#pragma mark - Mouse Events (Drag to Move / Corner to Scale)

- (void)mouseDown:(NSEvent *)event {
    NSPoint pt = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect imageRect = [self calculateImageDrawRect];
    NSRect roiRect = [self calculateViewROIRectWithImageRect:imageRect];

    NSRect resizeHandle = NSMakeRect(NSMaxX(roiRect) - 24, NSMaxY(roiRect) - 24, 28, 28);
    if (NSPointInRect(pt, resizeHandle)) {
        _isResizing = YES;
        _isPanning = NO;
        _dragStartPoint = pt;
        _startROI = _normalizedROI;
        return;
    }

    if (NSPointInRect(pt, roiRect)) {
        _isPanning = YES;
        _isResizing = NO;
        _dragStartPoint = pt;
        _startROI = _normalizedROI;
        return;
    }

    [super mouseDown:event];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_isPanning && !_isResizing) {
        [super mouseDragged:event];
        return;
    }

    NSPoint pt = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect imageRect = [self calculateImageDrawRect];
    if (imageRect.size.width <= 0 || imageRect.size.height <= 0) return;

    CGFloat dx = (pt.x - _dragStartPoint.x) / imageRect.size.width;
    CGFloat dy = (pt.y - _dragStartPoint.y) / imageRect.size.height;

    if (_isPanning) {
        CGRect newROI = _startROI;
        newROI.origin.x = std::max(0.0, std::min(1.0 - newROI.size.width, _startROI.origin.x + dx));
        newROI.origin.y = std::max(0.0, std::min(1.0 - newROI.size.height, _startROI.origin.y + dy));
        _normalizedROI = newROI;
        [self setNeedsDisplay:YES];
        [self.delegate previewViewDidUpdateROI:_normalizedROI];
    } else if (_isResizing) {
        if (!_image) return;
        NSSize imgSize = _image.size;
        CGFloat delta = std::max(dx, dy);

        CGFloat newW = std::max(0.15, std::min(1.0 - _startROI.origin.x, _startROI.size.width + delta));
        CGFloat pixelW = newW * imgSize.width;
        CGFloat newH = pixelW / imgSize.height;

        if (_startROI.origin.y + newH > 1.0) {
            newH = 1.0 - _startROI.origin.y;
            newW = (newH * imgSize.height) / imgSize.width;
        }

        _normalizedROI.size.width = newW;
        _normalizedROI.size.height = newH;
        [self setNeedsDisplay:YES];
        [self.delegate previewViewDidUpdateROI:_normalizedROI];
    }
}

- (void)mouseUp:(NSEvent *)event {
    _isPanning = NO;
    _isResizing = NO;
    [super mouseUp:event];
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    [[NSColor colorWithCalibratedRed:0.08 green:0.09 blue:0.11 alpha:1.0] setFill];
    NSRectFill(self.bounds);

    NSRect imageRect = [self calculateImageDrawRect];

    if (_image) {
        [_image drawInRect:imageRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    }

    NSRect roiRect = [self calculateViewROIRectWithImageRect:imageRect];

    // Dim mask outside ROI
    NSBezierPath* dimPath = [NSBezierPath bezierPathWithRect:imageRect];
    [dimPath appendBezierPath:[NSBezierPath bezierPathWithRoundedRect:roiRect xRadius:8 yRadius:8]];
    dimPath.windingRule = NSWindingRuleEvenOdd;
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.45] setFill];
    [dimPath fill];

    // Draw the 3x3 grid cells
    CGFloat cellW = roiRect.size.width / 3.0;
    CGFloat cellH = roiRect.size.height / 3.0;

    for (int row = 0; row < 3; row++) {
        for (int col = 0; col < 3; col++) {
            NSRect cellRect = NSMakeRect(roiRect.origin.x + col * cellW + 3,
                                         roiRect.origin.y + row * cellH + 3,
                                         cellW - 6,
                                         cellH - 6);

            NSBezierPath* cellPath = [NSBezierPath bezierPathWithRoundedRect:cellRect xRadius:6 yRadius:6];

            int idx = row * 3 + col;
            if (idx < (int)_patches.size()) {
                uint8_t c = _patches[idx].colorIndex;
                NSColor* colr = [RubikColorClassifier nsColorForIndex:c];
                [[colr colorWithAlphaComponent:0.75] setFill];
                [cellPath fill];

                [colr setStroke];
                cellPath.lineWidth = 2.0;
                [cellPath stroke];

                // Center dot
                NSPoint centerPt = NSMakePoint(NSMidX(cellRect), NSMidY(cellRect));
                NSBezierPath* dotPath = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(centerPt.x - 3, centerPt.y - 3, 6, 6)];
                [[NSColor colorWithCalibratedWhite:(c == COLOR_WHITE || c == COLOR_YELLOW) ? 0.2 : 1.0 alpha:0.85] setFill];
                [dotPath fill];

                // Letter label
                static const char* letters = "WRGYOB";
                NSString* lStr = [NSString stringWithFormat:@"%c", letters[c < 6 ? c : 0]];
                NSDictionary* attrs = @{
                    NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightBold],
                    NSForegroundColorAttributeName: (c == COLOR_WHITE || c == COLOR_YELLOW) ? [NSColor blackColor] : [NSColor whiteColor]
                };
                NSSize sSz = [lStr sizeWithAttributes:attrs];
                NSRect tRect = NSMakeRect(centerPt.x - sSz.width / 2.0,
                                          centerPt.y - sSz.height / 2.0 - 10,
                                          sSz.width, sSz.height);
                [lStr drawInRect:tRect withAttributes:attrs];
            }
        }
    }

    // Outer grid border
    NSBezierPath* outer = [NSBezierPath bezierPathWithRoundedRect:roiRect xRadius:10 yRadius:10];
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.95] setStroke];
    outer.lineWidth = 2.5;
    [outer stroke];

    // Corner resize handle (bottom-right)
    NSRect rHandle = NSMakeRect(NSMaxX(roiRect) - 16, NSMaxY(roiRect) - 16, 12, 12);
    NSBezierPath* hPath = [NSBezierPath bezierPath];
    [hPath moveToPoint:NSMakePoint(NSMinX(rHandle), NSMaxY(rHandle))];
    [hPath lineToPoint:NSMakePoint(NSMaxX(rHandle), NSMaxY(rHandle))];
    [hPath lineToPoint:NSMakePoint(NSMaxX(rHandle), NSMinY(rHandle))];
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.95] setStroke];
    hPath.lineWidth = 3.0;
    [hPath stroke];
}

@end

#pragma mark - RubikDashedDropView (Empty Drop Target Area)

@interface RubikDashedDropView : NSView
@property (nonatomic, assign) BOOL isHighlighted;
@end

@implementation RubikDashedDropView

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect r = NSInsetRect(self.bounds, 2, 2);
    NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:r xRadius:8 yRadius:8];

    CGFloat dashPattern[] = {6.0, 4.0};
    [path setLineDash:dashPattern count:2 phase:0.0];
    path.lineWidth = 1.5;

    if (_isHighlighted) {
        [[NSColor systemBlueColor] setStroke];
        [[NSColor colorWithCalibratedRed:0.1 green:0.3 blue:0.6 alpha:0.25] setFill];
        [path fill];
    } else {
        [[NSColor colorWithCalibratedWhite:0.35 alpha:0.8] setStroke];
        [[NSColor colorWithCalibratedWhite:0.10 alpha:0.4] setFill];
        [path fill];
    }
    [path stroke];
}

- (void)setIsHighlighted:(BOOL)highlighted {
    if (_isHighlighted != highlighted) {
        _isHighlighted = highlighted;
        [self setNeedsDisplay:YES];
    }
}

@end

#pragma mark - RubikFaceCardView (Card Representing 1 of the 6 Faces)

@class RubikFaceCardView;

@protocol RubikFaceCardDelegate <NSObject>
- (void)faceCardDidRequestChooseImage:(RubikFaceCardView*)card;
- (void)faceCardDidRequestEdit:(RubikFaceCardView*)card;
- (void)faceCardDidRequestRotate:(RubikFaceCardView*)card;
- (void)faceCardDidRequestClear:(RubikFaceCardView*)card;
- (void)faceCard:(RubikFaceCardView*)card didDropImage:(NSImage*)image;
- (void)faceCard:(RubikFaceCardView*)card didChangeFacelet:(int)stickerIdx toColor:(uint8_t)color;
@end

@interface RubikFaceCardView : NSView <NSDraggingDestination>
@property (nonatomic, weak) id<RubikFaceCardDelegate> delegate;
@property (nonatomic, assign) int faceIndex;
@property (nonatomic, strong) NSImage* image;
@property (nonatomic, assign) std::vector<uint8_t> facelets;
@property (nonatomic, assign) CGRect normalizedROI;
@property (nonatomic, assign) BOOL isUploaded;

- (instancetype)initWithFrame:(NSRect)frameRect faceIndex:(int)faceIndex;
- (void)setUploadedImage:(NSImage*)image facelets:(const std::vector<uint8_t>&)facelets roi:(CGRect)roi;
- (void)clearUploadedFace;
- (void)rotateFaceletsCW;
- (void)updateMiniGridDisplay;
@end

@implementation RubikFaceCardView {
    NSView* _colorBadge;
    NSTextField* _titleLabel;
    NSTextField* _subLabel;
    NSTextField* _statusBadge;

    RubikDashedDropView* _emptyDropView;
    NSButton* _btnChooseEmpty;

    NSView* _uploadedContainer;
    NSImageView* _thumbView;
    NSMutableArray<NSButton*>* _miniGridButtons;
    NSButton* _btnChange;
    NSButton* _btnAdjust;
    NSButton* _btnRotate;
    NSButton* _btnClear;
}

- (instancetype)initWithFrame:(NSRect)frameRect faceIndex:(int)faceIndex {
    self = [super initWithFrame:frameRect];
    if (self) {
        _faceIndex = faceIndex;
        _facelets.resize(9, (uint8_t)faceIndex);
        _normalizedROI = CGRectMake(0.12, 0.12, 0.76, 0.76);
        _isUploaded = NO;

        self.wantsLayer = YES;
        self.layer.cornerRadius = 10;
        self.layer.masksToBounds = YES;
        self.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.15 alpha:0.9].CGColor;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [NSColor colorWithCalibratedWhite:0.25 alpha:1.0].CGColor;

        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
        [self setupSubviews];
    }
    return self;
}

- (BOOL)isFlipped {
    return NO;
}

- (void)setupSubviews {
    static const char* faceNames[6] = {"Top Face (U)", "Right Face (R)", "Front Face (F)", "Down Face (D)", "Left Face (L)", "Back Face (B)"};
    static const char* centerColorNames[6] = {"White Center", "Red Center", "Green Center", "Yellow Center", "Orange Center", "Blue Center"};

    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;

    // Header Color Badge
    _colorBadge = [[NSView alloc] initWithFrame:NSMakeRect(12, h - 32, 16, 16)];
    _colorBadge.wantsLayer = YES;
    _colorBadge.layer.cornerRadius = 4;
    _colorBadge.layer.backgroundColor = [RubikColorClassifier nsColorForIndex:_faceIndex].CGColor;
    _colorBadge.layer.borderWidth = 1.0;
    _colorBadge.layer.borderColor = [NSColor colorWithCalibratedWhite:0.4 alpha:1.0].CGColor;
    [self addSubview:_colorBadge];

    // Header Title
    _titleLabel = [NSTextField labelWithString:[NSString stringWithUTF8String:faceNames[_faceIndex]]];
    _titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightBold];
    _titleLabel.textColor = [NSColor whiteColor];
    _titleLabel.frame = NSMakeRect(34, h - 33, 140, 18);
    [self addSubview:_titleLabel];

    // Header Subtitle (Center Color)
    _subLabel = [NSTextField labelWithString:[NSString stringWithUTF8String:centerColorNames[_faceIndex]]];
    _subLabel.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
    _subLabel.textColor = [NSColor colorWithCalibratedWhite:0.75 alpha:1.0];
    _subLabel.frame = NSMakeRect(34, h - 46, 140, 14);
    [self addSubview:_subLabel];

    // Header Status Badge
    _statusBadge = [NSTextField labelWithString:@"Empty"];
    _statusBadge.font = [NSFont systemFontOfSize:10 weight:NSFontWeightBold];
    _statusBadge.alignment = NSTextAlignmentCenter;
    _statusBadge.textColor = [NSColor colorWithCalibratedWhite:0.6 alpha:1.0];
    _statusBadge.wantsLayer = YES;
    _statusBadge.layer.cornerRadius = 9;
    _statusBadge.layer.masksToBounds = YES;
    _statusBadge.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.22 alpha:0.8].CGColor;
    _statusBadge.frame = NSMakeRect(w - 78, h - 34, 66, 18);
    [self addSubview:_statusBadge];

    // ---------------- Empty State Drop View ----------------
    _emptyDropView = [[RubikDashedDropView alloc] initWithFrame:NSMakeRect(12, 12, w - 24, h - 64)];
    [self addSubview:_emptyDropView];

    NSTextField* iconLabel = [NSTextField labelWithString:@"🖼️"];
    iconLabel.font = [NSFont systemFontOfSize:30];
    iconLabel.alignment = NSTextAlignmentCenter;
    iconLabel.frame = NSMakeRect(0, _emptyDropView.bounds.size.height - 56, _emptyDropView.bounds.size.width, 36);
    [_emptyDropView addSubview:iconLabel];

    NSTextField* emptyHint = [NSTextField labelWithString:@"Drop photo or click to upload"];
    emptyHint.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    emptyHint.alignment = NSTextAlignmentCenter;
    emptyHint.textColor = [NSColor colorWithCalibratedWhite:0.75 alpha:1.0];
    emptyHint.frame = NSMakeRect(0, _emptyDropView.bounds.size.height - 82, _emptyDropView.bounds.size.width, 18);
    [_emptyDropView addSubview:emptyHint];

    _btnChooseEmpty = [NSButton buttonWithTitle:@"Choose Photo..." target:self action:@selector(onChooseEmptyClicked:)];
    _btnChooseEmpty.bezelStyle = NSBezelStyleRounded;
    _btnChooseEmpty.frame = NSMakeRect((_emptyDropView.bounds.size.width - 130) / 2, 24, 130, 28);
    _btnChooseEmpty.contentTintColor = [NSColor whiteColor];
    NSMutableAttributedString* attrChoose = [[NSMutableAttributedString alloc] initWithString:@"Choose Photo..."];
    [attrChoose addAttribute:NSForegroundColorAttributeName value:[NSColor whiteColor] range:NSMakeRange(0, attrChoose.length)];
    [attrChoose addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:11 weight:NSFontWeightMedium] range:NSMakeRange(0, attrChoose.length)];
    _btnChooseEmpty.attributedTitle = attrChoose;
    [_emptyDropView addSubview:_btnChooseEmpty];

    // ---------------- Uploaded State Container ----------------
    _uploadedContainer = [[NSView alloc] initWithFrame:NSMakeRect(12, 8, w - 24, h - 58)];
    _uploadedContainer.hidden = YES;
    [self addSubview:_uploadedContainer];

    // Thumbnail Preview (Left)
    _thumbView = [[NSImageView alloc] initWithFrame:NSMakeRect(4, 38, 120, 140)];
    _thumbView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _thumbView.wantsLayer = YES;
    _thumbView.layer.cornerRadius = 8;
    _thumbView.layer.masksToBounds = YES;
    _thumbView.layer.borderWidth = 1.0;
    _thumbView.layer.borderColor = [NSColor colorWithCalibratedWhite:0.3 alpha:1.0].CGColor;
    [_uploadedContainer addSubview:_thumbView];

    // Mini 3x3 Grid (Right)
    _miniGridButtons = [NSMutableArray arrayWithCapacity:9];
    CGFloat gridX = 132;
    CGFloat gridY = 46;
    CGFloat sqSize = 38;
    CGFloat sqGap = 4;

    for (int r = 0; r < 3; r++) {
        for (int c = 0; c < 3; c++) {
            int idx = r * 3 + c;
            NSButton* sqBtn = [NSButton buttonWithTitle:@"" target:self action:@selector(onMiniSquareClicked:)];
            sqBtn.tag = idx;
            sqBtn.bezelStyle = NSBezelStyleRegularSquare;
            sqBtn.bordered = NO;
            sqBtn.wantsLayer = YES;
            sqBtn.layer.cornerRadius = 5;
            sqBtn.font = [NSFont systemFontOfSize:13 weight:NSFontWeightBold];
            // In flipped=NO coordinate system: r=0 is top, r=2 is bottom
            sqBtn.frame = NSMakeRect(gridX + c * (sqSize + sqGap),
                                     gridY + (2 - r) * (sqSize + sqGap),
                                     sqSize, sqSize);
            [_uploadedContainer addSubview:sqBtn];
            [_miniGridButtons addObject:sqBtn];
        }
    }

    // Action Buttons Row (Bottom)
    CGFloat btnY = 6;
    _btnChange = [NSButton buttonWithTitle:@"📷 Change" target:self action:@selector(onChooseEmptyClicked:)];
    _btnChange.bezelStyle = NSBezelStyleInline;
    _btnChange.contentTintColor = [NSColor whiteColor];
    _btnChange.font = [NSFont systemFontOfSize:10.5];
    _btnChange.frame = NSMakeRect(4, btnY, 68, 24);
    [_uploadedContainer addSubview:_btnChange];

    _btnAdjust = [NSButton buttonWithTitle:@"✏️ Adjust" target:self action:@selector(onAdjustClicked:)];
    _btnAdjust.bezelStyle = NSBezelStyleInline;
    _btnAdjust.contentTintColor = [NSColor whiteColor];
    _btnAdjust.font = [NSFont systemFontOfSize:10.5];
    _btnAdjust.frame = NSMakeRect(76, btnY, 68, 24);
    [_uploadedContainer addSubview:_btnAdjust];

    _btnRotate = [NSButton buttonWithTitle:@"↻ 90°" target:self action:@selector(onRotateClicked:)];
    _btnRotate.bezelStyle = NSBezelStyleInline;
    _btnRotate.contentTintColor = [NSColor whiteColor];
    _btnRotate.font = [NSFont systemFontOfSize:10.5];
    _btnRotate.frame = NSMakeRect(148, btnY, 56, 24);
    [_uploadedContainer addSubview:_btnRotate];

    _btnClear = [NSButton buttonWithTitle:@"✕ Clear" target:self action:@selector(onClearClicked:)];
    _btnClear.bezelStyle = NSBezelStyleInline;
    _btnClear.contentTintColor = [NSColor whiteColor];
    _btnClear.font = [NSFont systemFontOfSize:10.5];
    _btnClear.frame = NSMakeRect(208, btnY, 56, 24);
    [_uploadedContainer addSubview:_btnClear];
}

#pragma mark - State Updates

- (void)setUploadedImage:(NSImage*)image facelets:(const std::vector<uint8_t>&)facelets roi:(CGRect)roi {
    _image = image;
    _normalizedROI = roi;
    _isUploaded = YES;

    if (facelets.size() == 9) {
        _facelets = facelets;
    } else {
        _facelets.assign(9, (uint8_t)_faceIndex);
    }

    _thumbView.image = image;
    _emptyDropView.hidden = YES;
    _uploadedContainer.hidden = NO;

    _statusBadge.stringValue = @"✓ Ready";
    _statusBadge.textColor = [NSColor whiteColor];
    _statusBadge.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.12 green:0.55 blue:0.22 alpha:0.9].CGColor;

    [self updateMiniGridDisplay];
}

- (void)clearUploadedFace {
    _image = nil;
    _isUploaded = NO;
    _facelets.assign(9, (uint8_t)_faceIndex);

    _thumbView.image = nil;
    _emptyDropView.hidden = NO;
    _uploadedContainer.hidden = YES;

    _statusBadge.stringValue = @"Empty";
    _statusBadge.textColor = [NSColor colorWithCalibratedWhite:0.6 alpha:1.0];
    _statusBadge.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.22 alpha:0.8].CGColor;
}

- (void)rotateFaceletsCW {
    if (_facelets.size() != 9) return;
    std::vector<uint8_t> rotated(9);
    for (int r = 0; r < 3; r++) {
        for (int c = 0; c < 3; c++) {
            rotated[c * 3 + (2 - r)] = _facelets[r * 3 + c];
        }
    }
    _facelets = rotated;
    [self updateMiniGridDisplay];
}

- (void)updateMiniGridDisplay {
    if (_miniGridButtons.count < 9 || _facelets.size() < 9) return;
    static const char* letters = "WRGYOB";

    for (int i = 0; i < 9; i++) {
        uint8_t color = _facelets[i];
        NSButton* btn = _miniGridButtons[i];
        NSColor* c = [RubikColorClassifier nsColorForIndex:color];
        btn.layer.backgroundColor = c.CGColor;
        btn.layer.borderWidth = 1.0;
        btn.layer.borderColor = [NSColor colorWithCalibratedWhite:0.35 alpha:1.0].CGColor;

        btn.title = [NSString stringWithFormat:@"%c", letters[color < 6 ? color : 0]];
        btn.contentTintColor = (color == COLOR_WHITE || color == COLOR_YELLOW) ? [NSColor blackColor] : [NSColor whiteColor];
    }
}

#pragma mark - Button Actions

- (void)onChooseEmptyClicked:(id)sender {
    if ([self.delegate respondsToSelector:@selector(faceCardDidRequestChooseImage:)]) {
        [self.delegate faceCardDidRequestChooseImage:self];
    }
}

- (void)onAdjustClicked:(id)sender {
    if ([self.delegate respondsToSelector:@selector(faceCardDidRequestEdit:)]) {
        [self.delegate faceCardDidRequestEdit:self];
    }
}

- (void)onRotateClicked:(id)sender {
    [self rotateFaceletsCW];
    if ([self.delegate respondsToSelector:@selector(faceCardDidRequestRotate:)]) {
        [self.delegate faceCardDidRequestRotate:self];
    }
}

- (void)onClearClicked:(id)sender {
    [self clearUploadedFace];
    if ([self.delegate respondsToSelector:@selector(faceCardDidRequestClear:)]) {
        [self.delegate faceCardDidRequestClear:self];
    }
}

- (void)onMiniSquareClicked:(NSButton*)sender {
    NSInteger idx = sender.tag;
    if (idx >= 0 && idx < 9) {
        _facelets[idx] = (_facelets[idx] + 1) % 6;
        [self updateMiniGridDisplay];
        if ([self.delegate respondsToSelector:@selector(faceCard:didChangeFacelet:toColor:)]) {
            [self.delegate faceCard:self didChangeFacelet:(int)idx toColor:_facelets[idx]];
        }
    }
}

#pragma mark - Drag & Drop Destination

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSPasteboard* pboard = [sender draggingPasteboard];
    if ([pboard.types containsObject:NSPasteboardTypeFileURL]) {
        self.layer.borderColor = [NSColor systemBlueColor].CGColor;
        self.layer.borderWidth = 2.5;
        _emptyDropView.isHighlighted = YES;
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    self.layer.borderColor = [NSColor colorWithCalibratedWhite:0.25 alpha:1.0].CGColor;
    self.layer.borderWidth = 1.0;
    _emptyDropView.isHighlighted = NO;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
    return YES;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    self.layer.borderColor = [NSColor colorWithCalibratedWhite:0.25 alpha:1.0].CGColor;
    self.layer.borderWidth = 1.0;
    _emptyDropView.isHighlighted = NO;

    NSPasteboard* pboard = [sender draggingPasteboard];
    if ([pboard.types containsObject:NSPasteboardTypeFileURL]) {
        NSURL* fileURL = [NSURL URLFromPasteboard:pboard];
        if (fileURL) {
            NSImage* img = [[NSImage alloc] initWithContentsOfURL:fileURL];
            if (img && [self.delegate respondsToSelector:@selector(faceCard:didDropImage:)]) {
                [self.delegate faceCard:self didDropImage:img];
                return YES;
            }
        }
    }
    return NO;
}

@end

#pragma mark - RubikFaceUploadSheetController

@interface RubikFaceUploadSheetController () <RubikFaceCardDelegate, RubikFaceImagePreviewDelegate>
@end

@implementation RubikFaceUploadSheetController {
    NSWindow* _sheetWindow;
    NSWindow* _parentWindow;
    RubikColorClassifier* _classifier;
    RubikCube _cubeModel;
    uint8_t _configuredFacesMask;

    RubikCubeUploadCompletion _cubeCompletion;
    RubikFaceUploadCompletion _legacyFaceCompletion;

    // Overview 6-Face UI
    NSView* _overviewView;
    RubikFaceCardView* _faceCards[6];
    NSTextField* _progressLabel;
    NSTextField* _validationLabel;
    NSTextField* _colorCountLabel;
    NSButton* _btnApplyToCube;
    NSButton* _btnApplyAndSolve;

    // Detail Single-Face Editor UI
    NSView* _detailEditorView;
    RubikFaceImagePreviewView* _previewView;
    NSSlider* _sizeSlider;
    NSTextField* _detailTitleLabel;
    NSTextField* _compassTopLabel;
    NSTextField* _compassBottomLabel;
    NSTextField* _compassLeftLabel;
    NSTextField* _compassRightLabel;
    NSMutableArray<NSButton*>* _detailSquareButtons;
    std::vector<uint8_t> _detectedColors;
    NSInteger _selectedSquareIndex;
    int _editingFaceIndex;
}

+ (instancetype)sharedController {
    static RubikFaceUploadSheetController* sInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sInstance = [[RubikFaceUploadSheetController alloc] init];
    });
    return sInstance;
}

#pragma mark - Presentation

- (void)showCubeUploadSheetForWindow:(NSWindow*)parentWindow
                           cubeModel:(const RubikCube&)cubeModel
                          classifier:(RubikColorClassifier*)classifier
                 configuredFacesMask:(uint8_t)configuredFacesMask
                          completion:(RubikCubeUploadCompletion)completion
{
    _parentWindow = parentWindow;
    _cubeModel = cubeModel;
    _classifier = classifier ?: [[RubikColorClassifier alloc] init];
    _configuredFacesMask = configuredFacesMask;
    _cubeCompletion = completion;

    [self createAndPresentSheetWindow];
}

- (void)createAndPresentSheetWindow {
    NSRect frame = NSMakeRect(0, 0, 960, 700);
    _sheetWindow = [[NSWindow alloc] initWithContentRect:frame
                                               styleMask:NSWindowStyleMaskTitled
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
    _sheetWindow.title = @"Rubik's Cube — 6-Face Photo Upload";
    _sheetWindow.backgroundColor = [NSColor colorWithCalibratedRed:0.11 green:0.12 blue:0.15 alpha:1.0];

    [self buildOverviewView];
    [self buildDetailEditorView];

    _sheetWindow.contentView = _overviewView;
    [self updateCubeValidation];

    [_parentWindow beginSheet:_sheetWindow completionHandler:nil];
}

#pragma mark - Build Overview View (6 Cards Layout)

- (void)buildOverviewView {
    _overviewView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 960, 700)];

    // ---------------- Header Row ----------------
    NSTextField* titleLabel = [NSTextField labelWithString:@"📸 Rubik's Cube — 6-Face Photo Upload"];
    titleLabel.font = [NSFont systemFontOfSize:17 weight:NSFontWeightBold];
    titleLabel.textColor = [NSColor whiteColor];
    titleLabel.frame = NSMakeRect(20, 660, 420, 24);
    [_overviewView addSubview:titleLabel];

    NSTextField* subLabel = [NSTextField labelWithString:@"Upload photos for each face of the cube to reconstruct and solve."];
    subLabel.font = [NSFont systemFontOfSize:11.5];
    subLabel.textColor = [NSColor colorWithCalibratedWhite:0.75 alpha:1.0];
    subLabel.frame = NSMakeRect(20, 640, 440, 18);
    [_overviewView addSubview:subLabel];

    // Batch Action Buttons (Top-Right)
    NSButton* btnBatch = [NSButton buttonWithTitle:@"📁 Upload Multiple Images..." target:self action:@selector(onBatchUploadClicked:)];
    btnBatch.bezelStyle = NSBezelStyleRounded;
    btnBatch.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
    btnBatch.toolTip = @"Select all 6 face images at once (PNG, JPG, HEIC). Faces are auto-matched by center color.";
    btnBatch.accessibilityIdentifier = @"batchUploadButton";
    btnBatch.frame = NSMakeRect(480, 644, 185, 30);
    [_overviewView addSubview:btnBatch];

    NSButton* btnSample = [NSButton buttonWithTitle:@"🎲 Load Sample Photos" target:self action:@selector(onLoadSamplePhotosClicked:)];
    btnSample.bezelStyle = NSBezelStyleRounded;
    btnSample.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
    btnSample.toolTip = @"Instantly load bundled test photos for a valid 10-move scramble";
    btnSample.accessibilityIdentifier = @"loadSamplePhotosButton";
    btnSample.frame = NSMakeRect(670, 644, 170, 30);
    [_overviewView addSubview:btnSample];

    NSButton* btnClearAll = [NSButton buttonWithTitle:@"↺ Clear All" target:self action:@selector(onClearAllClicked:)];
    btnClearAll.bezelStyle = NSBezelStyleRounded;
    btnClearAll.font = [NSFont systemFontOfSize:11.5];
    btnClearAll.toolTip = @"Clear all uploaded photos and stickers";
    btnClearAll.frame = NSMakeRect(846, 644, 94, 30);
    [_overviewView addSubview:btnClearAll];

    // ---------------- 6 Face Cards Grid ----------------
    // Row 1 (Top):    Top Face (U), Front Face (F), Right Face (R)
    // Row 2 (Bottom): Down Face (D), Left Face (L), Back Face (B)
    static const int gridFaceMapping[2][3] = {
        {FACE_U, FACE_F, FACE_R},
        {FACE_D, FACE_L, FACE_B}
    };

    CGFloat cardW = 296;
    CGFloat cardH = 254;
    CGFloat gapX = 16;
    CGFloat gapY = 16;
    CGFloat startX = 20;
    CGFloat startY = 82; // Bottom row

    for (int r = 0; r < 2; r++) {
        for (int c = 0; c < 3; c++) {
            int face = gridFaceMapping[r][c];
            CGFloat x = startX + c * (cardW + gapX);
            CGFloat y = (r == 0) ? (startY + cardH + gapY) : startY;

            RubikFaceCardView* card = [[RubikFaceCardView alloc] initWithFrame:NSMakeRect(x, y, cardW, cardH)
                                                                     faceIndex:face];
            card.delegate = self;
            [_overviewView addSubview:card];
            _faceCards[face] = card;
        }
    }

    // ---------------- Footer Row ----------------
    _progressLabel = [NSTextField labelWithString:@"Faces Uploaded: 0 / 6"];
    _progressLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightBold];
    _progressLabel.textColor = [NSColor whiteColor];
    _progressLabel.accessibilityIdentifier = @"uploadProgressLabel";
    _progressLabel.frame = NSMakeRect(20, 48, 200, 20);
    [_overviewView addSubview:_progressLabel];

    _validationLabel = [NSTextField labelWithString:@"Upload all 6 faces to enable instant solving."];
    _validationLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _validationLabel.textColor = [NSColor colorWithCalibratedWhite:0.75 alpha:1.0];
    _validationLabel.accessibilityIdentifier = @"uploadValidationLabel";
    _validationLabel.frame = NSMakeRect(20, 28, 480, 18);
    [_overviewView addSubview:_validationLabel];

    _colorCountLabel = [NSTextField labelWithString:@"W:0  R:0  G:0  Y:0  O:0  B:0"];
    _colorCountLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium];
    _colorCountLabel.textColor = [NSColor colorWithCalibratedWhite:0.6 alpha:1.0];
    _colorCountLabel.accessibilityIdentifier = @"uploadColorCountLabel";
    _colorCountLabel.frame = NSMakeRect(20, 10, 480, 16);
    [_overviewView addSubview:_colorCountLabel];

    // Right Action Buttons
    NSButton* btnCancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(onCancelClicked:)];
    btnCancel.bezelStyle = NSBezelStyleRounded;
    btnCancel.frame = NSMakeRect(530, 20, 85, 32);
    [_overviewView addSubview:btnCancel];

    _btnApplyToCube = [NSButton buttonWithTitle:@"Apply to 3D Cube" target:self action:@selector(onApplyToCubeClicked:)];
    _btnApplyToCube.bezelStyle = NSBezelStyleRounded;
    _btnApplyToCube.accessibilityIdentifier = @"applyToCubeButton";
    _btnApplyToCube.frame = NSMakeRect(620, 20, 150, 32);
    [_overviewView addSubview:_btnApplyToCube];

    _btnApplyAndSolve = [NSButton buttonWithTitle:@"⚡ Apply & Solve" target:self action:@selector(onApplyAndSolveClicked:)];
    _btnApplyAndSolve.bezelStyle = NSBezelStyleRounded;
    _btnApplyAndSolve.keyEquivalent = @"\r";
    _btnApplyAndSolve.accessibilityIdentifier = @"applyAndSolveButton";
    _btnApplyAndSolve.frame = NSMakeRect(776, 20, 164, 32);
    [_overviewView addSubview:_btnApplyAndSolve];
}

#pragma mark - Build Detail Single-Face Editor View

- (void)buildDetailEditorView {
    _detailEditorView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 960, 700)];

    // Left Pane: Image Preview with Overlap UI
    _previewView = [[RubikFaceImagePreviewView alloc] initWithFrame:NSMakeRect(30, 120, 440, 440)];
    _previewView.wantsLayer = YES;
    _previewView.layer.cornerRadius = 10;
    _previewView.layer.masksToBounds = YES;
    _previewView.delegate = self;
    [_detailEditorView addSubview:_previewView];

    // Grid Size Slider & Reset row
    NSTextField* lblSlider = [NSTextField labelWithString:@"Grid Size:"];
    lblSlider.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    lblSlider.textColor = [NSColor whiteColor];
    lblSlider.frame = NSMakeRect(30, 80, 60, 20);
    [_detailEditorView addSubview:lblSlider];

    _sizeSlider = [NSSlider sliderWithValue:0.76 minValue:0.20 maxValue:0.95 target:self action:@selector(onSizeSliderChanged:)];
    _sizeSlider.frame = NSMakeRect(95, 80, 280, 20);
    [_detailEditorView addSubview:_sizeSlider];

    NSButton* btnResetGrid = [NSButton buttonWithTitle:@"↺ Reset" target:self action:@selector(onResetGridClicked:)];
    btnResetGrid.bezelStyle = NSBezelStyleInline;
    btnResetGrid.font = [NSFont systemFontOfSize:11];
    btnResetGrid.frame = NSMakeRect(385, 80, 85, 22);
    [_detailEditorView addSubview:btnResetGrid];

    NSTextField* hintLabel = [NSTextField labelWithString:@"💡 Drag inside grid to align • Drag bottom-right corner to scale"];
    hintLabel.font = [NSFont systemFontOfSize:11];
    hintLabel.textColor = [NSColor colorWithCalibratedWhite:0.7 alpha:1.0];
    hintLabel.frame = NSMakeRect(30, 50, 440, 18);
    [_detailEditorView addSubview:hintLabel];

    // Right Side: Controls & Editor
    CGFloat rx = 500.0;
    CGFloat rw = 430.0;

    _detailTitleLabel = [NSTextField labelWithString:@"Fine-Tune Face Alignment"];
    _detailTitleLabel.font = [NSFont systemFontOfSize:18 weight:NSFontWeightBold];
    _detailTitleLabel.textColor = [NSColor whiteColor];
    _detailTitleLabel.frame = NSMakeRect(rx, 630, rw, 26);
    [_detailEditorView addSubview:_detailTitleLabel];

    NSTextField* subLabel = [NSTextField labelWithString:@"Adjust the 3x3 recognition frame or tap any sticker below to correct its color."];
    subLabel.font = [NSFont systemFontOfSize:11];
    subLabel.textColor = [NSColor colorWithCalibratedWhite:0.7 alpha:1.0];
    subLabel.frame = NSMakeRect(rx, 608, rw, 18);
    [_detailEditorView addSubview:subLabel];

    // Compass Labels
    _compassTopLabel = [NSTextField labelWithString:@"▲ TOP"];
    _compassTopLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightBold];
    _compassTopLabel.alignment = NSTextAlignmentCenter;
    _compassTopLabel.textColor = [NSColor whiteColor];
    _compassTopLabel.frame = NSMakeRect(rx, 530, rw, 18);
    [_detailEditorView addSubview:_compassTopLabel];

    _compassLeftLabel = [NSTextField labelWithString:@"◀ LEFT"];
    _compassLeftLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _compassLeftLabel.textColor = [NSColor whiteColor];
    _compassLeftLabel.alignment = NSTextAlignmentRight;
    _compassLeftLabel.frame = NSMakeRect(rx - 10, 410, 100, 32);
    [_detailEditorView addSubview:_compassLeftLabel];

    _compassRightLabel = [NSTextField labelWithString:@"RIGHT ▶"];
    _compassRightLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _compassRightLabel.textColor = [NSColor whiteColor];
    _compassRightLabel.alignment = NSTextAlignmentLeft;
    _compassRightLabel.frame = NSMakeRect(rx + 340, 410, 100, 32);
    [_detailEditorView addSubview:_compassRightLabel];

    // 3x3 Square Editor Grid
    _detailSquareButtons = [NSMutableArray arrayWithCapacity:9];
    _detectedColors.resize(9, COLOR_WHITE);
    _selectedSquareIndex = 4;

    CGFloat gridStartX = rx + 105;
    CGFloat gridStartY = 330;
    CGFloat sqSize = 65;
    CGFloat sqGap = 6;

    for (int row = 0; row < 3; row++) {
        for (int col = 0; col < 3; col++) {
            int idx = row * 3 + col;
            NSButton* btn = [NSButton buttonWithTitle:@"" target:self action:@selector(onDetailSquareClicked:)];
            btn.tag = idx;
            btn.bezelStyle = NSBezelStyleRegularSquare;
            btn.bordered = NO;
            btn.wantsLayer = YES;
            btn.layer.cornerRadius = 8;
            btn.frame = NSMakeRect(gridStartX + col * (sqSize + sqGap),
                                   gridStartY + (2 - row) * (sqSize + sqGap),
                                   sqSize, sqSize);
            [_detailEditorView addSubview:btn];
            [_detailSquareButtons addObject:btn];
        }
    }

    _compassBottomLabel = [NSTextField labelWithString:@"▼ BOTTOM"];
    _compassBottomLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightBold];
    _compassBottomLabel.alignment = NSTextAlignmentCenter;
    _compassBottomLabel.textColor = [NSColor whiteColor];
    _compassBottomLabel.frame = NSMakeRect(rx, 300, rw, 18);
    [_detailEditorView addSubview:_compassBottomLabel];

    // Rotation & Color Palette Row
    NSButton* btnRotCCW = [NSButton buttonWithTitle:@"↺ 90°" target:self action:@selector(onDetailRotateCCWClicked:)];
    btnRotCCW.bezelStyle = NSBezelStyleInline;
    btnRotCCW.toolTip = @"Rotate 90° Counter-Clockwise";
    btnRotCCW.frame = NSMakeRect(rx + 10, 240, 56, 28);
    [_detailEditorView addSubview:btnRotCCW];

    NSButton* btnRotCW = [NSButton buttonWithTitle:@"↻ 90°" target:self action:@selector(onDetailRotateCWClicked:)];
    btnRotCW.bezelStyle = NSBezelStyleInline;
    btnRotCW.toolTip = @"Rotate 90° Clockwise";
    btnRotCW.frame = NSMakeRect(rx + 70, 240, 56, 28);
    [_detailEditorView addSubview:btnRotCW];

    // Quick Color Palette
    CGFloat palStartX = rx + 140;
    CGFloat palW = 44;
    for (int c = 0; c < 6; c++) {
        NSButton* palBtn = [NSButton buttonWithTitle:@"" target:self action:@selector(onDetailPaletteClicked:)];
        palBtn.tag = c;
        palBtn.bezelStyle = NSBezelStyleRegularSquare;
        palBtn.bordered = NO;
        palBtn.wantsLayer = YES;
        palBtn.layer.cornerRadius = 6;
        palBtn.frame = NSMakeRect(palStartX + c * (palW + 5), 240, palW, 28);
        palBtn.layer.backgroundColor = [RubikColorClassifier nsColorForIndex:c].CGColor;
        static const char* letters = "WRGYOB";
        palBtn.title = [NSString stringWithFormat:@"%c", letters[c]];
        palBtn.contentTintColor = (c == COLOR_WHITE || c == COLOR_YELLOW) ? [NSColor blackColor] : [NSColor whiteColor];
        palBtn.font = [NSFont systemFontOfSize:12 weight:NSFontWeightBold];
        [_detailEditorView addSubview:palBtn];
    }

    // Bottom Navigation Buttons
    NSButton* btnDetailCancel = [NSButton buttonWithTitle:@"← Cancel" target:self action:@selector(onDetailCancelClicked:)];
    btnDetailCancel.bezelStyle = NSBezelStyleRounded;
    btnDetailCancel.frame = NSMakeRect(rx + 80, 50, 110, 32);
    [_detailEditorView addSubview:btnDetailCancel];

    NSButton* btnDetailDone = [NSButton buttonWithTitle:@"✓ Done & Save" target:self action:@selector(onDetailDoneClicked:)];
    btnDetailDone.bezelStyle = NSBezelStyleRounded;
    btnDetailDone.keyEquivalent = @"\r";
    btnDetailDone.frame = NSMakeRect(rx + 200, 50, 160, 32);
    [_detailEditorView addSubview:btnDetailDone];
}

#pragma mark - Cube Validation & Updates

- (void)updateCubeValidation {
    int uploadedCount = 0;
    int colorCounts[6] = {0, 0, 0, 0, 0, 0};

    uint8_t fullFacelets[54];
    for (int i = 0; i < 54; i++) {
        fullFacelets[i] = _cubeModel.getFacelet(i);
    }

    for (int f = 0; f < 6; f++) {
        if (_faceCards[f].isUploaded) {
            uploadedCount++;
            const std::vector<uint8_t>& fColors = _faceCards[f].facelets;
            for (int i = 0; i < 9 && i < (int)fColors.size(); i++) {
                uint8_t col = fColors[i];
                fullFacelets[f * 9 + i] = col;
                if (col < 6) colorCounts[col]++;
            }
        }
    }

    _progressLabel.stringValue = [NSString stringWithFormat:@"Faces Uploaded: %d / 6", uploadedCount];

    _colorCountLabel.stringValue = [NSString stringWithFormat:@"W:%d  R:%d  G:%d  Y:%d  O:%d  B:%d",
                                    colorCounts[COLOR_WHITE], colorCounts[COLOR_RED],
                                    colorCounts[COLOR_GREEN], colorCounts[COLOR_YELLOW],
                                    colorCounts[COLOR_ORANGE], colorCounts[COLOR_BLUE]];

    if (uploadedCount == 6) {
        RubikCube testCube(fullFacelets);
        std::string errMsg;
        bool valid = testCube.isValidCube(&errMsg);

        if (valid) {
            _validationLabel.stringValue = @"✅ All 6 faces recognized! Mathematically valid cube ready to solve.";
            _validationLabel.textColor = [NSColor colorWithCalibratedRed:0.2 green:0.85 blue:0.35 alpha:1.0];
            _colorCountLabel.textColor = [NSColor colorWithCalibratedRed:0.4 green:0.85 blue:0.5 alpha:1.0];
        } else {
            _validationLabel.stringValue = [NSString stringWithFormat:@"⚠️ Warning: %s. Click 'Adjust' or tap stickers to fix.", errMsg.c_str()];
            _validationLabel.textColor = [NSColor colorWithCalibratedRed:1.0 green:0.65 blue:0.25 alpha:1.0];
            _colorCountLabel.textColor = [NSColor colorWithCalibratedRed:1.0 green:0.75 blue:0.4 alpha:1.0];
        }
    } else {
        _validationLabel.stringValue = [NSString stringWithFormat:@"%d faces uploaded. Upload all 6 faces to enable instant solving.", uploadedCount];
        _validationLabel.textColor = [NSColor colorWithCalibratedWhite:0.7 alpha:1.0];
        _colorCountLabel.textColor = [NSColor colorWithCalibratedWhite:0.6 alpha:1.0];
    }
}

#pragma mark - Batch Upload & Sample Photos

- (void)onBatchUploadClicked:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.title = @"Select Cube Face Photos (1 to 6 images)";
    panel.prompt = @"Import Photos";
    panel.allowedContentTypes = @[UTTypeImage];
    panel.allowsMultipleSelection = YES;

    [panel beginSheetModalForWindow:_sheetWindow completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSModalResponseOK || panel.URLs.count == 0) return;

        [self processMultipleImageURLs:panel.URLs];
    }];
}

- (void)processMultipleImageURLs:(NSArray<NSURL*>*)urls {
    for (NSURL* url in urls) {
        NSImage* img = [[NSImage alloc] initWithContentsOfURL:url];
        if (!img) continue;

        CGRect defaultROI = [self defaultROIForImage:img];
        std::vector<SampledPatch> patches = [_classifier classifyGridFromImage:img normalizedROI:defaultROI];
        if (patches.size() != 9) continue;

        int targetFace = -1;
        uint8_t centerColor = patches[4].colorIndex;

        // Auto-match face by center sticker color
        switch (centerColor) {
            case COLOR_WHITE:  targetFace = FACE_U; break;
            case COLOR_RED:    targetFace = FACE_R; break;
            case COLOR_GREEN:  targetFace = FACE_F; break;
            case COLOR_YELLOW: targetFace = FACE_D; break;
            case COLOR_ORANGE: targetFace = FACE_L; break;
            case COLOR_BLUE:   targetFace = FACE_B; break;
        }

        // If filename contains specific face indicator, prefer filename
        NSString* lowerName = url.lastPathComponent.lowercaseString;
        if ([lowerName containsString:@"face_0"] || [lowerName containsString:@"top"] || [lowerName containsString:@"white"]) targetFace = FACE_U;
        else if ([lowerName containsString:@"face_1"] || [lowerName containsString:@"right"] || [lowerName containsString:@"red"]) targetFace = FACE_R;
        else if ([lowerName containsString:@"face_2"] || [lowerName containsString:@"front"] || [lowerName containsString:@"green"]) targetFace = FACE_F;
        else if ([lowerName containsString:@"face_3"] || [lowerName containsString:@"down"] || [lowerName containsString:@"yellow"]) targetFace = FACE_D;
        else if ([lowerName containsString:@"face_4"] || [lowerName containsString:@"left"] || [lowerName containsString:@"orange"]) targetFace = FACE_L;
        else if ([lowerName containsString:@"face_5"] || [lowerName containsString:@"back"] || [lowerName containsString:@"blue"]) targetFace = FACE_B;

        if (targetFace < 0 || targetFace >= 6) {
            // Find first unconfigured card
            for (int f = 0; f < 6; f++) {
                if (!_faceCards[f].isUploaded) {
                    targetFace = f;
                    break;
                }
            }
        }

        if (targetFace >= 0 && targetFace < 6) {
            std::vector<uint8_t> facelets(9);
            for (int i = 0; i < 9; i++) facelets[i] = patches[i].colorIndex;
            [_faceCards[targetFace] setUploadedImage:img facelets:facelets roi:defaultROI];
        }
    }

    [self updateCubeValidation];
}

- (void)onLoadSamplePhotosClicked:(id)sender {
    NSString* sampleDir = [self findSampleImagesDirectory];
    if (!sampleDir) {
        NSAlert* alert = [[NSAlert alloc] init];
        alert.messageText = @"Sample Images Not Found";
        alert.informativeText = @"Could not locate the 'SampleImages' directory on your system.";
        [alert beginSheetModalForWindow:_sheetWindow completionHandler:nil];
        return;
    }

    static const char* sampleFiles[6] = {
        "face_0_top_white.png",
        "face_1_right_red.png",
        "face_2_front_green.png",
        "face_3_down_yellow.png",
        "face_4_left_orange.png",
        "face_5_back_blue.png"
    };

    for (int f = 0; f < 6; f++) {
        NSString* filePath = [sampleDir stringByAppendingPathComponent:[NSString stringWithUTF8String:sampleFiles[f]]];
        NSImage* img = [[NSImage alloc] initWithContentsOfFile:filePath];
        if (img) {
            CGRect defaultROI = [self defaultROIForImage:img];
            std::vector<SampledPatch> patches = [_classifier classifyGridFromImage:img normalizedROI:defaultROI];
            std::vector<uint8_t> facelets(9);
            if (patches.size() == 9) {
                for (int i = 0; i < 9; i++) facelets[i] = patches[i].colorIndex;
            } else {
                facelets.assign(9, (uint8_t)f);
            }
            [_faceCards[f] setUploadedImage:img facelets:facelets roi:defaultROI];
        }
    }

    [self updateCubeValidation];
}

- (NSString*)findSampleImagesDirectory {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSMutableArray<NSString*>* candidates = [NSMutableArray array];

    // 1. Explicit override for testing and custom installs.
    NSString* overrideDir = NSProcessInfo.processInfo.environment[@"RUBIK_SAMPLE_IMAGES_DIR"];
    if (overrideDir.length > 0) {
        [candidates addObject:overrideDir];
    }

    // 2. App bundle. project.yml copies SampleImages into Resources as a
    //    folder reference, so this is the normal path for a Run from Xcode.
    NSArray<NSString*>* bundlePaths = @[
        [NSBundle mainBundle].resourcePath ?: @"",
        [NSBundle mainBundle].resourceURL.path ?: @"",
        [NSBundle mainBundle].bundlePath ?: @"",
        [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Contents/Resources"] ?: @""
    ];
    for (NSString* base in bundlePaths) {
        if (base.length == 0) continue;
        [candidates addObject:[base stringByAppendingPathComponent:@"SampleImages"]];
        [candidates addObject:base];
    }

    // 3. Current working directory and its parents (handles `swift run`-style
    //    launches, tests, and running the binary from the repository root).
    NSString* cwd = [fm currentDirectoryPath];
    for (int depth = 0; depth < 5 && cwd.length > 1; ++depth) {
        [candidates addObject:[cwd stringByAppendingPathComponent:@"SampleImages"]];
        cwd = [cwd stringByDeletingLastPathComponent];
    }

    // 4. Development fallback: the source tree next to the executable's
    //    DerivedData products directory. This makes samples available even
    //    when the app bundle was built before the folder reference was added.
    NSString* executableDir = [[NSBundle mainBundle].executablePath stringByDeletingLastPathComponent];
    NSString* probe = executableDir;
    for (int depth = 0; depth < 6 && probe.length > 1; ++depth) {
        [candidates addObject:[probe stringByAppendingPathComponent:@"SampleImages"]];
        probe = [probe stringByDeletingLastPathComponent];
    }

    for (NSString* candidate in candidates) {
        NSString* facePath = [candidate stringByAppendingPathComponent:@"face_0_top_white.png"];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:facePath isDirectory:&isDir] && !isDir) {
            return candidate;
        }
    }
    return nil;
}

- (CGRect)defaultROIForImage:(NSImage*)img {
    if (!img) return CGRectMake(0.12, 0.12, 0.76, 0.76);
    NSSize sz = img.size;
    if (sz.width <= 0 || sz.height <= 0) return CGRectMake(0.12, 0.12, 0.76, 0.76);

    CGFloat minDim = std::min(sz.width, sz.height);
    CGFloat normW = (minDim * 0.76) / sz.width;
    CGFloat normH = (minDim * 0.76) / sz.height;
    CGFloat normX = (1.0 - normW) / 2.0;
    CGFloat normY = (1.0 - normH) / 2.0;
    return CGRectMake(normX, normY, normW, normH);
}

- (void)onClearAllClicked:(id)sender {
    for (int f = 0; f < 6; f++) {
        [_faceCards[f] clearUploadedFace];
    }
    [self updateCubeValidation];
}

#pragma mark - Card Delegate Callbacks

- (void)faceCardDidRequestChooseImage:(RubikFaceCardView*)card {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    static const char* faceNames[6] = {"Top Face (White)", "Right Face (Red)", "Front Face (Green)", "Down Face (Yellow)", "Left Face (Orange)", "Back Face (Blue)"};
    panel.title = [NSString stringWithFormat:@"Select Photo for %s", faceNames[card.faceIndex]];
    panel.prompt = @"Choose Image";
    panel.allowedContentTypes = @[UTTypeImage];
    panel.allowsMultipleSelection = NO;

    [panel beginSheetModalForWindow:_sheetWindow completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSModalResponseOK || !panel.URL) return;

        NSImage* image = [[NSImage alloc] initWithContentsOfURL:panel.URL];
        if (!image) return;

        CGRect roi = [self defaultROIForImage:image];
        std::vector<SampledPatch> patches = [self->_classifier classifyGridFromImage:image normalizedROI:roi];
        std::vector<uint8_t> facelets(9);
        if (patches.size() == 9) {
            for (int i = 0; i < 9; i++) facelets[i] = patches[i].colorIndex;
        } else {
            facelets.assign(9, (uint8_t)card.faceIndex);
        }

        [card setUploadedImage:image facelets:facelets roi:roi];
        [self updateCubeValidation];
    }];
}

- (void)faceCard:(RubikFaceCardView*)card didDropImage:(NSImage*)image {
    CGRect roi = [self defaultROIForImage:image];
    std::vector<SampledPatch> patches = [_classifier classifyGridFromImage:image normalizedROI:roi];
    std::vector<uint8_t> facelets(9);
    if (patches.size() == 9) {
        for (int i = 0; i < 9; i++) facelets[i] = patches[i].colorIndex;
    } else {
        facelets.assign(9, (uint8_t)card.faceIndex);
    }

    [card setUploadedImage:image facelets:facelets roi:roi];
    [self updateCubeValidation];
}

- (void)faceCardDidRequestRotate:(RubikFaceCardView*)card {
    [self updateCubeValidation];
}

- (void)faceCardDidRequestClear:(RubikFaceCardView*)card {
    [self updateCubeValidation];
}

- (void)faceCard:(RubikFaceCardView*)card didChangeFacelet:(int)stickerIdx toColor:(uint8_t)color {
    [self updateCubeValidation];
}

- (void)faceCardDidRequestEdit:(RubikFaceCardView*)card {
    [self openDetailEditorForFace:card.faceIndex];
}

#pragma mark - Detailed Single Face Editor

- (void)openDetailEditorForFace:(int)faceIndex {
    _editingFaceIndex = faceIndex;
    RubikFaceCardView* card = _faceCards[faceIndex];

    static const char* faceNames[6] = {"Top Face (U)", "Right Face (R)", "Front Face (F)", "Down Face (D)", "Left Face (L)", "Back Face (B)"};
    _detailTitleLabel.stringValue = [NSString stringWithFormat:@"Fine-Tune %s Alignment", faceNames[faceIndex]];

    _previewView.image = card.image;
    _previewView.normalizedROI = card.normalizedROI;
    _sizeSlider.doubleValue = card.normalizedROI.size.width;

    _detectedColors = card.facelets;
    _selectedSquareIndex = 4;

    [self updateCompassLabelsForFace:faceIndex];
    [self reclassifyDetailPatches];
    [self updateAllDetailSquareButtons];

    _sheetWindow.contentView = _detailEditorView;
}

- (void)updateCompassLabelsForFace:(int)face {
    NSString *topName = @"", *botName = @"", *leftName = @"", *rightName = @"";
    switch (face) {
        case FACE_U: // Top (White)
            topName = @"▲ TOP: Blue (B)";
            botName = @"▼ BOTTOM: Green (F)";
            leftName = @"◀ Orange (L)";
            rightName = @"Red (R) ▶";
            break;
        case FACE_R: // Right (Red)
            topName = @"▲ TOP: White (U)";
            botName = @"▼ BOTTOM: Yellow (D)";
            leftName = @"◀ Green (F)";
            rightName = @"Blue (B) ▶";
            break;
        case FACE_F: // Front (Green)
            topName = @"▲ TOP: White (U)";
            botName = @"▼ BOTTOM: Yellow (D)";
            leftName = @"◀ Orange (L)";
            rightName = @"Red (R) ▶";
            break;
        case FACE_D: // Down (Yellow)
            topName = @"▲ TOP: Green (F)";
            botName = @"▼ BOTTOM: Blue (B)";
            leftName = @"◀ Orange (L)";
            rightName = @"Red (R) ▶";
            break;
        case FACE_L: // Left (Orange)
            topName = @"▲ TOP: White (U)";
            botName = @"▼ BOTTOM: Yellow (D)";
            leftName = @"◀ Blue (B)";
            rightName = @"Green (F) ▶";
            break;
        case FACE_B: // Back (Blue)
            topName = @"▲ TOP: White (U)";
            botName = @"▼ BOTTOM: Yellow (D)";
            leftName = @"◀ Red (R)";
            rightName = @"Orange (L) ▶";
            break;
    }
    _compassTopLabel.stringValue = topName;
    _compassBottomLabel.stringValue = botName;
    _compassLeftLabel.stringValue = leftName;
    _compassRightLabel.stringValue = rightName;
}

- (void)reclassifyDetailPatches {
    if (!_previewView.image || !_classifier) return;

    std::vector<SampledPatch> patches = [_classifier classifyGridFromImage:_previewView.image
                                                             normalizedROI:_previewView.normalizedROI];
    if (patches.size() == 9) {
        _previewView.patches = patches;
        [_previewView setNeedsDisplay:YES];
    }
}

- (void)previewViewDidUpdateROI:(CGRect)normalizedROI {
    [self reclassifyDetailPatches];
    if (_previewView.patches.size() == 9) {
        for (int i = 0; i < 9; i++) {
            _detectedColors[i] = _previewView.patches[i].colorIndex;
        }
        [self updateAllDetailSquareButtons];
    }
}

- (void)onSizeSliderChanged:(NSSlider*)slider {
    [_previewView setGridScale:slider.doubleValue];
}

- (void)onResetGridClicked:(id)sender {
    [_previewView resetDefaultROI];
    _sizeSlider.doubleValue = 0.76;
    [self reclassifyDetailPatches];
    if (_previewView.patches.size() == 9) {
        for (int i = 0; i < 9; i++) {
            _detectedColors[i] = _previewView.patches[i].colorIndex;
        }
        [self updateAllDetailSquareButtons];
    }
}

- (void)updateAllDetailSquareButtons {
    static const char* letters = "WRGYOB";
    for (int i = 0; i < 9 && i < (int)_detailSquareButtons.count; i++) {
        uint8_t color = _detectedColors[i];
        NSButton* btn = _detailSquareButtons[i];
        NSColor* c = [RubikColorClassifier nsColorForIndex:color];
        btn.layer.backgroundColor = c.CGColor;
        btn.layer.borderWidth = (i == _selectedSquareIndex) ? 3.5 : 1.5;
        btn.layer.borderColor = (i == _selectedSquareIndex) ? [NSColor whiteColor].CGColor : [NSColor colorWithCalibratedWhite:0.25 alpha:1.0].CGColor;
        btn.title = [NSString stringWithFormat:@"%c", letters[color < 6 ? color : 0]];
        btn.contentTintColor = (color == COLOR_WHITE || color == COLOR_YELLOW) ? [NSColor blackColor] : [NSColor whiteColor];
        btn.font = [NSFont systemFontOfSize:17 weight:NSFontWeightBold];
    }
}

- (void)onDetailSquareClicked:(NSButton*)sender {
    NSInteger idx = sender.tag;
    _selectedSquareIndex = idx;
    if (idx >= 0 && idx < 9) {
        _detectedColors[idx] = (_detectedColors[idx] + 1) % 6;
        if (_previewView.patches.size() == 9) {
            _previewView.patches[idx].colorIndex = _detectedColors[idx];
            [_previewView setNeedsDisplay:YES];
        }
        [self updateAllDetailSquareButtons];
    }
}

- (void)onDetailPaletteClicked:(NSButton*)sender {
    uint8_t newColor = (uint8_t)sender.tag;
    if (_selectedSquareIndex >= 0 && _selectedSquareIndex < 9) {
        _detectedColors[_selectedSquareIndex] = newColor;
        if (_previewView.patches.size() == 9) {
            _previewView.patches[_selectedSquareIndex].colorIndex = newColor;
            [_previewView setNeedsDisplay:YES];
        }
        [self updateAllDetailSquareButtons];
    }
}

- (void)onDetailRotateCWClicked:(id)sender {
    std::vector<uint8_t> rotated(9);
    for (int r = 0; r < 3; r++) {
        for (int c = 0; c < 3; c++) {
            rotated[c * 3 + (2 - r)] = _detectedColors[r * 3 + c];
        }
    }
    _detectedColors = rotated;
    if (_previewView.patches.size() == 9) {
        for (int i = 0; i < 9; i++) _previewView.patches[i].colorIndex = _detectedColors[i];
        [_previewView setNeedsDisplay:YES];
    }
    [self updateAllDetailSquareButtons];
}

- (void)onDetailRotateCCWClicked:(id)sender {
    std::vector<uint8_t> rotated(9);
    for (int r = 0; r < 3; r++) {
        for (int c = 0; c < 3; c++) {
            rotated[(2 - c) * 3 + r] = _detectedColors[r * 3 + c];
        }
    }
    _detectedColors = rotated;
    if (_previewView.patches.size() == 9) {
        for (int i = 0; i < 9; i++) _previewView.patches[i].colorIndex = _detectedColors[i];
        [_previewView setNeedsDisplay:YES];
    }
    [self updateAllDetailSquareButtons];
}

- (void)onDetailCancelClicked:(id)sender {
    _sheetWindow.contentView = _overviewView;
}

- (void)onDetailDoneClicked:(id)sender {
    if (_editingFaceIndex >= 0 && _editingFaceIndex < 6) {
        RubikFaceCardView* card = _faceCards[_editingFaceIndex];
        [card setUploadedImage:_previewView.image facelets:_detectedColors roi:_previewView.normalizedROI];
    }
    _sheetWindow.contentView = _overviewView;
    [self updateCubeValidation];
}

#pragma mark - Main Sheet Completion Actions

- (void)onCancelClicked:(id)sender {
    [_parentWindow endSheet:_sheetWindow];
    _sheetWindow = nil;
}

- (void)onApplyToCubeClicked:(id)sender {
    [self finalizeAndApplyAutoSolve:NO];
}

- (void)onApplyAndSolveClicked:(id)sender {
    [self finalizeAndApplyAutoSolve:YES];
}

- (void)finalizeAndApplyAutoSolve:(BOOL)autoSolve {
    uint8_t fullFacelets[54];
    for (int i = 0; i < 54; i++) {
        fullFacelets[i] = _cubeModel.getFacelet(i);
    }

    uint8_t configuredMask = 0;
    for (int f = 0; f < 6; f++) {
        if (_faceCards[f].isUploaded) {
            configuredMask |= (1 << f);
            const std::vector<uint8_t>& fColors = _faceCards[f].facelets;
            for (int i = 0; i < 9 && i < (int)fColors.size(); i++) {
                fullFacelets[f * 9 + i] = fColors[i];
            }
        }
    }

    RubikCubeUploadCompletion completion = _cubeCompletion;
    [_parentWindow endSheet:_sheetWindow];
    _sheetWindow = nil;

    if (completion) {
        completion(fullFacelets, configuredMask, autoSolve);
    }
}

#pragma mark - Legacy Compatibility Methods

- (void)promptAndRecognizeFaceForWindow:(NSWindow*)parentWindow
                             classifier:(RubikColorClassifier*)classifier
                             completion:(RubikFaceUploadCompletion)completion
{
    [self promptAndRecognizeFaceForWindow:parentWindow
                               classifier:classifier
                      configuredFacesMask:0
                               completion:completion];
}

- (void)promptAndRecognizeFaceForWindow:(NSWindow*)parentWindow
                             classifier:(RubikColorClassifier*)classifier
                    configuredFacesMask:(uint8_t)configuredFacesMask
                             completion:(RubikFaceUploadCompletion)completion
{
    // Redirect legacy single face call to the 6-face upload sheet
    RubikCube dummyCube;
    [self showCubeUploadSheetForWindow:parentWindow
                             cubeModel:dummyCube
                            classifier:classifier
                   configuredFacesMask:configuredFacesMask
                            completion:^(const uint8_t facelets[54], uint8_t configuredMask, BOOL autoSolve) {
        if (completion) {
            // Forward first configured face
            for (int f = 0; f < 6; f++) {
                if (configuredMask & (1 << f)) {
                    std::vector<uint8_t> fVec(facelets + f * 9, facelets + f * 9 + 9);
                    completion(f, fVec, autoSolve);
                    return;
                }
            }
            std::vector<uint8_t> dummyVec(facelets, facelets + 9);
            completion(0, dummyVec, autoSolve);
        }
    }];
}

@end
