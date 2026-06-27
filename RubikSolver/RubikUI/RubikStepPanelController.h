//
//  RubikStepPanelController.h
//  RubikSolver - Right-Side Step-by-Step Solving Dashboard
//

#import <AppKit/AppKit.h>
#include <vector>
#include <string>

NS_ASSUME_NONNULL_BEGIN

@protocol RubikStepPanelDelegate <NSObject>
- (void)stepPanelDidRequestMove:(int)move isInverse:(BOOL)isInverse;
- (void)stepPanelDidJumpToStep:(NSInteger)stepIndex;
- (void)stepPanelDidRequestAutoPlay:(BOOL)start;
- (void)stepPanelDidChangeSpeed:(NSTimeInterval)duration;
- (void)stepPanelDidRequestPDFExport;
- (void)stepPanelDidRequestScramble;
- (void)stepPanelDidRequestCamera;
- (void)stepPanelDidRequestSolve;
- (void)stepPanelDidRequestCopyState;
@end

@interface RubikStepPanelController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, weak, nullable) id<RubikStepPanelDelegate> delegate;
@property (nonatomic, readonly) NSInteger currentStepIndex;
@property (nonatomic, readonly) const std::vector<int>& solutionMoves;
@property (nonatomic, readonly) BOOL isAutoPlaying;

- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (instancetype)init;

// Update with newly computed solution
- (void)setSolutionMoves:(const std::vector<int>&)moves solveTimeMs:(double)timeMs;

// Show a solver status in the empty solution area (invalid state, timeout, ...).
- (void)setSolverStatusText:(NSString*)text;

// Which engine produced the current solution, and whether Core ML placement
// was verified on the GPU. Updates the badge in the sidebar.
- (void)setEngineDescription:(NSString*)description gpuVerified:(BOOL)verified;

// Navigation
- (void)goToNextStep;
- (void)goToPreviousStep;
- (void)resetToStart;
- (void)startAutoPlay;
- (void)stopAutoPlay;
- (void)onPlayClicked:(nullable id)sender;

// External notification when animation finishes
- (void)didCompleteStepMove;

@end

NS_ASSUME_NONNULL_END
