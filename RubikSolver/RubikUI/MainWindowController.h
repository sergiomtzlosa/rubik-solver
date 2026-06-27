//
//  MainWindowController.h
//  RubikSolver - Primary macOS Window & Application Coordinator
//

#import <AppKit/AppKit.h>
#import "Rubik3DView.h"
#import "RubikStepPanelController.h"

#if __has_include("../RubikVision/RubikCameraOverlayView.h")
#import "../RubikVision/RubikCameraOverlayView.h"
#else
#import "RubikCameraOverlayView.h"
#endif

#if __has_include("../RubikCore/RubikMetalSolver.h")
#import "../RubikCore/RubikMetalSolver.h"
#else
#import "RubikMetalSolver.h"
#endif

#if __has_include("../RubikExport/RubikPDFExporter.h")
#import "../RubikExport/RubikPDFExporter.h"
#else
#import "RubikPDFExporter.h"
#endif

#if __has_include("../RubikCore/RubikCube.h")
#include "../RubikCore/RubikCube.h"
#else
#include "RubikCube.h"
#endif

@interface MainWindowController : NSWindowController <RubikStepPanelDelegate, Rubik3DViewDelegate, RubikCameraOverlayDelegate>

- (instancetype)init;
- (void)uploadFaceImage;
- (void)generateRandomCubeAndSolveDefault;
- (void)openRandomCubeGeneratorSheet;
- (void)solveWithMetalGPU;
- (void)stopSolver;
- (void)copyCubeStateForOpenCode;
- (void)toggleCameraScanner;
- (void)showCameraScanner;
- (void)closeCameraScanner;
- (void)resetCubeToSolved;
- (void)resetView3DToViewport;
- (IBAction)centerView3DMenuAction:(id)sender;

@end
