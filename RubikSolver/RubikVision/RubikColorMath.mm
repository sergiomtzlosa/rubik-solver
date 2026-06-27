//
//  RubikColorMath.mm
//  RubikSolver - Lighting-Robust Sticker Colour Analysis
//

#import "RubikColorMath.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace {

float srgbToLinear(float c) {
    c = std::max(0.0f, std::min(1.0f, c));
    return c <= 0.04045f ? c / 12.92f : std::pow((c + 0.055f) / 1.055f, 2.4f);
}

float labForward(float t) {
    const float epsilon = 216.0f / 24389.0f;   // 0.008856...
    const float kappa = 24389.0f / 27.0f;      // 903.3...
    return t > epsilon ? std::cbrt(t) : (kappa * t + 16.0f) / 116.0f;
}

void rgbToHSV(float r, float g, float b, float& h, float& s, float& v) {
    const float maxVal = std::max({r, g, b});
    const float minVal = std::min({r, g, b});
    const float delta = maxVal - minVal;

    v = maxVal;
    if (maxVal <= 0.0001f) {
        h = 0.0f;
        s = 0.0f;
        return;
    }
    s = delta / maxVal;
    if (delta <= 0.0001f) {
        h = 0.0f;
        return;
    }
    if (r >= maxVal) {
        h = 60.0f * std::fmod((g - b) / delta, 6.0f);
    } else if (g >= maxVal) {
        h = 60.0f * (((b - r) / delta) + 2.0f);
    } else {
        h = 60.0f * (((r - g) / delta) + 4.0f);
    }
    if (h < 0.0f) h += 360.0f;
}

uint8_t nearestColorIndex(const RubikLabColor& lab,
                          const std::array<RubikLabColor, NUM_COLORS>& prototypes,
                          float& bestDistance,
                          float& secondDistance) {
    uint8_t best = 255;
    bestDistance = std::numeric_limits<float>::max();
    secondDistance = std::numeric_limits<float>::max();

    for (int i = 0; i < NUM_COLORS; ++i) {
        const float d = RubikColorMath::deltaE(lab, prototypes[i]);
        if (d < bestDistance) {
            secondDistance = bestDistance;
            bestDistance = d;
            best = static_cast<uint8_t>(i);
        } else if (d < secondDistance) {
            secondDistance = d;
        }
    }
    return best;
}

} // namespace

RubikLabColor RubikColorMath::labFromRGB(float r, float g, float b) {
    const float lr = srgbToLinear(r);
    const float lg = srgbToLinear(g);
    const float lb = srgbToLinear(b);

    const float x = 0.4124564f * lr + 0.3575761f * lg + 0.1804375f * lb;
    const float y = 0.2126729f * lr + 0.7151522f * lg + 0.0721750f * lb;
    const float z = 0.0193339f * lr + 0.1191920f * lg + 0.9503041f * lb;

    const float fx = labForward(x / 0.95047f);
    const float fy = labForward(y / 1.00000f);
    const float fz = labForward(z / 1.08883f);

    RubikLabColor lab;
    lab.L = 116.0f * fy - 16.0f;
    lab.a = 500.0f * (fx - fy);
    lab.b = 200.0f * (fy - fz);
    return lab;
}

float RubikColorMath::deltaE(const RubikLabColor& lhs, const RubikLabColor& rhs) {
    const float dL = lhs.L - rhs.L;
    const float da = lhs.a - rhs.a;
    const float db = lhs.b - rhs.b;
    return std::sqrt(dL * dL + da * da + db * db);
}

float RubikColorMath::chroma(const RubikLabColor& lab) {
    return std::sqrt(lab.a * lab.a + lab.b * lab.b);
}

const std::array<RubikLabColor, NUM_COLORS>& RubikColorMath::defaultPrototypes() {
    // Typical plastic-sticker sRGB values, converted at first use.
    static const std::array<RubikLabColor, NUM_COLORS> prototypes = [] {
        std::array<RubikLabColor, NUM_COLORS> p;
        p[COLOR_WHITE]  = RubikColorMath::labFromRGB(0.94f, 0.94f, 0.93f);
        p[COLOR_RED]    = RubikColorMath::labFromRGB(0.78f, 0.12f, 0.16f);
        p[COLOR_GREEN]  = RubikColorMath::labFromRGB(0.04f, 0.62f, 0.28f);
        p[COLOR_YELLOW] = RubikColorMath::labFromRGB(0.96f, 0.82f, 0.09f);
        p[COLOR_ORANGE] = RubikColorMath::labFromRGB(0.94f, 0.43f, 0.06f);
        p[COLOR_BLUE]   = RubikColorMath::labFromRGB(0.05f, 0.32f, 0.72f);
        return p;
    }();
    return prototypes;
}

RubikColorReading RubikColorMath::analyze(float r, float g, float b) {
    return analyze(r, g, b, defaultPrototypes(), false);
}

RubikColorReading RubikColorMath::analyze(float r, float g, float b,
                                          const std::array<RubikLabColor, NUM_COLORS>& prototypes,
                                          bool hasCalibratedPrototypes) {
    RubikColorReading reading;
    reading.r = r;
    reading.g = g;
    reading.b = b;

    rgbToHSV(r, g, b, reading.h, reading.s, reading.v);
    reading.lab = labFromRGB(r, g, b);

    const float luminance = reading.lab.L;
    const float chroma = RubikColorMath::chroma(reading.lab);

    // Reject camera noise, shadows and the dark background between stickers.
    if (luminance < 9.0f || (luminance < 20.0f && chroma < 7.0f)) {
        reading.background = true;
        reading.reliable = false;
        reading.confidence = 0.0f;
        reading.colorIndex = 255;
        return reading;
    }

    float bestDistance = 0.0f;
    float secondDistance = 0.0f;
    const uint8_t best = nearestColorIndex(reading.lab, prototypes, bestDistance, secondDistance);
    reading.deltaE = bestDistance;

    const float margin = std::max(0.0f, secondDistance - bestDistance);
    const float marginScore = std::min(1.0f, margin / 22.0f);
    const float closeness = std::min(1.0f, std::max(0.0f, 1.0f - bestDistance / 55.0f));
    reading.confidence = std::min(1.0f, 0.7f * marginScore + 0.3f * closeness);

    // Grey/very low-chroma stickers can only sensibly be white; a low-chroma
    // sample that matched a saturated prototype is a lighting artefact.
    if (chroma < 6.0f && best != COLOR_WHITE) {
        reading.colorIndex = 255;
        reading.reliable = false;
        reading.background = true;
        return reading;
    }

    reading.colorIndex = best;
    const float acceptance = hasCalibratedPrototypes ? 0.18f : 0.24f;
    reading.reliable = (bestDistance < 42.0f) && (reading.confidence >= acceptance);
    return reading;
}

bool RubikColorMath::prototypesFromCenters(
    const std::array<RubikColorReading, 6>& centers,
    std::array<RubikLabColor, NUM_COLORS>& outPrototypes) {
    std::array<bool, NUM_COLORS> used{};
    std::array<RubikLabColor, NUM_COLORS> prototypes{};
    int assigned = 0;

    for (const RubikColorReading& center : centers) {
        if (center.colorIndex >= NUM_COLORS) continue;
        const uint8_t index = center.colorIndex;
        if (used[index]) return false;
        used[index] = true;
        prototypes[index] = center.lab;
        ++assigned;
    }

    if (assigned != NUM_COLORS) return false;
    outPrototypes = prototypes;
    return true;
}

uint8_t RubikColorMath::legacyHSVClassify(float h, float s, float v) {
    if (s < 0.22f && v > 0.32f) return COLOR_WHITE;
    if (h >= 40.0f && h < 72.0f) return COLOR_YELLOW;
    if (h >= 72.0f && h < 165.0f) return COLOR_GREEN;
    if (h >= 165.0f && h < 265.0f) return COLOR_BLUE;
    if (h >= 12.0f && h < 40.0f) return COLOR_ORANGE;
    return COLOR_RED;
}

#pragma mark - White balance

RubikWhiteBalance RubikWhiteBalance::grayWorld(const std::vector<std::array<float, 3>>& samples) {
    RubikWhiteBalance balance;
    if (samples.empty()) return balance;

    double sumR = 0.0;
    double sumG = 0.0;
    double sumB = 0.0;
    for (const auto& sample : samples) {
        sumR += sample[0];
        sumG += sample[1];
        sumB += sample[2];
    }
    const double count = static_cast<double>(samples.size());
    const float meanR = static_cast<float>(sumR / count);
    const float meanG = static_cast<float>(sumG / count);
    const float meanB = static_cast<float>(sumB / count);
    const float grey = (meanR + meanG + meanB) / 3.0f;
    if (meanR < 0.005f || meanG < 0.005f || meanB < 0.005f || grey < 0.01f) {
        return balance;
    }

    balance.scaleR = std::max(0.25f, std::min(4.0f, grey / meanR));
    balance.scaleG = std::max(0.25f, std::min(4.0f, grey / meanG));
    balance.scaleB = std::max(0.25f, std::min(4.0f, grey / meanB));
    balance.valid = true;
    return balance;
}

RubikWhiteBalance RubikWhiteBalance::fromWhiteReference(float r, float g, float b) {
    RubikWhiteBalance balance;
    if (r < 0.02f || g < 0.02f || b < 0.02f) return balance;

    // Preserve overall exposure; only equalise the channels.
    const float mean = (r + g + b) / 3.0f;
    balance.scaleR = std::max(0.25f, std::min(4.0f, mean / r));
    balance.scaleG = std::max(0.25f, std::min(4.0f, mean / g));
    balance.scaleB = std::max(0.25f, std::min(4.0f, mean / b));
    balance.valid = true;
    return balance;
}

RubikWhiteBalance RubikWhiteBalance::combinedWith(const RubikWhiteBalance& other) const {
    RubikWhiteBalance out;
    out.scaleR = scaleR * other.scaleR;
    out.scaleG = scaleG * other.scaleG;
    out.scaleB = scaleB * other.scaleB;
    out.valid = valid || other.valid;
    return out;
}
