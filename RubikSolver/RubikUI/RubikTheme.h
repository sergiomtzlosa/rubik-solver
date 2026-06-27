//
//  RubikTheme.h
//  RubikSolver - Studio Dark Design System
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RubikTheme : NSObject

+ (NSColor*)background;
+ (NSColor*)sidebar;
+ (NSColor*)card;
+ (NSColor*)cardElevated;
+ (NSColor*)separator;
+ (NSColor*)accent;
+ (NSColor*)accentSoft;
+ (NSColor*)success;
+ (NSColor*)warning;
+ (NSColor*)danger;
+ (NSColor*)textPrimary;
+ (NSColor*)textSecondary;
+ (NSColor*)textTertiary;

+ (NSFont*)titleFont;
+ (NSFont*)headingFont;
+ (NSFont*)bodyFont;
+ (NSFont*)captionFont;
+ (NSFont*)monoFontOfSize:(CGFloat)size weight:(NSFontWeight)weight;

+ (nullable NSImage*)symbolNamed:(NSString*)name
                            size:(CGFloat)size
                          weight:(NSFontWeight)weight;

+ (NSTextField*)labelWithText:(NSString*)text
                         font:(NSFont*)font
                        color:(NSColor*)color;

+ (NSButton*)symbolButton:(NSString*)symbol
                  tooltip:(NSString*)tooltip
                   target:(nullable id)target
                   action:(nullable SEL)action;

+ (NSButton*)filledButton:(NSString*)title
                   symbol:(nullable NSString*)symbol
                   target:(nullable id)target
                   action:(nullable SEL)action;

+ (NSButton*)softButton:(NSString*)title
                 symbol:(nullable NSString*)symbol
                 target:(nullable id)target
                 action:(nullable SEL)action;

+ (void)applyCardStyle:(NSView*)view elevated:(BOOL)elevated;

@end

/// A slim, themeable progress bar.
@interface RubikProgressView : NSView
@property (nonatomic) double doubleValue; // 0...1
@end

NS_ASSUME_NONNULL_END
