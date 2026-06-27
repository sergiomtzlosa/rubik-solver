//
//  RubikFaceUploadSheetController.h
//  RubikSolver - 6-Face Photo Upload & Recognition Sheet
//

#import <AppKit/AppKit.h>
#import "RubikColorClassifier.h"
#import "RubikCube.h"
#include <vector>

typedef void (^RubikFaceUploadCompletion)(int faceIndex, const std::vector<uint8_t>& facelets, BOOL autoSolve);
typedef void (^RubikCubeUploadCompletion)(const uint8_t facelets[54], uint8_t configuredMask, BOOL autoSolve);

@interface RubikFaceUploadSheetController : NSWindowController

+ (instancetype)sharedController;

// Displays the multi-face upload view to upload each face image of the cube
- (void)showCubeUploadSheetForWindow:(NSWindow*)parentWindow
                           cubeModel:(const RubikCube&)cubeModel
                          classifier:(RubikColorClassifier*)classifier
                 configuredFacesMask:(uint8_t)configuredFacesMask
                          completion:(RubikCubeUploadCompletion)completion;

// Prompts user to pick an image file and displays the face review sheet (backwards compatible)
- (void)promptAndRecognizeFaceForWindow:(NSWindow*)parentWindow
                             classifier:(RubikColorClassifier*)classifier
                             completion:(RubikFaceUploadCompletion)completion;

- (void)promptAndRecognizeFaceForWindow:(NSWindow*)parentWindow
                             classifier:(RubikColorClassifier*)classifier
                    configuredFacesMask:(uint8_t)configuredFacesMask
                             completion:(RubikFaceUploadCompletion)completion;

@end

