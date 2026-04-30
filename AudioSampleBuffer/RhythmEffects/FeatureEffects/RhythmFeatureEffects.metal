#include <metal_stdlib>
using namespace metal;

struct RhythmFeatureVertex {
    float2 position;
    float2 uv;
};

struct RhythmFeatureVarying {
    float4 position [[position]];
    float2 uv;
};

struct RhythmFeatureUniforms {
    float2 resolution;
    float time;
    float intensity;
    float strongMix;
    float beatTime;
    float seed;
    int effectType;
    float beatSyncMix;
    float subBass;
    float transient;
    float harmonic;
    float noise;
};

static float rfHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

static float rfNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = rfHash(i);
    float b = rfHash(i + float2(1.0, 0.0));
    float c = rfHash(i + float2(0.0, 1.0));
    float d = rfHash(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

vertex RhythmFeatureVarying rhythmFeatureVertex(uint vid [[vertex_id]],
                                                constant RhythmFeatureVertex *vertices [[buffer(0)]]) {
    RhythmFeatureVarying out;
    out.position = float4(vertices[vid].position, 0.0, 1.0);
    out.uv = vertices[vid].uv;
    return out;
}

fragment float4 rhythmFeatureFragment(RhythmFeatureVarying in [[stage_in]],
                                      constant RhythmFeatureUniforms &u [[buffer(0)]]) {
    float beatIntensity = clamp(u.intensity + 0.18 * u.subBass + 0.12 * u.transient, 0.0, 2.2);
    float previewIntensity = 0.12;
    float intensity = max(beatIntensity, previewIntensity);
    if (intensity < 0.002) {
        return float4(0.0);
    }

    float2 uv = in.uv;
    float2 centered = uv * 2.0 - 1.0;
    float t = u.time;
    float beatFlash = exp(-u.beatTime * (4.6 + u.strongMix * 1.8));
    float beatAttack = 1.0 - smoothstep(0.0, 0.11, u.beatTime);
    float beatSnap = pow(max(beatFlash, beatAttack), 0.72);
    float beatGate = smoothstep(0.01, 0.11, beatIntensity);
    float beatDrive = beatSnap * beatGate;
    float restDrive = 1.0 - beatGate;
    float alpha = 0.0;
    float3 color = float3(0.0);
    float idle = 0.07 + 0.04 * sin(t * 1.6 + u.seed * 7.0);

    if (u.effectType == 0) {
        float2 shiftedUv = uv;
        float bandNoise = rfNoise(float2(floor(uv.y * 24.0 + t * 3.2), floor(u.seed * 17.0)));
        shiftedUv.x += (bandNoise - 0.5) * (0.035 + beatDrive * 0.34);
        float scan = 0.5 + 0.5 * sin((shiftedUv.y * u.resolution.y * 0.26) + t * (42.0 + beatDrive * 54.0));
        float blocks = step(0.60 - beatDrive * 0.10, rfNoise(float2(floor(shiftedUv.y * 18.0 + t * (7.0 + beatDrive * 8.0)), floor(shiftedUv.x * 8.0 + u.seed * 9.0))));
        float centerBand = smoothstep(0.72, 0.06, abs(centered.y - sin(t * 12.0 + u.seed * 9.0) * 0.42));
        float verticalBurst = smoothstep(1.0, 0.12, abs(centered.x)) * (0.22 + beatDrive * 0.78);
        float edgeTear = smoothstep(0.42, 0.98, abs(centered.x)) * (0.12 + 0.88 * beatDrive);
        float rgbMix = 0.5 + 0.5 * sin((shiftedUv.x * 9.0 - shiftedUv.y * 15.0) + t * (4.0 + beatDrive * 8.0) + u.seed * 13.0);
        float3 hot = float3(1.0, 0.14, 0.36);
        float3 cool = float3(0.05, 0.88, 1.0);
        color = mix(cool, hot, rgbMix);
        color += float3(1.0, 1.0, 1.0) * blocks * (0.08 + beatDrive * 0.24);
        color += float3(0.95, 0.98, 1.0) * edgeTear * (0.07 + beatDrive * 0.20);
        alpha = (centerBand * (0.18 + beatDrive * 0.36) +
                 blocks * (0.08 + beatDrive * 0.22) +
                 scan * (0.08 + beatDrive * 0.18) +
                 verticalBurst * (0.06 + beatDrive * 0.18) +
                 edgeTear * (0.05 + beatDrive * 0.16) +
                 idle * (0.70 + restDrive * 0.30)) * intensity;
    } else if (u.effectType == 1) {
        float sweep = fract(t * (0.18 + u.strongMix * 0.10) + u.seed * 0.31);
        float trailLine = smoothstep(0.20, 0.0, abs(uv.x - sweep));
        float scanTrail = smoothstep(0.32, 0.0, abs(uv.x - (sweep - 0.10 - beatDrive * 0.12)));
        float horizontalGlow = smoothstep(0.78, 0.10, abs(centered.y));
        float ripples = 0.5 + 0.5 * sin((uv.y * 18.0 - t * (8.0 + beatDrive * 11.0)) + u.seed * 9.0);
        color = mix(float3(0.12, 0.95, 1.0), float3(0.72, 0.24, 1.0), 0.35 + 0.35 * ripples);
        color += float3(1.0, 0.98, 0.92) * trailLine * (0.10 + beatDrive * 0.34);
        alpha = (trailLine * (0.16 + beatDrive * 0.30) +
                 scanTrail * (0.09 + beatDrive * 0.22) +
                 horizontalGlow * ripples * (0.06 + beatDrive * 0.15) +
                 idle * (0.60 + restDrive * 0.40)) * intensity;
    } else if (u.effectType == 2) {
        float r = length(centered);
        float wave = smoothstep(0.05, 0.0, abs(r - (0.12 + beatDrive * 0.30)));
        float outerWave = smoothstep(0.06, 0.0, abs(r - (0.26 + beatDrive * 0.42)));
        float centerBlast = smoothstep(0.42, 0.0, r) * beatDrive;
        float shards = pow(max(0.0, cos(atan2(centered.y, centered.x) * 10.0 + t * 2.0)), 8.0);
        color = mix(float3(1.0, 0.48, 0.16), float3(1.0, 0.92, 0.58), 0.45 + 0.35 * u.strongMix);
        color += float3(1.0, 0.85, 0.76) * shards * (0.04 + beatDrive * 0.18);
        alpha = (wave * (0.18 + beatDrive * 0.32) +
                 outerWave * (0.10 + beatDrive * 0.22) +
                 centerBlast * (0.08 + beatDrive * 0.18) +
                 shards * centerBlast * 0.22 +
                 idle * (0.46 + restDrive * 0.26)) * intensity;
    } else if (u.effectType == 3) {
        float r = length(centered);
        float angle = atan2(centered.y, centered.x);
        float zoomCore = smoothstep(1.16, 0.03, r);
        float ring = smoothstep(0.48, 0.09, abs(r - (0.18 + beatDrive * 0.22)));
        float streak = pow(max(0.0, cos(angle * 8.0 + t * (4.0 + beatDrive * 12.0))), 7.0);
        float spokes = pow(max(0.0, cos(angle * 14.0 - t * (2.0 + beatDrive * 9.5))), 10.0);
        float pulse = beatDrive * smoothstep(1.18, 0.08, r);
        float tunnel = smoothstep(0.95, 0.18, r) * (0.18 + beatDrive * 0.82) * (0.5 + 0.5 * sin(t * (4.0 + beatDrive * 10.0) - r * 18.0));
        color = mix(float3(0.12, 0.74, 1.0), float3(1.0, 0.42, 0.12), 0.35 + u.strongMix * 0.65);
        color += float3(1.0, 0.95, 0.85) * spokes * (0.10 + beatDrive * 0.34);
        color += float3(0.85, 0.92, 1.0) * tunnel * (0.08 + beatDrive * 0.20);
        alpha = (zoomCore * (0.16 + beatDrive * 0.26) +
                 streak * (0.08 + beatDrive * 0.20) +
                 ring * (0.08 + beatDrive * 0.30) +
                 pulse * (0.08 + beatDrive * 0.34) +
                 tunnel * (0.07 + beatDrive * 0.18) +
                 idle * (0.68 + restDrive * 0.32)) * intensity;
    } else if (u.effectType == 4) {
        float angle = atan2(centered.y, centered.x);
        float r = length(centered);
        float petals = pow(max(0.0, cos(angle * 6.0 + t * (1.6 + beatDrive * 2.0))), 4.0);
        float mirrored = pow(max(0.0, cos(angle * 12.0 - t * (1.0 + beatDrive * 3.0))), 6.0);
        float ring = smoothstep(0.52, 0.08, abs(r - (0.20 + beatDrive * 0.16)));
        float core = smoothstep(0.46, 0.0, r);
        float palette = 0.5 + 0.5 * sin(t * 1.8 + r * 14.0 + u.seed * 5.0);
        color = mix(float3(0.14, 0.88, 1.0), float3(1.0, 0.30, 0.78), palette);
        color += float3(0.96, 0.96, 1.0) * mirrored * (0.06 + beatDrive * 0.18);
        alpha = (petals * core * (0.12 + beatDrive * 0.24) +
                 mirrored * ring * (0.10 + beatDrive * 0.20) +
                 ring * (0.08 + beatDrive * 0.20) +
                 idle * (0.56 + restDrive * 0.28)) * intensity;
    } else if (u.effectType == 5) {
        float r = length(centered);
        float pull = smoothstep(1.10, 0.04, r);
        float streaks = pow(max(0.0, cos(atan2(centered.y, centered.x) * 14.0 - t * (4.0 + beatDrive * 8.0))), 9.0);
        float tunnel = smoothstep(0.92, 0.10, r) * (0.5 + 0.5 * sin(r * 20.0 - t * (7.0 + beatDrive * 8.0)));
        float vacuum = pow(max(0.0, 1.0 - r), 2.0) * beatDrive;
        color = mix(float3(0.10, 0.78, 1.0), float3(0.62, 0.22, 1.0), 0.55);
        color += float3(1.0, 0.90, 0.96) * streaks * (0.06 + beatDrive * 0.22);
        alpha = (pull * (0.10 + beatDrive * 0.18) +
                 streaks * (0.08 + beatDrive * 0.22) +
                 tunnel * (0.07 + beatDrive * 0.18) +
                 vacuum * 0.24 +
                 idle * (0.54 + restDrive * 0.30)) * intensity;
    } else {
        float n = rfNoise(uv * (8.0 + u.strongMix * 10.0) + float2(t * 0.8, u.seed));
        color = mix(float3(0.18, 0.75, 1.0), float3(1.0, 0.30, 0.55), n);
        alpha = n * 0.32 * intensity;
    }

    alpha = clamp(alpha, 0.0, 0.98);
    alpha *= clamp(u.beatSyncMix, 0.0, 1.0);
    return float4(color, alpha);
}
