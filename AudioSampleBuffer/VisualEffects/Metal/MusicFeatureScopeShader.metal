#include "ShaderCommon.metal"
using namespace metal;

static inline float mfsRect(float2 uv, float2 center, float2 halfSize, float softness) {
    float2 d = abs(uv - center) - halfSize;
    float outside = length(max(d, float2(0.0)));
    float inside = min(max(d.x, d.y), 0.0);
    return 1.0 - smoothstep(0.0, softness, outside + inside);
}

static inline float mfsRing(float2 uv, float2 center, float radius, float width) {
    return 1.0 - smoothstep(0.0, width, abs(length(uv - center) - radius));
}

static inline float mfsLine(float2 p, float2 a, float2 b, float width) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
    return 1.0 - smoothstep(0.0, width, length(pa - ba * h));
}

static inline float mfsHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static inline float mfsFeatureAtIndex(int index, constant Uniforms &u) {
    float low = clamp(u.activityMeter1.x, 0.0, 1.0);
    float transient = clamp(u.activityMeter1.y, 0.0, 1.0);
    float harmonic = clamp(u.activityMeter1.z, 0.0, 1.0);
    float noise = clamp(u.activityMeter1.w, 0.0, 1.0);
    float high = clamp(u.activityMeter2.x, 0.0, 1.0);
    float electric = clamp(u.activityMeter2.y, 0.0, 1.0);
    float chopped = clamp(u.activityMeter2.z, 0.0, 1.0);
    float sweep = clamp(u.activityMeter2.w, 0.0, 1.0);
    float echo = clamp(u.activityMeter3.y, 0.0, 1.0);
    float sidechain = clamp(u.activityMeter3.z, 0.0, 1.0);
    float energy = clamp(u.activityMeter3.w, 0.0, 1.0);
    float beat = max(low, transient * 0.68);
    float kick = max(low, u.categoryFeatures.x);
    float drop = clamp(energy * 0.55 + low * 0.32 + sweep * 0.28 + noise * 0.18, 0.0, 1.0);

    if (index == 0) return beat;
    if (index == 1) return kick;
    if (index == 2) return low;
    if (index == 3) return harmonic * 0.58 + low * 0.36;
    if (index == 4) return transient * 0.78 + high * 0.18;
    if (index == 5) return high * 0.72 + transient * 0.25;
    if (index == 6) return harmonic * 0.74 + high * 0.20;
    if (index == 7) return harmonic * 0.62 + echo * 0.22;
    if (index == 8) return transient * 0.58 + harmonic * 0.25;
    if (index == 9) return sweep;
    if (index == 10) return drop;
    if (index == 11) return transient;
    if (index == 12) return harmonic;
    if (index == 13) return max(transient, chopped * 0.75);
    if (index == 14) return max(noise, electric * 0.42);
    return sidechain;
}

static inline float3 mfsPalette(int index, float activity) {
    float3 a = float3(0.12, 0.72, 1.00);
    float3 b = float3(1.00, 0.38, 0.18);
    float3 c = float3(0.70, 1.00, 0.32);
    float hue = float(index) / 20.0;
    float3 color = mix(a, b, smoothstep(0.08, 0.74, hue));
    color = mix(color, c, smoothstep(0.48, 1.0, activity) * 0.42);
    return color;
}

fragment float4 musicFeatureScopeFragment(RasterizerData in [[stage_in]],
                                          constant Uniforms &u [[buffer(0)]]) {
    float2 uv = in.texCoord;
    float2 p = uv - 0.5;
    float t = u.time.x;
    float energy = clamp(u.activityMeter3.w, 0.0, 1.0);
    float beat = mfsFeatureAtIndex(0, u);
    float kick = mfsFeatureAtIndex(1, u);
    float sidechain = mfsFeatureAtIndex(15, u);
    float drop = mfsFeatureAtIndex(10, u);

    float3 color = float3(0.006, 0.010, 0.016);
    float vignette = smoothstep(0.74, 0.10, length(p));
    color += float3(0.010, 0.018, 0.030) * (0.65 + energy * 0.55) * vignette;

    float centerPulse = mfsRing(uv, float2(0.50), 0.075 + beat * 0.050 + 0.010 * sin(t * 2.0), 0.016);
    float kickRing = mfsRing(uv, float2(0.50), 0.16 + kick * 0.18 + fract(t * 0.36 + kick) * 0.035, 0.018);
    float sideBreath = mfsRing(uv, float2(0.50), 0.27 + sidechain * 0.080, 0.020 + sidechain * 0.018);
    color += float3(0.20, 0.65, 1.00) * centerPulse * (0.35 + beat);
    color += float3(1.00, 0.42, 0.20) * kickRing * kick;
    color += float3(0.55, 0.95, 0.75) * sideBreath * sidechain * 0.72;

    float lowPressure = smoothstep(0.48, 0.16, abs(uv.y - (0.78 + sin(t * 1.7) * 0.012)));
    lowPressure *= smoothstep(0.98, 0.40, abs(uv.x - 0.5));
    color += float3(0.08, 0.20, 0.36) * lowPressure * clamp(u.activityMeter1.x, 0.0, 1.0) * 0.55;

    float riser = clamp(u.activityMeter2.w, 0.0, 1.0);
    float sweepY = 0.84 - fract(t * (0.10 + riser * 0.42)) * 0.68;
    float sweepLine = 1.0 - smoothstep(0.0, 0.026 + riser * 0.018, abs(uv.y - sweepY));
    color += float3(0.40, 0.85, 1.00) * sweepLine * riser * smoothstep(0.18, 0.92, uv.x);

    const int featureCount = 16;
    float2 center = float2(0.50, 0.50);
    for (int i = 0; i < featureCount; i++) {
        float activity = clamp(mfsFeatureAtIndex(i, u), 0.0, 1.0);
        float side = i < 8 ? 0.0 : 1.0;
        float row = float(i % 8);
        float y = 0.18 + row * 0.090;
        float x = mix(0.18, 0.82, side);
        float2 slot = float2(x, y);
        float3 slotColor = mfsPalette(i, activity);
        float box = mfsRect(uv, slot, float2(0.115, 0.026), 0.010);
        float fill = mfsRect(uv, float2(x - 0.040 + activity * 0.040, y), float2(0.008 + activity * 0.076, 0.009), 0.006);
        float link = mfsLine(uv, center, slot, 0.003 + activity * 0.004);
        float blip = mfsRing(uv, slot, 0.025 + activity * 0.028 + 0.006 * sin(t * 4.0 + float(i)), 0.009);
        color += float3(0.030, 0.044, 0.056) * box * (0.50 + activity * 0.8);
        color += slotColor * fill * (0.70 + activity);
        color += slotColor * link * activity * 0.35;
        color += slotColor * blip * activity * 0.55;
    }

    float chopped = clamp(u.activityMeter2.z, 0.0, 1.0);
    float high = clamp(u.activityMeter2.x, 0.0, 1.0);
    for (int i = 0; i < 24; i++) {
        float fi = float(i);
        float2 spark = float2(mfsHash(float2(fi, 1.0)), mfsHash(float2(fi, 7.0)));
        spark.x = 0.18 + spark.x * 0.64;
        spark.y = 0.12 + spark.y * 0.76;
        float phase = step(0.62, mfsHash(float2(fi, floor(t * (5.0 + high * 15.0)))));
        float dotMask = 1.0 - smoothstep(0.0, 0.012 + chopped * 0.010, length(uv - spark));
        color += float3(0.75, 0.95, 1.00) * dotMask * phase * (high * 0.45 + chopped * 0.60);
    }

    float dropFlash = smoothstep(0.48, 1.0, drop);
    color += float3(1.0, 0.86, 0.48) * dropFlash * mfsRing(uv, float2(0.50), 0.38 + drop * 0.12, 0.050);
    color += float3(0.34, 0.56, 0.70) * vignette * dropFlash * 0.22;
    color *= 0.80 + vignette * 0.55;
    return float4(color, 0.92);
}
