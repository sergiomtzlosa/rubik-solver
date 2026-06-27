//
//  RubikTheme.mm
//  RubikSolver - Studio Dark Design System
//

#import "RubikTheme.h"

@implementation RubikTheme

+ (NSColor*)background {
    return [NSColor colorWithSRGBRed:0.052 green:0.058 blue:0.072 alpha:1.0];
}

+ (NSColor*)sidebar {
    return [NSColor colorWithSRGBRed:0.070 green:0.077 blue:0.094 alpha:1.0];
}

+ (NSColor*)card {
    return [NSColor colorWithSRGBRed:0.096 green:0.105 blue:0.126 alpha:1.0];
}

+ (NSColor*)cardElevated {
    return [NSColor colorWithSRGBRed:0.120 green:0.131 blue:0.158 alpha:1.0];
}

+ (NSColor*)separator {
    return [NSColor colorWithSRGBRed:0.20 green:0.21 blue:0.25 alpha:0.8];
}

+ (NSColor*)accent {
    return [NSColor colorWithSRGBRed:0.20 green:0.82 blue:0.76 alpha:1.0];
}

+ (NSColor*)accentSoft {
    return [NSColor colorWithSRGBRed:0.20 green:0.82 blue:0.76 alpha:0.16];
}

+ (NSColor*)success {
    return [NSColor colorWithSRGBRed:0.34 green:0.86 blue:0.54 alpha:1.0];
}

+ (NSColor*)warning {
    return [NSColor colorWithSRGBRed:0.98 green:0.66 blue:0.24 alpha:1.0];
}

+ (NSColor*)danger {
    return [NSColor colorWithSRGBRed:0.96 green:0.36 blue:0.38 alpha:1.0];
}

+ (NSColor*)textPrimary {
    return [NSColor colorWithSRGBRed:0.96 green:0.97 blue:0.98 alpha:1.0];
}

+ (NSColor*)textSecondary {
    return [NSColor colorWithSRGBRed:0.68 green:0.71 blue:0.77 alpha:1.0];
}

+ (NSColor*)textTertiary {
    return [NSColor colorWithSRGBRed:0.46 green:0.49 blue:0.55 alpha:1.0];
}

+ (NSFont*)titleFont {
    return [NSFont systemFontOfSize:22 weight:NSFontWeightBold];
}

+ (NSFont*)headingFont {
    return [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
}

+ (NSFont*)bodyFont {
    return [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular];
}

+ (NSFont*)captionFont {
    return [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
}

+ (NSFont*)monoFontOfSize:(CGFloat)size weight:(NSFontWeight)weight {
    return [NSFont monospacedSystemFontOfSize:size weight:weight];
}

+ (nullable NSImage*)symbolNamed:(NSString*)name
                            size:(CGFloat)size
                          weight:(NSFontWeight)weight {
    NSImage* image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:name];
    if (!image) return nil;
    NSImageSymbolConfiguration* configuration =
        [NSImageSymbolConfiguration configurationWithPointSize:size weight:weight];
    return [image imageWithSymbolConfiguration:configuration];
}

+ (NSTextField*)labelWithText:(NSString*)text
                         font:(NSFont*)font
                        color:(NSColor*)color {
    NSTextField* label = [NSTextField labelWithString:text ?: @""];
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

+ (NSButton*)symbolButton:(NSString*)symbol
                  tooltip:(NSString*)tooltip
                   target:(id)target
                   action:(SEL)action {
    NSButton* button = [NSButton buttonWithImage:[self symbolNamed:symbol size:13 weight:NSFontWeightSemibold]
                                          target:target
                                          action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.bordered = NO;
    button.contentTintColor = [self textSecondary];
    button.toolTip = tooltip;
    return button;
}

+ (NSButton*)filledButton:(NSString*)title
                   symbol:(NSString*)symbol
                   target:(id)target
                   action:(SEL)action {
    NSButton* button = [NSButton buttonWithTitle:title target:target action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.bordered = NO;
    button.wantsLayer = YES;
    button.layer.cornerRadius = 9.0;
    button.layer.backgroundColor = [self accent].CGColor;
    button.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightSemibold];
    button.contentTintColor = [NSColor colorWithSRGBRed:0.03 green:0.10 blue:0.09 alpha:1.0];
    if (symbol) {
        button.image = [self symbolNamed:symbol size:12 weight:NSFontWeightBold];
        button.imagePosition = NSImageLeading;
    }
    return button;
}

+ (NSButton*)softButton:(NSString*)title
                 symbol:(NSString*)symbol
                 target:(id)target
                 action:(SEL)action {
    NSButton* button = [NSButton buttonWithTitle:title target:target action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.bordered = NO;
    button.wantsLayer = YES;
    button.layer.cornerRadius = 9.0;
    button.layer.backgroundColor = [NSColor colorWithWhite:1.0 alpha:0.07].CGColor;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.08].CGColor;
    button.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium];
    button.contentTintColor = [self textPrimary];
    if (symbol) {
        button.image = [self symbolNamed:symbol size:12 weight:NSFontWeightMedium];
        button.imagePosition = NSImageLeading;
    }
    return button;
}

+ (void)applyCardStyle:(NSView*)view elevated:(BOOL)elevated {
    view.wantsLayer = YES;
    view.layer.cornerRadius = 14.0;
    view.layer.backgroundColor = (elevated ? [self cardElevated] : [self card]).CGColor;
    view.layer.borderWidth = 1.0;
    view.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.06].CGColor;
}

@end

@implementation RubikProgressView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _doubleValue = 0.0;
        self.wantsLayer = YES;
        [self setAccessibilityElement:YES];
        self.accessibilityRole = NSAccessibilityProgressIndicatorRole;
        self.accessibilityLabel = @"Solve progress";
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setDoubleValue:(double)doubleValue {
    _doubleValue = MAX(0.0, MIN(1.0, doubleValue));
    self.accessibilityValue = @(_doubleValue);
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    const NSRect track = NSInsetRect(self.bounds, 0, 1);
    NSBezierPath* trackPath = [NSBezierPath bezierPathWithRoundedRect:track
                                                              xRadius:track.size.height / 2.0
                                                              yRadius:track.size.height / 2.0];
    [[NSColor colorWithWhite:1.0 alpha:0.08] setFill];
    [trackPath fill];

    if (_doubleValue <= 0.0) return;
    NSRect fill = track;
    fill.size.width = MAX(track.size.height, track.size.width * _doubleValue);
    NSBezierPath* fillPath = [NSBezierPath bezierPathWithRoundedRect:fill
                                                             xRadius:track.size.height / 2.0
                                                             yRadius:track.size.height / 2.0];
    [[RubikTheme accent] setFill];
    [fillPath fill];
}

@end
