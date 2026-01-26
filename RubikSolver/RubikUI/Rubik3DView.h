//
//  Rubik3DView.h
//  RubikSolver - 3D Interactive Animated Rubik's Cube Viewer
//

#import <SceneKit/SceneKit.h>
#if __has_include("../RubikCore/RubikCube.h")
#include "../RubikCore/RubikCube.h"
#else
#include "RubikCube.h"
#endif

NS_ASSUME_NONNULL_BEGIN

@protocol Rubik3DViewDelegate <NSObject>
@optional
- (void)rubik3DViewDidFinishMove:(int)move;
@end

@interface Rubik3DView : SCNView

@property (nonatomic, weak, nullable) id<Rubik3DViewDelegate> rubikDelegate;
@property (nonatomic, readonly) BOOL isAnimating;
@property (nonatomic) NSTimeInterval animationDuration; // default: 0.25s

- (instancetype)initWithFrame:(NSRect)frameRect;

// Reset 3D cube to solved state
- (void)resetCube;

// Recenter and frame the 3D cube within current view bounds
- (void)centerCubeInBounds;

// Sync 3D cubies instantly to match a RubikCube state
- (void)updateWithCubeState:(const RubikCube&)cube;

// Animate a single move (e.g. MOVE_U, MOVE_R_PRIME)
// Calls completion block when rotation animation finishes
- (void)animateMove:(int)move completion:(void(^ _Nullable)(void))completion;

// Animate an inverse move (for stepping backward)
- (void)animateInverseMove:(int)move completion:(void(^ _Nullable)(void))completion;

// Scramble with animation
- (void)playMoves:(const std::vector<int>&)moves completion:(void(^ _Nullable)(void))completion;

@end

NS_ASSUME_NONNULL_END
