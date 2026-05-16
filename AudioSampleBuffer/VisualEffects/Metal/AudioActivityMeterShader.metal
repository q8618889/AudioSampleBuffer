#include "ShaderCommon.metal"
using namespace metal;

static inline float aamLine(float value, float edge, float softness) {
    return 1.0 - smoothstep(edge, edge + softness, value);
}

static inline float aamRect(float2 uv, float2 center, float2 halfSize, float softness) {
    float2 d = abs(uv - center) - halfSize;
    float outside = length(max(d, float2(0.0)));
    float inside = min(max(d.x, d.y), 0.0);
    return 1.0 - smoothstep(0.0, softness, outside + inside);
}

static inline float aamActivityAtIndex(int index, constant Uniforms &u) {
    if (index == 0) return u.activityMeter1.x;
    if (index == 1) return u.activityMeter1.y;
    if (index == 2) return u.activityMeter1.z;
    if (index == 3) return u.activityMeter1.w;
    if (index == 4) return u.activityMeter2.x;
    if (index == 5) return u.activityMeter2.y;
    if (index == 6) return u.activityMeter2.z;
    if (index == 7) return u.activityMeter2.w;
    if (index == 8) return u.activityMeter3.x;
    if (index == 9) return u.activityMeter3.y;
    if (index == 10) return u.activityMeter3.z;
    return u.activityMeter3.w;
}

fragment float4 audioActivityMeterFragment(RasterizerData in [[stage_in]],
                                           constant Uniforms &u [[buffer(0)]]) {
    float2 uv = in.texCoord;
    float t = u.time.x;
    float3 color = float3(0.010, 0.012, 0.018);
    float alpha = 0.82;

    float2 panelCenter = float2(0.50, 0.50);
    float2 panelHalf = float2(0.43, 0.40);
    float panel = aamRect(uv, panelCenter, panelHalf, 0.018);
    float panelBorder = aamRect(uv, panelCenter, panelHalf + 0.006, 0.010) - panel;
    color += float3(0.018, 0.030, 0.040) * panel;
    color += float3(0.18, 0.32, 0.42) * panelBorder;

    float energy = clamp(u.activityMeter3.w, 0.0, 1.0);
    float sweep = fract(t * (0.10 + energy * 0.16));
    float scan = aamLine(abs(uv.y - sweep), 0.0, 0.022) * panel * (0.18 + energy * 0.28);
    color += float3(0.10, 0.36, 0.48) * scan;

    const int rowCount = 12;
    float rowTop = 0.17;
    float rowStep = 0.058;
    float barLeft = 0.42;
    float barWidth = 0.42;
    float barHeight = 0.016;

    for (int i = 0; i < rowCount; i++) {
        float y = rowTop + float(i) * rowStep;
        float activity = clamp(aamActivityAtIndex(i, u), 0.0, 1.0);
        float rowGlow = aamLine(abs(uv.y - y), 0.0, 0.019) * panel;
        float rowTrack = aamRect(uv, float2(barLeft + barWidth * 0.5, y), float2(barWidth * 0.5, barHeight), 0.006);
        float filledWidth = barWidth * max(0.025, activity);
        float fill = aamRect(uv, float2(barLeft + filledWidth * 0.5, y), float2(filledWidth * 0.5, barHeight), 0.005);
        float tick = 0.0;
        for (int j = 0; j < 10; j++) {
            float x = barLeft + barWidth * (float(j) + 0.5) / 10.0;
            tick += aamRect(uv, float2(x, y), float2(0.0012, 0.020), 0.002);
        }

        float hue = float(i) / float(rowCount);
        float3 rowColor = mix(float3(0.20, 0.74, 1.0), float3(1.0, 0.75, 0.22), hue);
        rowColor = mix(rowColor, float3(0.72, 1.0, 0.36), smoothstep(0.58, 1.0, activity));
        color += float3(0.06, 0.09, 0.11) * rowGlow * (0.55 + activity * 0.55);
        color += float3(0.12, 0.16, 0.18) * rowTrack * 0.72;
        color += rowColor * fill * (0.62 + activity * 0.90);
        color += rowColor * rowGlow * activity * 0.14;
        color += float3(0.30, 0.38, 0.42) * tick * 0.20;
    }

    float vignette = smoothstep(0.86, 0.22, length(uv - 0.5));
    color *= 0.72 + vignette * 0.58;
    return float4(color, alpha * panel);
}
