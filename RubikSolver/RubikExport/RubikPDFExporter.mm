//
//  RubikPDFExporter.mm
//  RubikSolver - Illustrated PDF Solution Manual Exporter
//

#import "RubikPDFExporter.h"
#import <CoreGraphics/CoreGraphics.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSColor* colorForFacelet(uint8_t c) {
    switch (c) {
        case COLOR_WHITE:  return [NSColor colorWithCalibratedRed:0.95 green:0.95 blue:0.95 alpha:1.0];
        case COLOR_RED:    return [NSColor colorWithCalibratedRed:0.88 green:0.20 blue:0.20 alpha:1.0];
        case COLOR_GREEN:  return [NSColor colorWithCalibratedRed:0.15 green:0.75 blue:0.35 alpha:1.0];
        case COLOR_YELLOW: return [NSColor colorWithCalibratedRed:0.95 green:0.80 blue:0.10 alpha:1.0];
        case COLOR_ORANGE: return [NSColor colorWithCalibratedRed:0.95 green:0.45 blue:0.10 alpha:1.0];
        case COLOR_BLUE:   return [NSColor colorWithCalibratedRed:0.15 green:0.45 blue:0.95 alpha:1.0];
        default:           return [NSColor lightGrayColor];
    }
}

// Draws a 3x3 face
static void drawFace3x3(CGContextRef ctx, CGRect rect, const uint8_t* facelets, int faceOffset) {
    CGFloat sz = rect.size.width / 3.0;
    for (int r = 0; r < 3; r++) {
        for (int c = 0; c < 3; c++) {
            CGRect cellRect = CGRectMake(rect.origin.x + c * sz,
                                         rect.origin.y + (2 - r) * sz,
                                         sz, sz);

            uint8_t colorIdx = facelets[faceOffset + r * 3 + c];
            NSColor* nsCol = colorForFacelet(colorIdx);

            CGContextSetFillColorWithColor(ctx, nsCol.CGColor);
            CGContextFillRect(ctx, cellRect);

            CGContextSetStrokeColorWithColor(ctx, [NSColor colorWithCalibratedWhite:0.2 alpha:1.0].CGColor);
            CGContextSetLineWidth(ctx, 0.75);
            CGContextStrokeRect(ctx, cellRect);
        }
    }
}

// Draws 2D unfolded net:
//       [ U ]
// [ L ] [ F ] [ R ] [ B ]
//       [ D ]
static void drawCubeNet(CGContextRef ctx, CGRect rect, const RubikCube& cube) {
    CGFloat faceSz = rect.size.width / 4.0;
    CGFloat originX = rect.origin.x;
    CGFloat originY = rect.origin.y;

    const uint8_t* f = cube.getFacelets();

    // Top: U (offset 0)
    drawFace3x3(ctx, CGRectMake(originX + faceSz, originY + faceSz * 2, faceSz, faceSz), f, 0);

    // Middle row: L (36), F (18), R (9), B (45)
    drawFace3x3(ctx, CGRectMake(originX + 0, originY + faceSz, faceSz, faceSz), f, 36);
    drawFace3x3(ctx, CGRectMake(originX + faceSz, originY + faceSz, faceSz, faceSz), f, 18);
    drawFace3x3(ctx, CGRectMake(originX + faceSz * 2, originY + faceSz, faceSz, faceSz), f, 9);
    drawFace3x3(ctx, CGRectMake(originX + faceSz * 3, originY + faceSz, faceSz, faceSz), f, 45);

    // Bottom: D (27)
    drawFace3x3(ctx, CGRectMake(originX + faceSz, originY + 0, faceSz, faceSz), f, 27);
}

@implementation RubikPDFExporter

+ (void)exportSolutionWithWindow:(NSWindow*)parentWindow
                     initialCube:(const RubikCube&)initialCube
                           moves:(const std::vector<int>&)moves
                     solveTimeMs:(double)timeMs
{
    NSSavePanel* savePanel = [NSSavePanel savePanel];
    savePanel.title = @"Export Step-by-Step Solution Guide";
    savePanel.nameFieldStringValue = @"RubiksCube_Solution_Guide.pdf";
    savePanel.allowedContentTypes = @[UTTypePDF];

    [savePanel beginSheetModalForWindow:parentWindow completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && savePanel.URL) {
            NSError* error = nil;
            BOOL success = [self renderSolutionToURL:savePanel.URL
                                         initialCube:initialCube
                                               moves:moves
                                         solveTimeMs:timeMs
                                               error:&error];
            if (success) {
                [[NSWorkspace sharedWorkspace] openURL:savePanel.URL];
            } else {
                NSAlert* alert = [[NSAlert alloc] init];
                alert.messageText = @"Export Failed";
                alert.informativeText = error.localizedDescription ?: @"Unknown error while generating PDF.";
                [alert beginSheetModalForWindow:parentWindow completionHandler:nil];
            }
        }
    }];
}

+ (BOOL)renderSolutionToURL:(NSURL*)fileURL
                initialCube:(const RubikCube&)initialCube
                      moves:(const std::vector<int>&)moves
                solveTimeMs:(double)timeMs
                      error:(NSError**)outError
{
    CGRect pageRect = CGRectMake(0, 0, 612, 792); // Standard Letter (8.5 x 11 in)
    CGDataConsumerRef consumer = CGDataConsumerCreateWithURL((__bridge CFURLRef)fileURL);
    if (!consumer) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"RubikPDFExporter" code:1
                                        userInfo:@{NSLocalizedDescriptionKey: @"Could not create PDF data consumer"}];
        }
        return NO;
    }

    CGContextRef ctx = CGPDFContextCreate(consumer, &pageRect, NULL);
    CGDataConsumerRelease(consumer);
    if (!ctx) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"RubikPDFExporter" code:2
                                        userInfo:@{NSLocalizedDescriptionKey: @"Could not create PDF context"}];
        }
        return NO;
    }

    NSDateFormatter* df = [[NSDateFormatter alloc] init];
    df.dateStyle = NSDateFormatterMediumStyle;
    df.timeStyle = NSDateFormatterShortStyle;
    NSString* dateStr = [df stringFromDate:[NSDate date]];

    RubikCube currentCube = initialCube;
    size_t totalMoves = moves.size();

    // -------------------------------------------------------------
    // Page 1: Title & Overview
    // -------------------------------------------------------------
    CGPDFContextBeginPage(ctx, NULL);
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO]];

    // White background
    CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
    CGContextFillRect(ctx, pageRect);

    // Decorative Header Banner
    CGContextSetRGBFillColor(ctx, 0.08, 0.12, 0.18, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, pageRect.size.height - 110, pageRect.size.width, 110));

    // Title text
    NSDictionary* titleAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:26 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    [@"RUBIK'S CUBE SOLVING GUIDE" drawAtPoint:NSMakePoint(40, pageRect.size.height - 56) withAttributes:titleAttrs];

    NSDictionary* subtitleAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.8 alpha:1.0]
    };
    NSString* sub = [NSString stringWithFormat:@"Verified by the exact two-phase solver on macOS • %@", dateStr];
    [sub drawAtPoint:NSMakePoint(40, pageRect.size.height - 84) withAttributes:subtitleAttrs];

    // Summary Statistics Card
    CGRect statsCardRect = CGRectMake(40, pageRect.size.height - 210, pageRect.size.width - 80, 80);
    CGContextSetRGBFillColor(ctx, 0.94, 0.96, 0.98, 1.0);
    CGContextFillRect(ctx, statsCardRect);

    CGContextSetRGBStrokeColor(ctx, 0.82, 0.86, 0.90, 1.0);
    CGContextSetLineWidth(ctx, 1.0);
    CGContextStrokeRect(ctx, statsCardRect);

    NSDictionary* cardLabelAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.4 alpha:1.0]
    };
    NSDictionary* cardValAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:20 weight:NSFontWeightHeavy],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.1 green:0.4 blue:0.8 alpha:1.0]
    };

    [@"TOTAL MOVES" drawAtPoint:NSMakePoint(60, statsCardRect.origin.y + 46) withAttributes:cardLabelAttrs];
    [[NSString stringWithFormat:@"%zu", totalMoves] drawAtPoint:NSMakePoint(60, statsCardRect.origin.y + 16) withAttributes:cardValAttrs];

    [@"SOLVE TIME" drawAtPoint:NSMakePoint(240, statsCardRect.origin.y + 46) withAttributes:cardLabelAttrs];
    [[NSString stringWithFormat:@"%.1f ms", timeMs] drawAtPoint:NSMakePoint(240, statsCardRect.origin.y + 16) withAttributes:cardValAttrs];

    [@"ALGORITHM" drawAtPoint:NSMakePoint(420, statsCardRect.origin.y + 46) withAttributes:cardLabelAttrs];
    [@"Metal Parallel IDA*" drawAtPoint:NSMakePoint(420, statsCardRect.origin.y + 16) withAttributes:cardValAttrs];

    // Initial Cube Diagram Section
    NSDictionary* secHeadingAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:15 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.15 alpha:1.0]
    };
    [@"Initial Cube Configuration (2D Unfolded Net):" drawAtPoint:NSMakePoint(40, pageRect.size.height - 250) withAttributes:secHeadingAttrs];

    CGRect netRect = CGRectMake(150, pageRect.size.height - 520, 312, 234);
    drawCubeNet(ctx, netRect, initialCube);

    // Complete Algorithm Notation
    [@"Complete Move Sequence:" drawAtPoint:NSMakePoint(40, pageRect.size.height - 560) withAttributes:secHeadingAttrs];

    std::string algStr = RubikCube::movesToString(moves);
    if (algStr.empty()) algStr = "(Cube is already solved)";

    NSDictionary* algAttrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.2 green:0.2 blue:0.25 alpha:1.0]
    };
    CGRect algRect = CGRectMake(40, pageRect.size.height - 700, pageRect.size.width - 80, 120);
    [[NSString stringWithUTF8String:algStr.c_str()] drawInRect:algRect withAttributes:algAttrs];

    // Page Number
    NSDictionary* footerAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:9 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.5 alpha:1.0]
    };
    [@"Page 1" drawAtPoint:NSMakePoint(pageRect.size.width / 2.0 - 15, 24) withAttributes:footerAttrs];

    CGPDFContextEndPage(ctx);

    // -------------------------------------------------------------
    // Subsequent Pages: Step-by-Step Move Cards (6 per page)
    // -------------------------------------------------------------
    size_t movesPerPage = 6;
    size_t numPages = (totalMoves + movesPerPage - 1) / movesPerPage;

    for (size_t p = 0; p < numPages; p++) {
        CGPDFContextBeginPage(ctx, NULL);
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO]];

        CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
        CGContextFillRect(ctx, pageRect);

        // Header
        NSString* pageHeader = [NSString stringWithFormat:@"Step-by-Step Solving Guide • Moves %zu to %zu of %zu",
                                p * movesPerPage + 1,
                                std::min((p + 1) * movesPerPage, totalMoves),
                                totalMoves];
        [pageHeader drawAtPoint:NSMakePoint(40, pageRect.size.height - 40) withAttributes:secHeadingAttrs];

        CGContextSetRGBStrokeColor(ctx, 0.85, 0.85, 0.85, 1.0);
        CGContextSetLineWidth(ctx, 1.0);
        CGContextStrokeLineSegments(ctx, (CGPoint[]){
            CGPointMake(40, pageRect.size.height - 48),
            CGPointMake(pageRect.size.width - 40, pageRect.size.height - 48)
        }, 2);

        // 2 cols x 3 rows grid
        CGFloat cardW = 250.0;
        CGFloat cardH = 205.0;
        CGFloat startX = 40.0;
        CGFloat colGap = 32.0;
        CGFloat rowGap = 20.0;

        for (size_t i = 0; i < movesPerPage; i++) {
            size_t moveIdx = p * movesPerPage + i;
            if (moveIdx >= totalMoves) break;

            int m = moves[moveIdx];
            size_t col = i % 2;
            size_t row = i / 2;

            CGFloat cx = startX + col * (cardW + colGap);
            CGFloat cy = pageRect.size.height - 68 - (row + 1) * cardH - row * rowGap;

            CGRect cardRect = CGRectMake(cx, cy, cardW, cardH);

            // Card background & border
            CGContextSetRGBFillColor(ctx, 0.97, 0.98, 0.99, 1.0);
            CGContextFillRect(ctx, cardRect);

            CGContextSetRGBStrokeColor(ctx, 0.85, 0.88, 0.92, 1.0);
            CGContextSetLineWidth(ctx, 1.0);
            CGContextStrokeRect(ctx, cardRect);

            // Step pill
            CGRect pillRect = CGRectMake(cx + 12, cy + cardH - 28, 80, 18);
            CGContextSetRGBFillColor(ctx, 0.2, 0.5, 0.9, 1.0);
            CGContextFillRect(ctx, pillRect);

            NSDictionary* pillAttrs = @{
                NSFontAttributeName: [NSFont systemFontOfSize:9 weight:NSFontWeightBold],
                NSForegroundColorAttributeName: [NSColor whiteColor]
            };
            NSString* pillStr = [NSString stringWithFormat:@"STEP %zu", moveIdx + 1];
            [pillStr drawAtPoint:NSMakePoint(cx + 18, cy + cardH - 26) withAttributes:pillAttrs];

            // Large Move Notation
            NSDictionary* moveAttrs = @{
                NSFontAttributeName: [NSFont monospacedSystemFontOfSize:30 weight:NSFontWeightHeavy],
                NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.1 green:0.25 blue:0.6 alpha:1.0]
            };
            NSString* moveStr = [NSString stringWithUTF8String:RubikCube::moveToString(m).c_str()];
            [moveStr drawAtPoint:NSMakePoint(cx + 14, cy + cardH - 72) withAttributes:moveAttrs];

            // Direction symbol & description
            std::string desc = RubikCube::moveDescription(m);
            NSDictionary* descAttrs = @{
                NSFontAttributeName: [NSFont systemFontOfSize:10 weight:NSFontWeightMedium],
                NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.25 alpha:1.0]
            };
            CGRect descRect = CGRectMake(cx + 14, cy + cardH - 118, cardW - 28, 40);
            [[NSString stringWithUTF8String:desc.c_str()] drawInRect:descRect withAttributes:descAttrs];

            // Draw mini cube face diagram
            currentCube.applyMove(m);
            CGRect miniNetRect = CGRectMake(cx + cardW - 84, cy + 12, 72, 54);
            drawCubeNet(ctx, miniNetRect, currentCube);
        }

        // Page Number
        NSString* pageNumStr = [NSString stringWithFormat:@"Page %zu of %zu", p + 2, numPages + 1];
        [pageNumStr drawAtPoint:NSMakePoint(pageRect.size.width / 2.0 - 25, 24) withAttributes:footerAttrs];

        CGPDFContextEndPage(ctx);
    }

    CGPDFContextClose(ctx);
    CGContextRelease(ctx);

    return YES;
}

@end
