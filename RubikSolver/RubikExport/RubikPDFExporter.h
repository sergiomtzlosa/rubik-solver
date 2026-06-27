//
//  RubikPDFExporter.h
//  RubikSolver - Illustrated PDF Solution Manual Exporter
//

#import <AppKit/AppKit.h>
#if __has_include("../RubikCore/RubikCube.h")
#include "../RubikCore/RubikCube.h"
#else
#include "RubikCube.h"
#endif
#include <vector>

@interface RubikPDFExporter : NSObject

// Prompts user with NSSavePanel and exports PDF
+ (void)exportSolutionWithWindow:(NSWindow*)parentWindow
                     initialCube:(const RubikCube&)initialCube
                           moves:(const std::vector<int>&)moves
                     solveTimeMs:(double)timeMs;

// Directly renders PDF data into destination file URL
+ (BOOL)renderSolutionToURL:(NSURL*)fileURL
                initialCube:(const RubikCube&)initialCube
                      moves:(const std::vector<int>&)moves
                solveTimeMs:(double)timeMs
                      error:(NSError**)outError;

@end
