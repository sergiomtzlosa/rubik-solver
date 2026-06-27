//
//  RubikColorMath.h
//  RubikSolver - Lighting-Robust Sticker Colour Analysis
//
//  Sticker recognition is done in CIELAB rather than HSV: Lab distances are
//  much less sensitive to exposure changes and LED colour casts. The scanner
//  first classifies with a generic set of prototypes, then recalibrates those
//  prototypes from the six face centres of the actual cube.
//

#ifndef RubikColorMath_h
#define RubikColorMath_h

#include "RubikTypes.h"
#include <array>
#include <cstdint>
#include <vector>

struct RubikLabColor {
    float L = 0.0f;
    float a = 0.0f;
    float b = 0.0f;
};

/// One sampled sticker after colour analysis.
struct RubikColorReading {
    float r = 0.0f;             // white-balanced RGB
    float g = 0.0f;
    float b = 0.0f;
    float rawR = 0.0f;          // original sensor RGB
    float rawG = 0.0f;
    float rawB = 0.0f;
    float h = 0.0f;
    float s = 0.0f;
    float v = 0.0f;
    RubikLabColor lab;
    uint8_t colorIndex = 255;   // 255 means "unknown / rejected"
    float confidence = 0.0f;    // 0...1
    float deltaE = 1.0e9f;      // distance to the winning prototype
    bool reliable = false;      // safe to auto-accept without review
    bool background = false;    // low-light or low-chroma rejection
};

/// A linear per-channel white-balance transform.
struct RubikWhiteBalance {
    float scaleR = 1.0f;
    float scaleG = 1.0f;
    float scaleB = 1.0f;
    bool valid = false;

    /// Grey-world estimate over a set of RGB samples. Useful before the white
    /// centre has been found (the average of a Rubik face is approximately
    /// neutral, especially once several faces are available).
    static RubikWhiteBalance grayWorld(const std::vector<std::array<float, 3>>& samples);

    /// Von Kries-style balance that maps the reference to neutral.
    static RubikWhiteBalance fromWhiteReference(float r, float g, float b);

    /// Combine two transforms (used to refine grey-world with a white centre).
    RubikWhiteBalance combinedWith(const RubikWhiteBalance& other) const;
};

class RubikColorMath {
public:
    static RubikLabColor labFromRGB(float r, float g, float b);
    static float deltaE(const RubikLabColor& lhs, const RubikLabColor& rhs);
    static float chroma(const RubikLabColor& lab);

    /// Generic sticker prototypes in U, R, F, D, L, B (white, red, green,
    /// yellow, orange, blue) order.
    static const std::array<RubikLabColor, NUM_COLORS>& defaultPrototypes();

    /// Analyse one raw RGB sample. `prototypes` may be supplied from the six
    /// centres once they are known.
    static RubikColorReading analyze(float r, float g, float b,
                                     const std::array<RubikLabColor, NUM_COLORS>& prototypes,
                                     bool hasCalibratedPrototypes);

    static RubikColorReading analyze(float r, float g, float b);

    /// Build prototypes from six centre readings. Returns false if the six
    /// centres are not six distinct colours.
    static bool prototypesFromCenters(const std::array<RubikColorReading, 6>& centers,
                                      std::array<RubikLabColor, NUM_COLORS>& outPrototypes);

    /// Rough hue-only classification for diagnostics.
    static uint8_t legacyHSVClassify(float h, float s, float v);
};

#endif /* RubikColorMath_h */
