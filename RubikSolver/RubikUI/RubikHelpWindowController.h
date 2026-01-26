//
//  RubikHelpWindowController.h
//  RubikSolver - In-App Help & User Guide Window
//

#import <AppKit/AppKit.h>

@interface RubikHelpWindowController : NSWindowController

+ (instancetype)sharedHelpController;
- (void)showHelpWindow;

@end
