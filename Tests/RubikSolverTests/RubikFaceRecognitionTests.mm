//
//  RubikFaceRecognitionTests.mm
//  RubikSolverTests - Six-face photo upload and colour recognition
//

#import <XCTest/XCTest.h>

#import "RubikColorClassifier.h"
#include "RubikCube.h"
#include "RubikTypes.h"

#include <string>
#include <vector>

namespace {

NSString* RubikSampleImagesDirectory() {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSMutableArray<NSString*>* candidates = [NSMutableArray array];

    NSString* overrideDir = NSProcessInfo.processInfo.environment[@"RUBIK_SAMPLE_IMAGES_DIR"];
    if (overrideDir.length > 0) [candidates addObject:overrideDir];

    NSString* bundleResource = [[NSBundle mainBundle] resourcePath];
    if (bundleResource.length > 0) {
        [candidates addObject:[bundleResource stringByAppendingPathComponent:@"SampleImages"]];
    }

    NSString* cwd = [fm currentDirectoryPath];
    for (int depth = 0; depth < 5 && cwd.length > 1; ++depth) {
        [candidates addObject:[cwd stringByAppendingPathComponent:@"SampleImages"]];
        cwd = [cwd stringByDeletingLastPathComponent];
    }

    NSString* sourceFile = [NSString stringWithUTF8String:__FILE__];
    if (![sourceFile isAbsolutePath]) {
        sourceFile = [[fm currentDirectoryPath] stringByAppendingPathComponent:sourceFile];
    }
    NSString* sourceDir = [sourceFile stringByDeletingLastPathComponent];
    for (int depth = 0; depth < 4 && sourceDir.length > 1; ++depth) {
        [candidates addObject:[sourceDir stringByAppendingPathComponent:@"SampleImages"]];
        sourceDir = [sourceDir stringByDeletingLastPathComponent];
    }

    for (NSString* candidate in candidates) {
        NSString* face = [candidate stringByAppendingPathComponent:@"face_0_top_white.png"];
        BOOL isDirectory = NO;
        if ([fm fileExistsAtPath:face isDirectory:&isDirectory] && !isDirectory) {
            return candidate;
        }
    }
    return nil;
}

const char* kSampleFiles[6] = {
    "face_0_top_white.png",
    "face_1_right_red.png",
    "face_2_front_green.png",
    "face_3_down_yellow.png",
    "face_4_left_orange.png",
    "face_5_back_blue.png"
};

// Expected stickers in U, R, F, D, L, B order (row-major, top-left first).
const int kExpectedFacelets[6][9] = {
    {COLOR_WHITE, COLOR_WHITE, COLOR_WHITE,
     COLOR_RED, COLOR_WHITE, COLOR_WHITE,
     COLOR_RED, COLOR_WHITE, COLOR_GREEN},
    {COLOR_ORANGE, COLOR_RED, COLOR_RED,
     COLOR_WHITE, COLOR_RED, COLOR_RED,
     COLOR_YELLOW, COLOR_RED, COLOR_RED},
    {COLOR_GREEN, COLOR_ORANGE, COLOR_WHITE,
     COLOR_GREEN, COLOR_GREEN, COLOR_BLUE,
     COLOR_GREEN, COLOR_GREEN, COLOR_RED},
    {COLOR_YELLOW, COLOR_YELLOW, COLOR_GREEN,
     COLOR_YELLOW, COLOR_YELLOW, COLOR_YELLOW,
     COLOR_YELLOW, COLOR_YELLOW, COLOR_YELLOW},
    {COLOR_ORANGE, COLOR_GREEN, COLOR_WHITE,
     COLOR_ORANGE, COLOR_ORANGE, COLOR_ORANGE,
     COLOR_ORANGE, COLOR_ORANGE, COLOR_ORANGE},
    {COLOR_BLUE, COLOR_GREEN, COLOR_BLUE,
     COLOR_BLUE, COLOR_BLUE, COLOR_BLUE,
     COLOR_BLUE, COLOR_BLUE, COLOR_BLUE},
};

} // namespace

@interface RubikFaceRecognitionTests : XCTestCase
@end

@implementation RubikFaceRecognitionTests

- (void)testBundledSampleFacesAreAvailable {
    NSString* directory = RubikSampleImagesDirectory();
    XCTAssertNotNil(directory, @"SampleImages must be copied into the app bundle");
    if (!directory) return;

    for (int face = 0; face < 6; ++face) {
        NSString* path = [directory stringByAppendingPathComponent:
            [NSString stringWithUTF8String:kSampleFiles[face]]];
        XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:path],
                      @"Missing bundled sample %@", path);
    }
}

- (void)testSampleFacesClassifyInTheCorrectOrientationAndColours {
    NSString* directory = RubikSampleImagesDirectory();
    XCTAssertNotNil(directory);
    if (!directory) return;

    RubikColorClassifier* classifier = [[RubikColorClassifier alloc] init];
    const CGRect roi = CGRectMake(0.12, 0.12, 0.76, 0.76);

    for (int face = 0; face < 6; ++face) {
        NSString* path = [directory stringByAppendingPathComponent:
            [NSString stringWithUTF8String:kSampleFiles[face]]];
        NSImage* image = [[NSImage alloc] initWithContentsOfFile:path];
        XCTAssertNotNil(image, @"Could not load %@", path);
        if (!image) continue;

        std::vector<SampledPatch> patches = [classifier classifyGridFromImage:image normalizedROI:roi];
        XCTAssertEqual(patches.size(), 9u, @"%@", path);
        if (patches.size() != 9) continue;

        for (int i = 0; i < 9; ++i) {
            XCTAssertEqual(patches[i].colorIndex, kExpectedFacelets[face][i],
                           @"%@ sticker %d was misclassified", path, i);
        }
        XCTAssertEqual(patches[4].colorIndex, face,
                       @"The centre of %@ should be face colour %d", path, face);
    }
}

- (void)testRealisticPhotoClassifiesEverySticker {
    NSString* directory = RubikSampleImagesDirectory();
    XCTAssertNotNil(directory);
    if (!directory) return;

    NSString* path = [directory stringByAppendingPathComponent:@"sample_scramble_photo.jpg"];
    NSImage* image = [[NSImage alloc] initWithContentsOfFile:path];
    XCTAssertNotNil(image, @"Could not load %@", path);
    if (!image) return;

    RubikColorClassifier* classifier = [[RubikColorClassifier alloc] init];
    std::vector<SampledPatch> patches =
        [classifier classifyGridFromImage:image normalizedROI:CGRectMake(0.12, 0.12, 0.76, 0.76)];
    XCTAssertEqual(patches.size(), 9u);
    if (patches.size() != 9) return;

    const int expected[9] = {
        COLOR_YELLOW, COLOR_BLUE,   COLOR_ORANGE,
        COLOR_GREEN,  COLOR_YELLOW, COLOR_RED,
        COLOR_WHITE,  COLOR_RED,    COLOR_BLUE,
    };
    for (int i = 0; i < 9; ++i) {
        XCTAssertEqual(patches[i].colorIndex, expected[i],
                       @"realistic photo sticker %d was misclassified", i);
    }
}

- (void)testSixSampleFacesAssembleIntoAValidScrambledCube {
    NSString* directory = RubikSampleImagesDirectory();
    XCTAssertNotNil(directory);
    if (!directory) return;

    RubikColorClassifier* classifier = [[RubikColorClassifier alloc] init];
    const CGRect roi = CGRectMake(0.12, 0.12, 0.76, 0.76);
    uint8_t facelets[54] = {0};

    for (int face = 0; face < 6; ++face) {
        NSString* path = [directory stringByAppendingPathComponent:
            [NSString stringWithUTF8String:kSampleFiles[face]]];
        NSImage* image = [[NSImage alloc] initWithContentsOfFile:path];
        if (!image) continue;

        std::vector<SampledPatch> patches = [classifier classifyGridFromImage:image normalizedROI:roi];
        if (patches.size() != 9) continue;
        for (int i = 0; i < 9; ++i) {
            facelets[face * 9 + i] = patches[i].colorIndex;
        }
    }

    RubikCube cube(facelets);
    std::string error;
    XCTAssertTrue(cube.isValidCube(&error), @"Assembled cube is invalid: %s", error.c_str());
    XCTAssertFalse(cube.isSolved());
}

@end
