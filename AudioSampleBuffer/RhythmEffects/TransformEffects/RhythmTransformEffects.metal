#include <metal_stdlib>
using namespace metal;

struct RhythmTransformVertex {
    float2 position;
    float2 uv;
};

struct RhythmTransformVarying {
    float4 position [[position]];
    float2 uv;
};

struct RhythmTransformUniforms {
    float2 resolution;
    float2 videoSize;
    float time;
    float baseIntensity;
    float beatPulse;
    float beatTime;
    float strongMix;
    float radius;
    float speed;
    int effectType;
    float beatSyncMix;
};

vertex RhythmTransformVarying rhythmTransformVertex(uint vid [[vertex_id]],
                                                    constant RhythmTransformVertex *vertices [[buffer(0)]]) {
    RhythmTransformVarying out;
    out.position = float4(vertices[vid].position, 0.0, 1.0);
    out.uv = vertices[vid].uv;
    return out;
}

static float2 aspectFillUV(float2 uv, float2 videoSize, float2 outputSize) {
    float videoAspect = videoSize.x / max(videoSize.y, 1.0);
    float outputAspect = outputSize.x / max(outputSize.y, 1.0);
    float2 scale = float2(1.0, 1.0);
    if (videoAspect > outputAspect) {
        scale.x = outputAspect / videoAspect;
    } else {
        scale.y = videoAspect / outputAspect;
    }
    return (uv - 0.5) * scale + 0.5;
}

static float ringMask(float dist, float center, float width) {
    return smoothstep(center + width, center, dist) * smoothstep(center - width, center, dist);
}

fragment float4 rhythmTransformFragment(RhythmTransformVarying in [[stage_in]],
                                        texture2d<float> videoTexture [[texture(0)]],
                                        constant RhythmTransformUniforms &u [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 centered = in.uv * 2.0 - 1.0;
    float2 circular = float2(centered.x * aspect, centered.y);
    float dist = length(circular);
    float angle = atan2(circular.y, circular.x);

    float beatFlash = exp(-u.beatTime * (3.0 + u.strongMix * 1.6));
    float beatAttack = 1.0 - smoothstep(0.0, 0.12, u.beatTime);
    float beatDrive = max(beatFlash, beatAttack) * clamp(u.beatPulse, 0.0, 1.8);
    float intensity = clamp(u.baseIntensity * 0.75 + beatDrive * 0.55, 0.0, 1.8);
    float2 warped = circular;
    float3 glow = float3(0.0);

    if (u.effectType == 6) {
        float sustainedDrive = max(beatDrive, clamp(u.beatSyncMix, 0.0, 1.0) * clamp(u.beatPulse, 0.0, 1.2));
        float ripple = sin((dist * 28.0) - u.time * (4.0 + u.speed * 10.0)) * 0.5 + 0.5;
        float dropletMask = smoothstep(u.radius + 0.28, u.radius - 0.05, dist);
        float lens = pow(max(0.0, 1.0 - dist / max(u.radius, 0.08)), 2.2);
        float wake = smoothstep(u.radius + 0.18, 0.02, dist) * sustainedDrive;
        warped += normalize(circular + 1e-4) * (ripple * 0.020 + lens * 0.045 + wake * 0.060) * intensity * dropletMask;
        glow += float3(0.45, 0.85, 1.0) * dropletMask * lens * (0.12 + sustainedDrive * 0.22);
    } else if (u.effectType == 7) {
        float portalMask = smoothstep(u.radius + 0.42, u.radius - 0.08, dist);
        float swirl = (0.22 + beatDrive * 0.32) * portalMask * (1.0 - dist);
        float cs = cos(swirl + angle * 0.0);
        float sn = sin(swirl + angle * 0.0);
        warped = float2(circular.x * cs - circular.y * sn, circular.x * sn + circular.y * cs);
        warped *= 1.0 - portalMask * (0.10 + beatDrive * 0.20);
        float rim = ringMask(dist, u.radius * (0.55 + beatDrive * 0.18), 0.045 + beatDrive * 0.018);
        glow += mix(float3(0.22, 0.75, 1.0), float3(0.95, 0.45, 1.0), 0.5 + 0.5 * sin(u.time * 4.0)) * rim * (0.28 + beatDrive * 0.40);
    } else if (u.effectType == 8) {
        float waveCenter = 0.12 + beatDrive * (0.18 + u.radius * 0.26);
        float wave = ringMask(dist, waveCenter, 0.05 + beatDrive * 0.03);
        warped += normalize(circular + 1e-4) * wave * intensity * 0.085;
        warped *= 1.0 + smoothstep(0.42, 0.0, dist) * beatDrive * 0.04;
        glow += float3(1.0, 0.92, 0.72) * wave * (0.24 + beatDrive * 0.34);
    }

    float2 unwarped = float2(warped.x / max(aspect, 0.0001), warped.y);
    float2 videoUV = aspectFillUV(unwarped * 0.5 + 0.5, u.videoSize, u.resolution);
    float3 color = videoTexture.sample(s, videoUV).rgb;

    if (u.effectType == 7 || u.effectType == 8) {
        float2 fringe = normalize(circular + 1e-4) * 0.004 * beatDrive;
        float2 plusUV = float2((warped + fringe).x / max(aspect, 0.0001), (warped + fringe).y);
        float2 minusUV = float2((warped - fringe).x / max(aspect, 0.0001), (warped - fringe).y);
        float r = videoTexture.sample(s, aspectFillUV(plusUV * 0.5 + 0.5, u.videoSize, u.resolution)).r;
        float b = videoTexture.sample(s, aspectFillUV(minusUV * 0.5 + 0.5, u.videoSize, u.resolution)).b;
        color = float3(r, color.g, b);
    }

    color += glow;
    float3 effected = saturate(color);
    float syncMix = clamp(u.beatSyncMix, 0.0, 1.0);
    if (syncMix < 0.999) {
        float2 plainUV = aspectFillUV(in.uv, u.videoSize, u.resolution);
        float3 plainColor = videoTexture.sample(s, plainUV).rgb;
        effected = mix(plainColor, effected, syncMix);
    }
    return float4(effected, 1.0);
}
