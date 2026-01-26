//
//  RubikRandomGeneratorSheetController.h
//  RubikSolver - Random Cube Generator & Metal Solver Sheet
//

#import <AppKit/AppKit.h>
#include <vector>
#if __has_include("../RubikCore/RubikCube.h")
#include "../RubikCore/RubikCube.h"
#else
#include "RubikCube.h"
#endif

typedef void (^RubikRandomGeneratorCompletion)(const RubikCube& scrambledCube, const std::vector<int>& scrambleMoves, BOOL autoSolve);

@interface RubikRandomGeneratorSheetController : NSWindowController

+ (instancetype)sharedController;

- (void)showGeneratorSheetForWindow:(NSWindow*)parentWindow
                         completion:(RubikRandomGeneratorCompletion)completion;

@end
