//
//  RubikColorClassifier.mm
//  RubikSolver - Real-Time Rubik Facelet Color Recognition
//

#import "RubikColorClassifier.h"

#include <algorithm>
#include <array>
#include <cmath>

namespace {

using RGB = std::array<float, 3>;

/// Average the inner portion of each 3x3 cell. Sampling away from the cell
/// borders avoids capturing the black plastic between stickers.
std::vector<RGB> sampleCells(const uint8_t* base,
                             size_t width,
                             size_t height,
                             size_t bytesPerRow,
                             size_t bytesPerPixel,
                             bool bgra,
                             CGRect normalizedROI) {
    std::vector<RGB> cells;
    cells.reserve(9);
    if (!base || width == 0 || height == 0) return cells;

    const CGFloat rw = normalizedROI.size.width * width;
    const CGFloat rh = normalizedROI.size.height * height;
    if (rw < 3.0 || rh < 3.0) return cells;

    const CGFloat cellW = rw / 3.0;
    const CGFloat cellH = rh / 3.0;
    const int radius = std::max(1, static_cast<int>(std::min(cellW, cellH) * 0.18));

    for (int row = 0; row < 3; ++row) {
        for (int col = 0; col < 3; ++col) {
            const CGFloat normalizedX = normalizedROI.origin.x +
                (col + 0.5) * normalizedROI.size.width / 3.0;
            const CGFloat normalizedY = normalizedROI.origin.y +
                (row + 0.5) * normalizedROI.size.height / 3.0;
            const int cx = static_cast<int>(normalizedX * width);
            const int cy = static_cast<int>(normalizedY * height);

            double sumR = 0.0;
            double sumG = 0.0;
            double sumB = 0.0;
            int count = 0;

            for (int dy = -radius; dy <= radius; ++dy) {
                const int py = cy + dy;
                if (py < 0 || py >= static_cast<int>(height)) continue;
                const uint8_t* rowPtr = base + static_cast<size_t>(py) * bytesPerRow;
                for (int dx = -radius; dx <= radius; ++dx) {
                    const int px = cx + dx;
                    if (px < 0 || px >= static_cast<int>(width)) continue;
                    const uint8_t* pixel = rowPtr + static_cast<size_t>(px) * bytesPerPixel;
                    if (bgra) {
                        sumB += pixel[0];
                        sumG += pixel[1];
                        sumR += pixel[2];
                    } else {
                        sumR += pixel[0];
                        sumG += pixel[1];
                        sumB += pixel[2];
                    }
                    ++count;
                }
            }

            if (count > 0) {
                cells.push_back(RGB{
                    static_cast<float>(sumR / (count * 255.0)),
                    static_cast<float>(sumG / (count * 255.0)),
                    static_cast<float>(sumB / (count * 255.0))
                });
            } else {
                cells.push_back(RGB{0.5f, 0.5f, 0.5f});
            }
        }
    }
    return cells;
}

SampledPatch patchFromReading(const RubikColorReading& reading) {
    SampledPatch patch;
    patch.colorIndex = reading.colorIndex;
    patch.r = reading.r;
    patch.g = reading.g;
    patch.b = reading.b;
    patch.h = reading.h;
    patch.s = reading.s;
    patch.v = reading.v;
    patch.labL = reading.lab.L;
    patch.labA = reading.lab.a;
    patch.labB = reading.lab.b;
    patch.confidence = reading.confidence;
    patch.reliable = reading.reliable;
    patch.background = reading.background;
    return patch;
}

std::vector<SampledPatch> patchesFromReadings(const std::vector<RubikColorReading>& readings) {
    std::vector<SampledPatch> patches;
    patches.reserve(readings.size());
    for (const auto& reading : readings) {
        patches.push_back(patchFromReading(reading));
    }
    return patches;
}

std::vector<RubikColorReading> analyzeCells(
    const std::vector<RGB>& cells,
    const std::array<RubikLabColor, NUM_COLORS>& prototypes,
    bool calibrated,
    bool applyGreyWorld) {
    std::vector<RubikColorReading> readings;
    readings.reserve(cells.size());
    if (cells.empty()) return readings;

    // Grey-world balance helps live camera frames under mixed lighting, but it
    // is actively harmful on a still photo of a single face: a red face biases
    // every channel toward red, so red stickers get reclassified as blue.
    // Uploaded images are already colour-managed by macOS, so analyze them raw.
    RubikWhiteBalance balance;
    if (applyGreyWorld) {
        balance = RubikWhiteBalance::grayWorld(cells);
    }
    for (const RGB& cell : cells) {
        const float r = std::min(1.0f, cell[0] * balance.scaleR);
        const float g = std::min(1.0f, cell[1] * balance.scaleG);
        const float b = std::min(1.0f, cell[2] * balance.scaleB);
        RubikColorReading reading = RubikColorMath::analyze(r, g, b, prototypes, calibrated);
        reading.rawR = cell[0];
        reading.rawG = cell[1];
        reading.rawB = cell[2];
        readings.push_back(reading);
    }
    return readings;
}

} // namespace

@implementation RubikColorClassifier

- (std::vector<SampledPatch>)classifyGridFromPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                              normalizedROI:(CGRect)roi {
    return patchesFromReadings([self readingsFromPixelBuffer:pixelBuffer normalizedROI:roi]);
}

- (std::vector<RubikColorReading>)readingsFromPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                             normalizedROI:(CGRect)roi {
    std::vector<RubikColorReading> readings;
    if (!pixelBuffer) return readings;

    const OSType format = CVPixelBufferGetPixelFormatType(pixelBuffer);
    if (format != kCVPixelFormatType_32BGRA &&
        format != kCVPixelFormatType_32RGBA &&
        format != kCVPixelFormatType_32ARGB) {
        return readings;
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    uint8_t* base = static_cast<uint8_t*>(CVPixelBufferGetBaseAddress(pixelBuffer));
    const size_t width = CVPixelBufferGetWidth(pixelBuffer);
    const size_t height = CVPixelBufferGetHeight(pixelBuffer);
    const size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);

    if (base) {
        const bool bgra = (format == kCVPixelFormatType_32BGRA);
        const std::vector<RGB> cells = sampleCells(base, width, height, bytesPerRow,
                                                   4, bgra, roi);
        readings = analyzeCells(cells, RubikColorMath::defaultPrototypes(), false, true);
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    return readings;
}

- (std::vector<SampledPatch>)classifyGridFromImage:(NSImage*)image
                                     normalizedROI:(CGRect)roi {
    if (!image) return {};
    CGImageRef cgImage = [image CGImageForProposedRect:nil context:nil hints:nil];
    return [self classifyGridFromCGImage:cgImage normalizedROI:roi];
}

- (std::vector<SampledPatch>)classifyGridFromCGImage:(CGImageRef)cgImage
                                       normalizedROI:(CGRect)roi {
    std::vector<SampledPatch> patches;
    if (!cgImage) return patches;

    const size_t width = CGImageGetWidth(cgImage);
    const size_t height = CGImageGetHeight(cgImage);
    if (width == 0 || height == 0) return patches;

    const size_t bytesPerRow = width * 4;
    std::vector<uint8_t> rawData(height * bytesPerRow);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(rawData.data(), width, height, 8,
                                                 bytesPerRow, colorSpace,
                                                 kCGImageAlphaPremultipliedLast |
                                                 kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!context) return patches;

    // Draw without the usual CGContext vertical flip: a CGBitmapContext row 0
    // then corresponds to the top row of the source image, which is what
    // NSImage uploads and the on-screen 3x3 grid expect.
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
    CGContextRelease(context);

    const std::vector<RGB> cells = sampleCells(rawData.data(), width, height,
                                               bytesPerRow, 4, false, roi);
    return patchesFromReadings(analyzeCells(cells, RubikColorMath::defaultPrototypes(), false, false));
}

- (std::vector<SampledPatch>)classifyReadings:(const std::vector<RubikColorReading>&)readings
                              withPrototypes:(const std::array<RubikLabColor, NUM_COLORS>&)prototypes
                        calibratedPrototypes:(BOOL)calibrated {
    std::vector<SampledPatch> patches;
    patches.reserve(readings.size());
    for (const RubikColorReading& reading : readings) {
        RubikColorReading updated =
            RubikColorMath::analyze(reading.r, reading.g, reading.b, prototypes, calibrated);
        patches.push_back(patchFromReading(updated));
    }
    return patches;
}

+ (NSColor*)nsColorForIndex:(uint8_t)colorIndex {
    switch (colorIndex) {
        case COLOR_WHITE:  return [NSColor colorWithSRGBRed:0.95 green:0.95 blue:0.94 alpha:1.0];
        case COLOR_RED:    return [NSColor colorWithSRGBRed:0.86 green:0.16 blue:0.18 alpha:1.0];
        case COLOR_GREEN:  return [NSColor colorWithSRGBRed:0.10 green:0.66 blue:0.32 alpha:1.0];
        case COLOR_YELLOW: return [NSColor colorWithSRGBRed:0.98 green:0.80 blue:0.10 alpha:1.0];
        case COLOR_ORANGE: return [NSColor colorWithSRGBRed:0.96 green:0.47 blue:0.08 alpha:1.0];
        case COLOR_BLUE:   return [NSColor colorWithSRGBRed:0.12 green:0.38 blue:0.86 alpha:1.0];
        default:           return [NSColor colorWithSRGBRed:0.32 green:0.34 blue:0.38 alpha:1.0];
    }
}

+ (NSString*)colorNameForIndex:(uint8_t)colorIndex {
    switch (colorIndex) {
        case COLOR_WHITE:  return @"White (Up)";
        case COLOR_RED:    return @"Red (Right)";
        case COLOR_GREEN:  return @"Green (Front)";
        case COLOR_YELLOW: return @"Yellow (Down)";
        case COLOR_ORANGE: return @"Orange (Left)";
        case COLOR_BLUE:   return @"Blue (Back)";
        default:           return @"Unknown";
    }
}

@end
