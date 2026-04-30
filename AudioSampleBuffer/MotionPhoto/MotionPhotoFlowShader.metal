#include <metal_stdlib>
using namespace metal;

struct RasterizerData {
    float4 position [[position]];
    float2 uv;
};

struct MotionPhotoUniforms {
    float2 phase;
    float2 amplitude;
};

vertex RasterizerData motionPhotoVertexShader(uint vertexID [[vertex_id]]) {
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    float2 uvs[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    RasterizerData out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID];
    return out;
}

fragment float4 motionPhotoFragmentShader(RasterizerData in [[stage_in]],
                                          texture2d<float> sourceTexture [[texture(0)]],
                                          texture2d<float> flowTexture [[texture(1)]],
                                          texture2d<float> maskTexture [[texture(2)]],
                                          sampler textureSampler [[sampler(0)]],
                                          constant MotionPhotoUniforms &uniforms [[buffer(0)]]) {
    float2 uv = in.uv;
    float4 baseColor = sourceTexture.sample(textureSampler, uv);
    if (!flowTexture.get_width() || !maskTexture.get_width()) {
        return baseColor;
    }

    float4 flowSample = flowTexture.sample(textureSampler, uv);
    float maskAlpha = maskTexture.sample(textureSampler, uv).r;
    float progress = fract(uniforms.phase.x);
    float2 flowVector = flowSample.xy * 1.75;
    float2 warpedUV0 = clamp(uv - flowVector * progress, float2(0.0), float2(1.0));
    float2 warpedUV1 = clamp(uv - flowVector * (progress - 1.0), float2(0.0), float2(1.0));
    float4 warpedColor0 = sourceTexture.sample(textureSampler, warpedUV0);
    float4 warpedColor1 = sourceTexture.sample(textureSampler, warpedUV1);
    float wrapBlend = smoothstep(0.82, 1.0, progress);
    float4 warpedColor = mix(warpedColor0, warpedColor1, wrapBlend);
    float blendAlpha = clamp(max(maskAlpha, flowSample.z), 0.0, 1.0);
    return mix(baseColor, warpedColor, blendAlpha);
}
