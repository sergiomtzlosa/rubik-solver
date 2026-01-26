//
//  RubikHelpWindowController.mm
//  RubikSolver - In-App Help & User Guide Window
//

#import "RubikHelpWindowController.h"

@implementation RubikHelpWindowController

+ (instancetype)sharedHelpController {
    static RubikHelpWindowController* sInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sInstance = [[RubikHelpWindowController alloc] init];
    });
    return sInstance;
}

- (instancetype)init {
    NSRect frame = NSMakeRect(200, 200, 740, 640);
    NSWindowStyleMask style = NSWindowStyleMaskTitled |
                              NSWindowStyleMaskClosable |
                              NSWindowStyleMaskResizable;

    NSWindow* window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Rubik's Solver - User Guide & Help";
    window.minSize = NSMakeSize(580, 480);
    window.backgroundColor = [NSColor colorWithCalibratedRed:0.12 green:0.13 blue:0.16 alpha:1.0];

    self = [super initWithWindow:window];
    if (self) {
        [self setupContent];
    }
    return self;
}

- (void)setupContent {
    NSView* contentView = self.window.contentView;
    NSRect b = contentView.bounds;

    NSScrollView* scrollView = [[NSScrollView alloc] initWithFrame:b];
    scrollView.hasVerticalScroller = YES;
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scrollView.drawsBackground = NO;

    NSTextView* textView = [[NSTextView alloc] initWithFrame:scrollView.bounds];
    textView.editable = NO;
    textView.selectable = YES;
    textView.backgroundColor = [NSColor colorWithCalibratedRed:0.11 green:0.12 blue:0.15 alpha:1.0];
    textView.textContainerInset = NSMakeSize(28, 28);
    textView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSMutableAttributedString* text = [[NSMutableAttributedString alloc] init];

    auto addHeading = ^(NSString* str) {
        NSDictionary* attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:22 weight:NSFontWeightBold],
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.35 green:0.65 blue:1.0 alpha:1.0]
        };
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:[str stringByAppendingString:@"\n\n"] attributes:attrs]];
    };

    auto addSubheading = ^(NSString* str) {
        NSDictionary* attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:15 weight:NSFontWeightBold],
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.95 green:0.80 blue:0.25 alpha:1.0]
        };
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:[str stringByAppendingString:@"\n"] attributes:attrs]];
    };

    auto addBody = ^(NSString* str) {
        NSDictionary* attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.90 alpha:1.0],
            NSParagraphStyleAttributeName: ({
                NSMutableParagraphStyle* p = [[NSMutableParagraphStyle alloc] init];
                p.lineSpacing = 4.0;
                p.paragraphSpacing = 14.0;
                p;
            })
        };
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:[str stringByAppendingString:@"\n\n"] attributes:attrs]];
    };

    auto addCode = ^(NSString* str) {
        NSDictionary* attrs = @{
            NSFontAttributeName: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.4 green:0.85 blue:0.6 alpha:1.0],
            NSParagraphStyleAttributeName: ({
                NSMutableParagraphStyle* p = [[NSMutableParagraphStyle alloc] init];
                p.lineSpacing = 3.0;
                p.paragraphSpacing = 12.0;
                p;
            })
        };
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:[str stringByAppendingString:@"\n\n"] attributes:attrs]];
    };

    addHeading(@"Rubik's Cube Solver — User Guide");

    addSubheading(@"1. Quick Start (Solving in 3 Steps)");
    addBody(@"• Step 1: Input your cube state by scanning with your camera (📷 Camera button) or generate a scramble (🎲 Scramble button).\n"
            @"• Step 2: Click '⚡ Solve' to run the selected engine (Exact, Neural, or Hybrid). The solution is verified before it is shown.\n"
            @"• Step 3: Use the step panel on the right to walk through the solution step-by-step or press '▶ Play' for auto-play.\n\n"
            @"The toolbar '🔀 Random' button only scrambles the cube; it does not start a solve. Use Actions -> Random Cube & Solve when you want both in one step.");

    addSubheading(@"2. Camera Scanner & 6-Face Recognition");
    addBody(@"Click the '📷 Camera' button to open the live augmented-reality viewfinder HUD.\n\n"
            @"Scanning sequence (follow the on-screen guide):\n"
            @"  1. Top Face    — White center\n"
            @"  2. Right Face  — Red center\n"
            @"  3. Front Face  — Green center\n"
            @"  4. Down Face   — Yellow center\n"
            @"  5. Left Face   — Orange center\n"
            @"  6. Back Face   — Blue center\n\n"
            @"Tips for accurate color detection:\n"
            @"• Hold the cube 8–12 inches away from the webcam inside the 3x3 alignment squares.\n"
            @"• Avoid strong glare or reflection from direct sunlight.\n"
            @"• Look at the letter badges (W, R, G, Y, O, B) inside each square to confirm color accuracy before clicking '📸 Capture Face'.");

    addSubheading(@"3. Cube Faces Photo Upload & Recognition");
    addBody(@"Click the '🖼️ Photos' button in the toolbar (or File -> Upload Cube Face Photos... / ⌘U) to open the 6-face photo upload view.\n\n"
            @"• Upload photos for each of the 6 cube faces (Top, Front, Right, Down, Left, Back) individually or in batch.\n"
            @"• Drag and drop image files directly from Finder onto any face card or window.\n"
            @"• Faces are automatically identified by their center sticker color.\n"
            @"• Tap any square on the mini 3x3 grid to quickly cycle colors, or click '✏️ Adjust' to fine-tune the recognition ROI frame.\n"
            @"• Click '🎲 Load Sample Photos' for an instant demonstration, or '⚡ Apply & Solve' to solve immediately with the selected engine. If the neural search cannot finish, it completes with the exact solver and reports 'Neural · exact fallback'.");

    addSubheading(@"4. Interactive 3D Cube Viewer");
    addBody(@"• Orbit Rotation: Click and drag with your mouse or trackpad anywhere on the 3D viewer to inspect all sides of the cube.\n"
            @"• Zooming: Pinch on the trackpad or use the scroll wheel to zoom in and out.\n"
            @"• Center 3D View Shortcut: Press ⌘0, Spacebar, 'C', or double-click anywhere on the viewport to instantly reset the camera to the optimal centered isometric perspective.\n"
            @"• Smooth Turn Animations: Every move is animated with physical 3D layer rotations and cubic-bezier easing curves.");

    addSubheading(@"5. Step-by-Step Solving Dashboard");
    addBody(@"The right-hand panel gives you full control over the solution process:\n\n"
            @"• Current Step Card: Shows large bold Singmaster notation (e.g. R', U2, F) and a clear plain-English explanation.\n"
            @"• [Next ▶] / [◀ Prev]: Step forward or reverse a step with synchronized 3D animations.\n"
            @"• [▶ Play] / [⏸ Pause]: Automatically animates through the entire sequence of moves.\n"
            @"• Speed Selector: Adjust animation tempo between 0.5x, 1.0x, and 2.0x.\n"
            @"• All Steps Table: Displays all moves in a scrollable list. Click any row to jump directly to that step!");

    addSubheading(@"6. Exporting PDF Solution Manual");
    addBody(@"Click '📄 Export PDF Guide' at the bottom of the right panel.\n\n"
            @"This generates a high-resolution, multi-page illustrated PDF manual:\n"
            @"• Page 1: Overview, initial scramble, metadata, and complete 2D unfolded cube net.\n"
            @"• Pages 2+: Step-by-step cards (6 per page) showing move notations, rotation direction arrows (↻, ↺, ⟲), descriptions, and diagram previews.\n"
            @"• The generated PDF automatically opens in Preview for printing or sharing.");

    addSubheading(@"7. Singmaster Move Notation Reference");
    addCode(@"Base Moves (90° Clockwise):\n"
            @"  U = Top Face (White)       D = Bottom Face (Yellow)\n"
            @"  R = Right Face (Red)       L = Left Face (Orange)\n"
            @"  F = Front Face (Green)     B = Back Face (Blue)\n\n"
            @"Modifiers:\n"
            @"  ' (Prime) = 90° Counter-Clockwise (e.g. R', U', F')\n"
            @"  2         = 180° Half Turn        (e.g. R2, U2, F2)");

    [textView.textStorage setAttributedString:text];
    scrollView.documentView = textView;
    [contentView addSubview:scrollView];
}

- (void)showHelpWindow {
    [self.window makeKeyAndOrderFront:nil];
    [self.window center];
    [NSApp activateIgnoringOtherApps:YES];
}

@end
