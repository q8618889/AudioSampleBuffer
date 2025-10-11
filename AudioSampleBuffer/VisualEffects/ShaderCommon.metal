//
//  ShaderCommon.metal
//  AudioSampleBuffer
//
//  Metal着色器公共定义
//

#ifndef ShaderCommon_metal
#define ShaderCommon_metal

#include <metal_stdlib>
using namespace metal;

// 顶点结构体
struct Vertex {
    float2 position [[attribute(0)]];
    float4 color [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
};

// 光栅化数据
struct RasterizerData {
    float4 position [[position]];
    float4 color;
    float2 texCoord;
};

// 统一缓冲区
struct Uniforms {
    float4x4 projectionMatrix;
    float4x4 modelViewMatrix;
    float4 time;
    float4 resolution;
    float4 audioData[80];
    float4 galaxyParams1; // 星系参数1: (coreIntensity, edgeIntensity, rotationSpeed, glowRadius)
    float4 galaxyParams2; // 星系参数2: (colorShiftSpeed, nebulaIntensity, pulseStrength, audioSensitivity)
    float4 galaxyParams3; // 星系参数3: (starDensity, spiralArms, colorTheme, reserved)
    float4 cyberpunkControls; // 赛博朋克控制: (enableClimaxEffect, showDebugBars, enableGrid, backgroundMode)
    float4 cyberpunkFrequencyControls; // 赛博朋克频段控制: (enableBass, enableMid, enableTreble, reserved)
    float4 cyberpunkBackgroundParams; // 赛博朋克背景参数: (solidColorR, solidColorG, solidColorB, intensity)
};

#pragma mark - 辅助函数（使用static inline避免重复符号）

// 宽高比校正 + 缩放函数
// Metal视图是正方形(926x926)，但需要缩放特效使其适合屏幕宽度(428)
static inline float2 aspectCorrect(float2 uv, float4 resolution) {
    // resolution.x = drawableWidth (926*3 = 2778)
    // resolution.y = drawableHeight (926*3 = 2778)
    // resolution.z = aspectRatio (should be screen width/height, e.g., 428/926 ≈ 0.462)
    
    // 计算缩放因子：视图是正方形，但我们希望特效基于屏幕宽度
    // 如果 resolution.z < 1.0（竖屏），说明宽度 < 高度
    // 我们需要将特效缩小到 resolution.z 的比例
    float scaleFactor = (resolution.z < 1.0) ? resolution.z : 1.0;
    
    // 转换到中心坐标系 [-0.5, 0.5]
    float2 pos = uv - 0.5;
    
    // 应用缩放（缩小特效）
    pos /= scaleFactor;
    
    // 转回UV坐标 [0, 1]
    return pos + 0.5;
}

// 噪声函数
static inline float noise(float2 uv) {
    return fract(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
}

// 分形噪声
static inline float fractalNoise(float2 uv, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    
    for (int i = 0; i < octaves; i++) {
        value += noise(uv) * amplitude;
        uv *= 2.0;
        amplitude *= 0.5;
    }
    
    return value;
}

#endif /* ShaderCommon_metal */

