//
//  Shaders.metal
//  AudioSampleBuffer
//
//  Metal着色器集合
//

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
    float4 cyberpunkControls; // 赛博朋克控制: (enableClimaxEffect, showDebugBars, reserved1, reserved2)
    float4 cyberpunkFrequencyControls; // 赛博朋克频段控制: (enableBass, enableMid, enableTreble, reserved)
};

#pragma mark - 辅助函数

// 宽高比校正 + 缩放函数
// Metal视图是正方形(926x926)，但需要缩放特效使其适合屏幕宽度(428)
float2 aspectCorrect(float2 uv, float4 resolution) {
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
float noise(float2 uv) {
    return fract(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
}

// 分形噪声
float fractalNoise(float2 uv, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    
    for (int i = 0; i < octaves; i++) {
        value += noise(uv) * amplitude;
        uv *= 2.0;
        amplitude *= 0.5;
    }
    
    return value;
}

#pragma mark - 霓虹发光效果

vertex RasterizerData neon_vertex(uint vertexID [[vertex_id]],
                                  constant Uniforms& uniforms [[buffer(0)]]) {
    RasterizerData out;
    
    // 创建全屏四边形
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    
    float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    out.color = float4(1.0);
    
    return out;
}

fragment float4 neon_fragment(RasterizerData in [[stage_in]],
                              constant Uniforms& uniforms [[buffer(0)]]) {
    // 宽高比校正 - 保证圆形不变形
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float2 center = float2(0.5, 0.5);
    float time = uniforms.time.x;
    
    // 创建高精度环形频谱
    float angle = atan2(uv.y - center.y, uv.x - center.x);
    float radius = length(uv - center);
    
    // 将角度转换为频谱索引
    float normalizedAngle = (angle + M_PI_F) / (2.0 * M_PI_F);
    int spectrumIndex = int(normalizedAngle * 79.0);
    float audioValue = uniforms.audioData[spectrumIndex].x;
    
    // 高清晰度霓虹发光效果
    float baseRadius = 0.35;
    float glowRadius = baseRadius + audioValue * 0.15;
    
    // 多层发光效果
    float innerGlow = exp(-abs(radius - glowRadius) * 50.0) * 0.8;
    float middleGlow = exp(-abs(radius - glowRadius) * 20.0) * 0.4;
    float outerGlow = exp(-abs(radius - glowRadius) * 8.0) * 0.2;
    
    float totalGlow = innerGlow + middleGlow + outerGlow;
    
    // 更精细的彩虹色
    float hue = normalizedAngle + time * 0.5;
    float3 color = float3(
        sin(hue * 6.28) * 0.5 + 0.5,
        sin(hue * 6.28 + 2.09) * 0.5 + 0.5,
        sin(hue * 6.28 + 4.18) * 0.5 + 0.5
    );
    
    // 增强饱和度和亮度
    color = color * 1.5;
    color = clamp(color, 0.0, 1.0);
    
    // 音频响应的亮度调制
    float brightness = 0.8 + audioValue * 0.4;
    
    // 高频闪烁效果
    float flicker = sin(time * 15.0 + audioValue * 20.0) * 0.1 + 0.9;
    
    // 径向渐变增强
    float radialEnhancement = smoothstep(0.1, 0.6, 1.0 - radius);
    
    totalGlow *= brightness * flicker * radialEnhancement;
    
    return float4(color * totalGlow, totalGlow);
}

#pragma mark - 3D波形效果

vertex RasterizerData waveform3d_vertex(uint vertexID [[vertex_id]],
                                         constant Uniforms& uniforms [[buffer(0)]]) {
    RasterizerData out;
    
    // 创建3D网格顶点
    int gridSize = 80;
    int x = vertexID % gridSize;
    int z = vertexID / gridSize;
    
    float fx = (float(x) / float(gridSize - 1)) * 2.0 - 1.0;
    float fz = (float(z) / float(gridSize - 1)) * 2.0 - 1.0;
    
    // 从音频数据获取高度
    float audioValue = uniforms.audioData[x].x;
    float height = audioValue * 2.0;
    
    // 添加时间波动
    float time = uniforms.time.x;
    height += sin(time + fx * 5.0) * 0.2;
    
    float4 position = float4(fx, height, fz, 1.0);
    
    // 应用变换矩阵
    position = uniforms.projectionMatrix * uniforms.modelViewMatrix * position;
    
    out.position = position;
    out.texCoord = float2(float(x) / float(gridSize), float(z) / float(gridSize));
    
    // 基于高度的颜色
    out.color = float4(height, 1.0 - height, 0.5, 1.0);
    
    return out;
}

fragment float4 waveform3d_fragment(RasterizerData in [[stage_in]],
                                    constant Uniforms& uniforms [[buffer(0)]]) {
    float2 uv = in.texCoord;
    float time = uniforms.time.x;
    
    // 高精度3D波形效果
    float waveform = 0.0;
    float maxWave = 0.0;
    
    // 增加采样点数量，提高清晰度
    for (int i = 0; i < 40; i++) {
        float audioValue = uniforms.audioData[i * 2].x;
        float x = float(i) / 40.0;
        
        // 高频波形，更锐利的边缘
        float wave = sin((uv.x - x) * 80.0 + time * 4.0) * audioValue;
        
        // 更精确的衰减函数
        float falloff = exp(-pow(abs(uv.x - x) * 15.0, 2.0));
        wave *= falloff;
        
        waveform += wave;
        maxWave = max(maxWave, abs(wave));
    }
    
    // 高清晰度3D深度效果
    float depth1 = sin(uv.y * 15.0 + time * 1.2) * 0.15;
    float depth2 = sin(uv.y * 25.0 - time * 0.8) * 0.1;
    float totalDepth = (depth1 + depth2) * 0.5 + 0.7;
    
    waveform *= totalDepth;
    
    // 额外的立体层次
    float layer1 = sin(uv.x * 30.0 + time * 2.0) * maxWave * 0.3;
    float layer2 = sin(uv.y * 20.0 + time * 1.5) * maxWave * 0.2;
    
    float finalWave = waveform + layer1 + layer2;
    
    // 增强的颜色系统
    float intensity = abs(finalWave);
    float3 baseColor = float3(0.1, 0.3, 0.8);
    float3 waveColor = float3(
        0.8 + finalWave * 3.0,
        0.4 + finalWave * 2.5,
        0.2 + finalWave * 2.0
    );
    
    float3 color = mix(baseColor, waveColor, intensity * 2.0);
    
    // 边缘锐化
    float edgeEnhancement = smoothstep(0.1, 0.8, intensity);
    color *= (1.0 + edgeEnhancement * 0.5);
    
    // 亮度和对比度增强
    color = clamp(color * 1.6, 0.0, 1.0);
    
    // 高精度alpha
    float alpha = clamp(intensity + 0.3, 0.0, 1.0);
    
    return float4(color, alpha);
}

#pragma mark - 流体模拟效果

fragment float4 fluid_fragment(RasterizerData in [[stage_in]],
                               constant Uniforms& uniforms [[buffer(0)]]) {
    // 宽高比校正 - 保证流体效果不变形
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float time = uniforms.time.x;
    
    // 优化的流体场模拟 - 减少循环次数提高性能
    float2 field = float2(0.0);
    float2 velocity = float2(0.0);
    
    // 减少循环次数从80到16，大幅提升性能
    for (int i = 0; i < 16; i++) {
        // 使用更高效的索引映射
        int audioIndex = i * 5; // 0, 5, 10, 15, ..., 75
        float audioValue = uniforms.audioData[audioIndex].x;
        
        // 预计算角度值
        float angle = float(i) * 0.39269908; // 2π/16 = 0.39269908
        
        // 优化的源点位置计算
        float2 pos = float2(cos(angle + time * 0.5), sin(angle + time * 0.3)) * 0.25 + 0.5;
        
        float2 diff = uv - pos;
        float distSq = dot(diff, diff); // 使用平方距离避免sqrt
        
        // 避免除零和过小值
        if (distSq > 0.001) {
            float force = audioValue * audioValue;
            
            // 优化的衰减函数 - 避免除法
            float falloff = 1.0 / (distSq * 25.0 + 0.01);
            
            // 归一化方向向量
            float2 direction = diff * rsqrt(distSq); // 使用rsqrt代替normalize
            
            field += direction * force * falloff;
            
            // 简化的涡流效果
            float2 vortex = float2(-direction.y, direction.x) * force * falloff * 0.3;
            velocity += vortex;
        }
    }
    
    // 组合场和速度
    float2 totalField = field + velocity;
    float intensity = length(totalField);
    
    // 简化的流体密度计算 - 减少循环次数
    float density = 0.0;
    for (int j = 0; j < 8; j++) { // 从20减少到8
        int audioIdx = j * 10; // 0, 10, 20, ..., 70
        float audioVal = uniforms.audioData[audioIdx].x;
        float x = float(j) * 0.125; // 1/8 = 0.125
        
        // 优化的波形计算
        float wave = sin(uv.x * 15.0 - time * 2.5 + x * 6.28) * audioVal;
        density += wave * exp(-abs(uv.x - x) * 6.0);
    }
    
    // 限制密度范围防止数值溢出
    density = clamp(density, -1.0, 1.0);
    
    // 优化的颜色系统
    float hue = atan2(totalField.y, totalField.x) * 0.15915494 + 0.5; // 1/(2π) = 0.15915494
    float saturation = clamp(intensity * 1.5, 0.0, 1.0);
    
    // 使用更高效的颜色计算
    float3 color = float3(
        sin(hue * 6.28) * saturation + (1.0 - saturation),
        sin(hue * 6.28 + 2.09) * saturation + (1.0 - saturation),
        sin(hue * 6.28 + 4.18) * saturation + (1.0 - saturation)
    );
    
    // 密度影响颜色 - 减少混合强度
    color = mix(color, float3(0.7, 0.8, 0.9), density * 0.2);
    
    // 简化的流动纹理
    float2 flowUV = uv + totalField * 0.08;
    float flowNoise = sin(flowUV.x * 20.0 + time * 1.5) * sin(flowUV.y * 18.0 + time * 1.2);
    
    // 边缘锐化
    float edgeSharpening = smoothstep(0.2, 0.8, intensity);
    color *= (1.0 + edgeSharpening * 0.5);
    
    // 简化的流动效果
    float flow = sin(dot(totalField, float2(0.707, 0.707)) + time * 2.0) * 0.2 + 0.8;
    flow *= (1.0 + flowNoise * 0.15);
    
    // 最终颜色处理
    color = clamp(color * flow * 1.2, 0.0, 1.0);
    
    // 透明度基于强度
    float alpha = clamp(intensity * 1.2 + 0.3, 0.0, 1.0);
    
    return float4(color, alpha);
}

#pragma mark - 量子场效果

fragment float4 quantum_fragment(RasterizerData in [[stage_in]],
                                 constant Uniforms& uniforms [[buffer(0)]]) {
    // 宽高比校正 - 保证量子场效果不变形
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float time = uniforms.time.x;
    
    // 量子涨落
    float quantum = 0.0;
    
    for (int i = 0; i < 10; i++) {
        float audioValue = uniforms.audioData[i * 8].x;
        float phase = float(i) * 0.628 + time * (1.0 + audioValue);
        
        float2 center = float2(
            sin(phase) * 0.3 + 0.5,
            cos(phase * 1.3) * 0.3 + 0.5
        );
        
        float dist = length(uv - center);
        quantum += audioValue / (dist * 10.0 + 0.1) * sin(phase * 5.0);
    }
    
    // 量子干涉图案
    float interference = sin(quantum * 50.0) * sin(quantum * 30.0 + time);
    
    // 能量场颜色
    float3 color = float3(
        abs(sin(quantum * 2.0 + time)),
        abs(sin(quantum * 2.0 + time + 2.09)),
        abs(sin(quantum * 2.0 + time + 4.18))
    );
    
    float alpha = smoothstep(0.0, 1.0, abs(interference) * 2.0);
    
    return float4(color, alpha);
}

#pragma mark - 全息效果

fragment float4 holographic_fragment(RasterizerData in [[stage_in]],
                                     constant Uniforms& uniforms [[buffer(0)]]) {
    // 宽高比校正 - 保证全息投影不变形
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float2 originalUV = in.texCoord; // 保留原始UV用于扫描线
    float time = uniforms.time.x;
    
    float2 center = float2(0.5, 0.5);
    float2 diff = uv - center;
    float radius = length(diff);
    float angle = atan2(diff.y, diff.x);
    
    // ===== 计算音频数据 =====
    float normalizedAngle = (angle + M_PI_F) / (2.0 * M_PI_F);
    int spectrumIndex = int(normalizedAngle * 79.0);
    float audioValue = uniforms.audioData[spectrumIndex].x;
    
    // 平均音频强度
    float averageAudio = 0.0;
    for (int i = 0; i < 20; i++) {
        averageAudio += uniforms.audioData[i * 4].x;
    }
    averageAudio /= 20.0;
    
    // 低频和高频
    float lowFreq = (uniforms.audioData[5].x + uniforms.audioData[10].x) * 0.5;
    float highFreq = (uniforms.audioData[60].x + uniforms.audioData[70].x) * 0.5;
    
    // ===== 1. 多层全息扫描线系统 =====
    // 主扫描线（细密）
    float mainScanline = sin(originalUV.y * 400.0 + time * 0.5) * 0.05 + 0.95;
    
    // 粗扫描线（增强层次感）
    float coarseScanline = sin(originalUV.y * 80.0 + time * 0.3) * 0.08 + 0.92;
    
    // 动态扫描波（从上到下）
    float scanWavePos = fract(time * 0.08 + lowFreq * 0.3);
    float scanWave = exp(-abs(originalUV.y - scanWavePos) * 30.0) * (0.3 + lowFreq * 0.5);
    
    // 垂直扫描线（模拟栅格）
    float verticalScan = sin(originalUV.x * 200.0) * 0.03 + 0.97;
    
    // 组合扫描线效果
    float scanlineTotal = mainScanline * coarseScanline * verticalScan;
    
    // ===== 2. 全息投影主体 - 多层圆环 =====
    float hologramLayers = 0.0;
    
    // 外层主投影环（音频响应）
    float outerRadius = 0.28 + audioValue * 0.15;
    float outerRing = exp(-abs(radius - outerRadius) * 25.0) * (0.5 + audioValue * 0.8);
    hologramLayers += outerRing;
    
    // 中层投影环（稳定层）
    float midRadius = 0.22 + sin(time * 0.5 + averageAudio * 2.0) * 0.03;
    float midRing = exp(-abs(radius - midRadius) * 30.0) * 0.4;
    hologramLayers += midRing;
    
    // 内层核心环（高频响应）
    float innerRadius = 0.15 + highFreq * 0.08;
    float innerRing = exp(-abs(radius - innerRadius) * 35.0) * (0.3 + highFreq * 0.6);
    hologramLayers += innerRing;
    
    // 核心光点
    float coreGlow = exp(-radius * 12.0) * (0.4 + lowFreq * 0.5);
    hologramLayers += coreGlow;
    
    // ===== 3. 数据流可视化 =====
    float dataStream = 0.0;
    
    // 径向数据条（从中心向外）
    for (int i = 0; i < 12; i++) {
        float rayAngle = float(i) * 0.5236; // 30度间隔
        float angleDiff = abs(angle - rayAngle);
        angleDiff = min(angleDiff, abs(angleDiff - 6.28318)); // 环绕处理
        
        // 音频响应的数据条
        int dataIndex = i * 6;
        float dataValue = uniforms.audioData[dataIndex].x;
        
        // 数据条长度随音频变化
        float dataLength = 0.12 + dataValue * 0.25;
        float dataBar = exp(-angleDiff * 150.0) * smoothstep(dataLength + 0.1, dataLength - 0.05, radius);
        dataBar *= (0.2 + dataValue * 0.7);
        
        // 数据条脉冲效果
        float pulse = sin(time * 3.0 + float(i) * 0.5 + dataValue * 5.0) * 0.3 + 0.7;
        dataStream += dataBar * pulse;
    }
    
    // ===== 4. 全息粒子系统 =====
    float particles = 0.0;
    
    // 旋转粒子云
    float2 particleUV = uv * 15.0;
    particleUV = float2(
        particleUV.x * cos(time * 0.3) - particleUV.y * sin(time * 0.3),
        particleUV.x * sin(time * 0.3) + particleUV.y * cos(time * 0.3)
    );
    
    // 粒子噪声
    float particleNoise1 = fract(sin(dot(floor(particleUV), float2(12.9898, 78.233))) * 43758.5453);
    float particleNoise2 = fract(sin(dot(floor(particleUV * 1.5), float2(93.989, 67.345))) * 23421.6312);
    
    // 音频驱动的粒子
    float particle1 = step(0.92, particleNoise1) * smoothstep(0.4, 0.15, radius);
    particle1 *= (0.3 + averageAudio * 0.8);
    
    float particle2 = step(0.95, particleNoise2) * smoothstep(0.35, 0.1, radius);
    particle2 *= (0.2 + highFreq * 0.7);
    
    particles = particle1 + particle2;
    
    // ===== 5. 干涉图案（全息特征）=====
    float interference = 0.0;
    
    // 同心圆干涉
    float concentricPattern = sin(radius * 60.0 - time * 2.0 + averageAudio * 10.0);
    concentricPattern = smoothstep(0.4, 0.9, concentricPattern) * exp(-radius * 1.5);
    interference += concentricPattern * 0.15;
    
    // 角度干涉
    float angularPattern = sin(angle * 24.0 + time * 1.5);
    angularPattern = smoothstep(0.5, 0.8, angularPattern) * smoothstep(0.4, 0.2, radius);
    interference += angularPattern * 0.12;
    
    // 波纹干涉（从中心扩散）
    float ripple = sin(radius * 40.0 - time * 4.0) * 0.5 + 0.5;
    ripple *= exp(-radius * 2.0) * (0.1 + lowFreq * 0.3);
    interference += ripple;
    
    // ===== 6. 全息文字/符号投影 =====
    float symbols = 0.0;
    
    // 环形文字轨道
    float textRadius = 0.32;
    float textDist = abs(radius - textRadius);
    
    // 创建文字块效果
    float textAngle = angle * 8.0 - time * 0.5;
    float textBlock = step(0.5, fract(textAngle)) * exp(-textDist * 50.0);
    textBlock *= sin(time * 2.0 + audioValue * 3.0) * 0.15 + 0.2;
    
    symbols += textBlock;
    
    // 内圈数据标签
    float labelRadius = 0.18;
    float labelDist = abs(radius - labelRadius);
    float labelPattern = step(0.7, fract(angle * 6.0 + time * 0.3));
    float labels = labelPattern * exp(-labelDist * 60.0) * 0.18;
    
    symbols += labels;
    
    // ===== 7. 全息故障效果（柔和）=====
    float glitch = 0.0;
    
    // 随机故障区域
    float glitchTime = floor(time * 4.0);
    float glitchSeed = fract(sin(glitchTime * 123.456) * 43758.5453);
    
    // 轻微的故障条纹
    if (glitchSeed > 0.85) {
        float glitchY = fract(glitchSeed * 789.123);
        if (abs(originalUV.y - glitchY) < 0.08) {
            glitch = (sin(originalUV.x * 50.0 + time * 30.0) * 0.5 + 0.5) * 0.15;
        }
    }
    
    // ===== 8. 三维投影感 - 深度层次 =====
    // 近景层（亮）
    float nearLayer = smoothstep(0.3, 0.15, radius) * (hologramLayers + particles);
    
    // 中景层（中等）
    float midLayer = smoothstep(0.15, 0.25, radius) * smoothstep(0.4, 0.3, radius) * (dataStream + interference);
    
    // 远景层（暗淡）
    float farLayer = smoothstep(0.25, 0.4, radius) * symbols * 0.6;
    
    // ===== 9. 柔和的全息颜色系统（不刺眼）=====
    // 主色调：柔和的青蓝色
    float3 primaryColor = float3(0.3, 0.7, 0.9);
    
    // 次要色调：淡青色
    float3 secondaryColor = float3(0.5, 0.85, 0.95);
    
    // 强调色：淡紫蓝
    float3 accentColor = float3(0.6, 0.75, 1.0);
    
    // 核心发光：温暖的白色
    float3 coreColor = float3(0.85, 0.9, 1.0);
    
    // 根据半径和音频混合颜色
    float colorMix1 = sin(time * 0.8 + radius * 5.0) * 0.5 + 0.5;
    float colorMix2 = averageAudio;
    
    float3 baseColor = mix(primaryColor, secondaryColor, colorMix1);
    baseColor = mix(baseColor, accentColor, audioValue * 0.4);
    
    // 核心区域使用温暖色
    baseColor = mix(baseColor, coreColor, exp(-radius * 8.0) * 0.6);
    
    // ===== 10. 组合所有效果 =====
    float totalIntensity = nearLayer + midLayer + farLayer + scanWave + glitch;
    
    // 限制最大亮度（避免刺眼）
    totalIntensity = clamp(totalIntensity, 0.0, 0.85);
    
    // 应用颜色
    float3 finalColor = baseColor * totalIntensity;
    
    // 添加粒子（白色点缀）
    finalColor += particles * float3(0.9, 0.95, 1.0) * 0.6;
    
    // 应用扫描线效果
    finalColor *= scanlineTotal;
    
    // ===== 11. 柔和的闪烁效果（不刺眼）=====
    // 去除强烈的闪烁，改用柔和的呼吸效果
    float breathe = sin(time * 1.5 + averageAudio * 3.0) * 0.08 + 0.92;
    finalColor *= breathe;
    
    // 轻微的随机抖动（模拟全息不稳定）
    float shimmer = sin(time * 8.0 + originalUV.y * 20.0) * 0.03 + 0.97;
    finalColor *= shimmer;
    
    // ===== 12. 边缘柔化 =====
    float edgeFade = smoothstep(0.5, 0.35, radius);
    
    // ===== 13. 最终透明度（柔和）=====
    float alpha = totalIntensity * edgeFade;
    
    // 限制透明度范围（避免过于强烈）
    alpha = clamp(alpha * 0.75, 0.0, 0.7);
    
    // 最终颜色增强（轻微）
    finalColor = pow(finalColor, float3(0.95)); // 轻微gamma校正，让颜色更柔和
    finalColor = clamp(finalColor, 0.0, 1.0);
    
    return float4(finalColor, alpha);
}

#pragma mark - 赛博朋克效果

fragment float4 cyberpunk_fragment(RasterizerData in [[stage_in]],
                                   constant Uniforms& uniforms [[buffer(0)]]) {
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float2 originalUV = in.texCoord; // 保留原始UV用于扫描线
    float time = uniforms.time.x;
    
    // 计算平均音频强度
    float averageAudio = 0.0;
    float bassAudio = 0.0;
    float midAudio = 0.0;
    float trebleAudio = 0.0;
    
    // 分频段采样音频（大幅增强，让调试条清晰可见）
    // 低音：0-18（更宽范围） + 大幅增强
    for (int i = 0; i < 18; i++) {
        bassAudio += uniforms.audioData[i].x;
    }
    bassAudio /= 18.0;
    bassAudio *= 1.8; // 大幅增强到3倍
    
    // 中音：18-58（更宽范围） + 增强
    for (int i = 18; i < 58; i++) {
        midAudio += uniforms.audioData[i].x;
    }
    midAudio /= 40.0;
    midAudio *= 1.9; // 大幅增强到2.5倍
    
    // 高音：45-79（更宽范围，从更低频段开始） + 大幅增强
    for (int i = 45; i < 79; i++) {
        trebleAudio += uniforms.audioData[i].x;
    }
    trebleAudio /= 34.0;
    trebleAudio *= 1.6; // 大幅增强到3.5倍
    
    // 限制最大值，避免过度
    bassAudio = min(bassAudio, 1.5);
    midAudio = min(midAudio, 1.5);
    trebleAudio = min(trebleAudio, 1.5);
    
    averageAudio = (bassAudio + midAudio + trebleAudio) / 3.0;
    
    // 🎨 保存原始音频值用于调试显示
    float bassAudioDisplay = bassAudio;
    float midAudioDisplay = midAudio;
    float trebleAudioDisplay = trebleAudio;
    
    // 💡 关键：在multiChannelSuppression之前，先保存完整强度的音频数据用于isClimax计算
    // 这样isClimax不会被抑制因子削弱，保持正常触发
    float bassAudioOriginal = bassAudio;
    float midAudioOriginal = midAudio;
    float trebleAudioOriginal = trebleAudio;
    
    // 🔥 多频段同时触发检测与抑制（防止刺眼）
    // 检测有多少个频段处于高值状态（> 0.3）
    float highBassCount = step(0.3, bassAudio);
    float highMidCount = step(0.3, midAudio);
    float highTrebleCount = step(0.3, trebleAudio);
    float activeChannels = highBassCount + highMidCount + highTrebleCount;
    
    // 根据活跃频段数量计算抑制因子
    // 1个频段：不抑制 (1.0)
    // 2个频段：抑制30% (0.7)
    // 3个频段：抑制50% (0.5)
    float multiChannelSuppression = 1.0;
    if (activeChannels >= 2.0) {
        multiChannelSuppression = 1.0 - (activeChannels - 1.0) * 0.25; // 每增加1个频段，抑制25%
    }
    
    // 对用于视觉效果的音频数据应用抑制（调试显示不受影响）
    bassAudio *= multiChannelSuppression;
    midAudio *= multiChannelSuppression;
    trebleAudio *= multiChannelSuppression;
    
    // 🎛️ 读取赛博朋克控制参数
    float enableClimaxEffect = uniforms.cyberpunkControls.x; // 0.0=关闭, 1.0=开启
    float showDebugBars = uniforms.cyberpunkControls.y;      // 0.0=隐藏, 1.0=显示
    
    // 🎨 读取频段特效控制参数
    float enableBassEffect = uniforms.cyberpunkFrequencyControls.x;   // 0.0=关闭, 1.0=开启（红色低音）
    float enableMidEffect = uniforms.cyberpunkFrequencyControls.y;    // 0.0=关闭, 1.0=开启（绿色中音）
    float enableTrebleEffect = uniforms.cyberpunkFrequencyControls.z; // 0.0=关闭, 1.0=开启（蓝色高音）
    
    // ===== 🔥 高潮检测系统（降低版 - 适配低音频增强，使用原始音频数据）=====
    // 多维度检测音乐高能时刻 - 大幅降低阈值，确保能触发
    
    // 1. 综合能量（使用原始数据）
    float totalEnergy = (bassAudioOriginal + midAudioOriginal + trebleAudioOriginal) / 3.0;
    
    // 2. 低音响应（使用原始数据，降低阈值，提高响应系数）
    float bassResponse = smoothstep(0.08, 0.35, bassAudioOriginal) * 1.5; // 8%开始，35%满
    
    // 3. 中音响应（使用原始数据，降低阈值）
    float midResponse = smoothstep(0.08, 0.35, midAudioOriginal) * 1.4;
    
    // 4. 高音响应（使用原始数据，降低阈值）
    float trebleResponse = smoothstep(0.08, 0.35, trebleAudioOriginal) * 1.5;
    
    // 5. 峰值响应（使用原始数据，降低峰值要求）
    float peakValue = max(max(bassAudioOriginal, midAudioOriginal), trebleAudioOriginal);
    float peakResponse = smoothstep(0.12, 0.4, peakValue) * 1.6; // 12%开始
    
    // 6. 综合响应强度（提高增益系数）
    float responseA = totalEnergy * 2.0; // 提高到2.0
    float responseB = max(max(bassResponse, midResponse), trebleResponse) * 1.3; // 提高到1.3
    float responseC = (bassResponse + midResponse + trebleResponse) / 2.8; // 降低除数
    float responseD = peakResponse * 1.2; // 提高到1.5
    
    // 最终高潮强度（取最大值）
    float isClimax = max(max(responseA, responseB), max(responseC, responseD));
    
    // 🔥 移除低值压缩，让低音频强度也能触发
    // 改为轻微提升低值，让黄色条更容易出现
    if (isClimax < 0.3) {
        isClimax = isClimax * 0.6; // 低值轻微提升
    }
    
    // 🔥 非线性压缩：高值时压缩（避免刺眼）
    if (isClimax > 1.0) {
        float excess = isClimax - 1.0;
        isClimax = 1.0 + sqrt(excess) * 0.5;
    }
    
    // 最终限制：最高1.6（进一步降低上限）
    isClimax = clamp(isClimax, 0.0, 1.6);
    
    // 🎨 保存isClimax用于调试显示（在应用开关之前）
    float isClimaxDisplay = isClimax;
    
    // 🎛️ 应用高能效果开关（只影响视觉效果，不影响调试条）
    if (enableClimaxEffect < 0.5) {
        isClimax = 0.0; // 关闭高能效果时，isClimax强制为0（但isClimaxDisplay保留）
    }
    
    // 🎨 应用频段特效开关（在isClimax计算完成后才应用，这样黄色强度不受红绿蓝开关影响）
    if (enableBassEffect < 0.5) {
        bassAudio = 0.0;         // 关闭低音特效时，低音数据归零
        bassAudioDisplay = 0.0;  // 调试条也归零
    }
    if (enableMidEffect < 0.5) {
        midAudio = 0.0;          // 关闭中音特效时，中音数据归零
        midAudioDisplay = 0.0;   // 调试条也归零
    }
    if (enableTrebleEffect < 0.5) {
        trebleAudio = 0.0;       // 关闭高音特效时，高音数据归零
        trebleAudioDisplay = 0.0; // 调试条也归零
    }
    
    // ===== 1. 故障效果（Glitch）- 根据音频强度 =====
    float2 glitchUV = uv;
    
    // 随机故障区域
    float glitchTime = floor(time * 8.0 + bassAudio * 20.0);
    float glitchRow = fract(sin(glitchTime * 123.456) * 43758.5453);
    float glitchStrength = step(0.95, glitchRow) * bassAudio;
    
    // RGB分离故障
    if (glitchStrength > 0.0) {
        float glitchOffset = (fract(sin(glitchTime * 789.123) * 43758.5453) - 0.5) * 0.05 * bassAudio;
        glitchUV.x += glitchOffset * step(abs(uv.y - glitchRow), 0.1);
    }
    
    // 水平扫描故障
    float scanGlitch = sin(uv.y * 50.0 + time * 30.0 + bassAudio * 40.0);
    glitchUV.x += scanGlitch * 0.003 * bassAudio;
    
    // ===== 2. 霓虹网格系统 =====
    float2 gridUV = glitchUV * 20.0;
    float2 gridID = floor(gridUV);
    float2 gridFract = fract(gridUV);
    
    // 网格线条
    float gridLine = 0.0;
    float lineWidth = 0.08 + bassAudio * 0.1;
    gridLine += step(1.0 - lineWidth, gridFract.x);
    gridLine += step(1.0 - lineWidth, gridFract.y);
    gridLine = clamp(gridLine, 0.0, 1.0);
    
    // 网格闪烁 - 仅音频触发，静态时不闪烁
    float hasAudio = step(0.01, bassAudio + midAudio + trebleAudio); // 检测是否有音频
    
    // 基础闪烁（仅在有音频时）
    float baseFlicker = 1.0; // 静态时不闪烁
    if (hasAudio > 0.0) {
        baseFlicker = sin(time * 5.0 + gridID.x * 2.0 + gridID.y * 3.0 + bassAudio * 15.0) * 0.5 + 0.5;
    }
    
    // ===== 高音触发的方格动画效果 =====
    float gridAnimation = 0.0;
    
    // 1. 随机方格高亮（高音触发）
    float gridNoise = fract(sin(dot(gridID, float2(12.9898, 78.233))) * 43758.5453);
    float gridHighlight = step(0.85, gridNoise) * smoothstep(0.15, 0.5, trebleAudio);
    gridHighlight *= (1.0 + trebleAudio * 2.0); // 高音越强，高亮越亮
    
    // 2. 脉冲波纹效果（从中心扩散）
    float2 gridCenter = gridID - float2(10.0, 10.0); // 网格中心
    float gridDist = length(gridCenter);
    float pulseWave = sin(gridDist * 2.0 - time * 8.0 - trebleAudio * 10.0);
    pulseWave = smoothstep(0.5, 1.0, pulseWave) * smoothstep(0.1, 0.4, trebleAudio);
    pulseWave *= (0.5 + trebleAudio * 1.5);
    
    // 3. 横向扫描效果（高音触发）
    float scanPattern = sin(gridID.y * 0.5 + time * 4.0 + trebleAudio * 8.0);
    scanPattern = smoothstep(0.7, 0.95, scanPattern) * smoothstep(0.12, 0.45, trebleAudio);
    scanPattern *= (0.4 + trebleAudio * 1.2);
    
    // 4. 棋盘闪烁效果
    float checkerboard = step(0.5, fract((gridID.x + gridID.y) * 0.5));
    float checkerFlicker = checkerboard * sin(time * 6.0 + trebleAudio * 12.0) * 0.5 + 0.5;
    checkerFlicker *= smoothstep(0.18, 0.5, trebleAudio) * (0.3 + trebleAudio * 1.0);
    
    // 5. 随机闪烁点（高频音效）
    float sparkle = step(0.95, fract(sin(time * 2.0 + gridID.x * 13.7 + gridID.y * 17.3) * 43758.5453));
    sparkle *= smoothstep(0.2, 0.55, trebleAudio) * (1.0 + trebleAudio * 2.5);
    
    // 组合所有高音动画效果
    gridAnimation = max(max(max(gridHighlight, pulseWave), max(scanPattern, checkerFlicker)), sparkle);
    
    // 最终网格强度：基础网格 + 高音动画效果
    // 静态时：仅基础透明网格（0.15亮度）
    // 有音频时：基础闪烁 + 中音增强 + 高音动画
    float baseIntensity = 0.15; // 静态时的透明基础
    float audioIntensity = baseFlicker * (0.5 + midAudio * 1.5); // 音频时的强度
    
    gridLine *= (baseIntensity + hasAudio * (audioIntensity - baseIntensity + gridAnimation));
    
    // ===== 🌟 高潮专属效果：全屏能量爆发（移除条件判断，始终计算）=====
    float climaxEffect = 0.0;
    
    // 移除 if 判断，让效果强度完全由 isClimax 控制
    {
        // 1. 全屏径向脉冲波（从中心爆发）
        float2 climaxCenter = float2(0.5, 0.5);
        float climaxDist = length(glitchUV - climaxCenter);
        
        // 多层冲击波（快速扩散）- 使用压缩后的isClimax，低值明显，高值不刺眼
        // 创建一个压缩因子：isClimax越高，压缩越多
        float climaxSoftFactor = 1.0 / (1.0 + isClimax * 0.3); // 高值时降低强度系数
        
        float wave1 = sin(climaxDist * 15.0 - time * 20.0 - totalEnergy * 30.0);
        wave1 = smoothstep(0.4, 1.0, wave1) * isClimax * 0.25 * climaxSoftFactor;
        
        float wave2 = sin(climaxDist * 25.0 - time * 25.0 - bassAudio * 40.0);
        wave2 = smoothstep(0.5, 1.0, wave2) * isClimax * 0.22 * climaxSoftFactor;
        
        float wave3 = sin(climaxDist * 35.0 - time * 30.0 - midAudio * 35.0);
        wave3 = smoothstep(0.6, 1.0, wave3) * isClimax * 0.18 * climaxSoftFactor;
        
        float radialPulse = (wave1 + wave2 + wave3) * (1.0 + totalEnergy * 0.4);
        
        // 2. 网格增强（使用软化因子）
        float gridBurst = isClimax * (0.35 + totalEnergy * 0.5) * climaxSoftFactor;
        gridLine += gridBurst * 0.25;
        
        // 3. 旋转射线效果（软化）
        float climaxAngle = atan2(glitchUV.y - climaxCenter.y, glitchUV.x - climaxCenter.x);
        float rayBurst = sin(climaxAngle * 16.0 + time * 10.0) * 0.5 + 0.5;
        rayBurst *= smoothstep(0.6, 0.2, climaxDist);
        rayBurst *= isClimax * (0.3 + totalEnergy * 0.4) * climaxSoftFactor;
        
        // 4. 脉冲效果（软化，避免刺眼闪光）
        float flashPulse = sin(time * 15.0 + totalEnergy * 25.0) * 0.5 + 0.5;
        flashPulse *= isClimax * (0.18 + peakValue * 0.25) * climaxSoftFactor;
        
        // 5. 边缘光晕（软化）
        float edgeExplosion = exp(-climaxDist * 3.0);
        edgeExplosion *= isClimax * (0.22 + bassAudio * 0.35) * climaxSoftFactor;
        
        // 6. 粒子点缀（软化）
        float2 particleBurstUV = glitchUV * 60.0 + time * 8.0;
        float particleBurstNoise = fract(sin(dot(floor(particleBurstUV), float2(12.9898, 78.233))) * 43758.5453);
        float particleBurst = step(0.88, particleBurstNoise) * isClimax * (0.3 + totalEnergy * 0.4) * climaxSoftFactor;
        
        // 7. 螺旋纹理（软化）
        float spiralAngle = climaxAngle + climaxDist * 10.0 - time * 8.0;
        float spiral1 = sin(spiralAngle * 3.0) * 0.5 + 0.5;
        float spiral2 = sin(spiralAngle * 3.0 + 3.14159) * 0.5 + 0.5;
        float spiralEffect = (spiral1 + spiral2) * smoothstep(0.5, 0.2, climaxDist);
        spiralEffect *= isClimax * (0.22 + midAudio * 0.3) * climaxSoftFactor;
        
        // 8. 冲击波环（软化）
        float shockwaveRadius = fract(time * 2.0 + totalEnergy * 3.0) * 0.8;
        float shockwave = exp(-abs(climaxDist - shockwaveRadius) * 50.0);
        shockwave *= isClimax * (0.35 + bassAudio * 0.5) * climaxSoftFactor;
        
        // 组合所有高潮效果（带软化）
        climaxEffect = radialPulse + rayBurst + flashPulse + edgeExplosion 
                      + particleBurst + spiralEffect + shockwave;
        
        // 限制最大值（已经通过climaxSoftFactor软化了）
        climaxEffect = clamp(climaxEffect, 0.0, 1.2); // 降低上限，避免刺眼
    }
    
    // ===== 3. 音频响应的霓虹圆环冲击波 =====
    float2 hexCenter = float2(0.5, 0.5);
    float hexDist = length(glitchUV - hexCenter);
    
    // 低音驱动的主冲击波 - 基础效果 + 音频增强
    float baseIntensity1 = 0.3; // 基础强度，始终可见
    float bassBoost = smoothstep(0.1, 0.4, bassAudio); // 低阈值，容易触发
    
    // 冲击波扩散半径（从小到大）
    float shockwaveRadius1 = 0.15 + bassAudio * 0.4; // 半径随低音增大
    float hexRing1 = exp(-abs(hexDist - shockwaveRadius1) * 35.0);
    hexRing1 *= (baseIntensity1 + bassBoost * 1.5); // 基础可见 + 音频增强
    hexRing1 *= (1.0 + bassAudio * 2.5); // 亮度响应
    
    // 中音驱动的次级波 - 基础效果 + 音频增强
    float baseIntensity2 = 0.25; // 基础强度
    float midBoost = smoothstep(0.08, 0.35, midAudio);
    float shockwaveRadius2 = 0.1 + midAudio * 0.35;
    float hexRing2 = exp(-abs(hexDist - shockwaveRadius2) * 45.0);
    hexRing2 *= (baseIntensity2 + midBoost * 1.2);
    hexRing2 *= (1.0 + midAudio * 2.0);
    
    // ===== 4. 音频响应的角度射线 =====
    float angle = atan2(glitchUV.y - hexCenter.y, glitchUV.x - hexCenter.x);
    
    // 将角度转换为频谱索引，每条射线对应一个频率
    float normalizedAngle = (angle + M_PI_F) / (2.0 * M_PI_F);
    int raySpectrumIndex = int(normalizedAngle * 79.0);
    float rayAudioValue = uniforms.audioData[raySpectrumIndex].x;
    
    // 射线基础效果 + 音频增强
    float baseRayIntensity = 0.15; // 基础强度
    float rayStrength = smoothstep(0.05, 0.25, rayAudioValue); // 低阈值
    
    // 射线从中心发出，长度由音频控制
    float rayLength = 0.1 + rayAudioValue * 0.45; // 基础长度 + 音频延伸
    float rayPattern = sin(angle * 16.0 + time * 0.5) * 0.5 + 0.5;
    
    // 射线形状：从中心向外，基于音频强度
    float rays = rayPattern * smoothstep(rayLength + 0.15, rayLength - 0.05, hexDist);
    rays *= (baseRayIntensity + rayStrength * 1.0); // 基础可见 + 音频增强
    rays *= exp(-hexDist * 2.0); // 径向衰减
    rays *= (0.4 + rayAudioValue * 1.8); // 亮度跟随该频率的音频
    
    // ===== 5. 数字流 =====
    float2 digitGridUV = glitchUV * float2(40.0, 60.0);
    float2 digitGridID = floor(digitGridUV);
    float2 digitGridFract = fract(digitGridUV);
    
    // 音频响应的数字流
    float audioIndex = fmod(digitGridID.x, 80.0);
    float digitAudioValue = uniforms.audioData[int(audioIndex)].x;
    
    // 下降速度基于音频
    float fallSpeed = 3.0 + digitAudioValue * 8.0;
    float yOffset = fmod(time * fallSpeed + digitGridID.x * 0.5, 60.0);
    
    // 创建数字字符
    float digitNoise = fract(sin(dot(digitGridID, float2(12.9898, 78.233))) * 43758.5453);
    float character = step(0.6, digitNoise);
    float trail = smoothstep(0.0, 8.0, yOffset - digitGridID.y) * 
                  smoothstep(20.0, 12.0, yOffset - digitGridID.y);
    
    // 字符形状
    float charShape = step(0.3, digitGridFract.x) * step(digitGridFract.x, 0.7) * 
                      step(0.2, digitGridFract.y) * step(digitGridFract.y, 0.8);
    
    float digits = character * trail * charShape * (0.2 + digitAudioValue * 0.8);
    
    // ===== 6. 音频响应的扫描线系统 =====
    // 主扫描线（使用原始UV保持水平）- 密度随音频变化
    float scanlineMain = sin(originalUV.y * 300.0 + time * 2.0) * 0.15 + 0.85;
    
    // 粗扫描线（低音响应）
    float coarseScanline = sin(originalUV.y * 80.0 + time * 1.0 + bassAudio * 3.0) * 0.1 + 0.9;
    coarseScanline *= (0.9 + bassAudio * 0.2);
    
    // 低音驱动的扫描波 - 始终存在，音频时变强
    float baseScanIntensity = 0.3; // 基础强度
    float scanWaveBoost = smoothstep(0.05, 0.3, bassAudio); // 低阈值
    
    // 扫描波位置（从顶部扫到底部，速度随低音）
    float scanWavePos = fract(time * 0.15 + bassAudio * 1.0);
    float scanWave = smoothstep(0.02, 0.0, abs(originalUV.y - scanWavePos));
    scanWave *= (baseScanIntensity + scanWaveBoost * 1.5); // 基础可见 + 音频增强
    scanWave *= (1.0 + bassAudio * 2.5); // 亮度跟随低音
    
    // 中音驱动的次级扫描波 - 始终存在
    float baseScan2Intensity = 0.2;
    float scanWave2Boost = smoothstep(0.04, 0.25, midAudio);
    float scanWave2Pos = fract(time * 0.2 + midAudio * 0.8);
    float scanWave2 = smoothstep(0.015, 0.0, abs(originalUV.y - scanWave2Pos));
    scanWave2 *= (baseScan2Intensity + scanWave2Boost * 1.2);
    scanWave2 *= (1.0 + midAudio * 2.0);
    
    // 高音驱动的快速扫描 - 音频时触发
    float trebleScanBoost = smoothstep(0.08, 0.3, trebleAudio);
    float trebleScanPos = fract(time * 0.35 + trebleAudio * 0.6);
    float trebleScan = smoothstep(0.008, 0.0, abs(originalUV.y - trebleScanPos));
    trebleScan *= trebleScanBoost * (1.0 + trebleAudio * 1.8);
    
    // 组合所有扫描线
    float scanlineTotal = scanlineMain * coarseScanline;
    
    // ===== 7. 音频响应的赛博朋克配色系统 =====
    // 霓虹青色（主色调）- 网格和次级圆环，中音控制
    float cyanIntensity = (gridLine + hexRing2) * (1.0 + midAudio * 2.0);
    float3 cyanNeon = float3(0.0, 1.0, 1.0) * cyanIntensity;
    
    // 霓虹粉红/品红（副色调）- 主圆环和射线，低音控制
    float magentaIntensity = (hexRing1 + rays) * (1.0 + bassAudio * 3.0);
    float3 magentaNeon = float3(1.0, 0.0, 0.8) * magentaIntensity;
    
    // 霓虹紫色（强调色）- 所有扫描波
    float purpleIntensity = (scanWave + scanWave2 + trebleScan) * (1.2 + bassAudio * 2.5);
    float3 purpleNeon = float3(0.8, 0.0, 1.0) * purpleIntensity;
    
    // 🔥 高潮时的特殊配色（使用压缩后的isClimax + 多频段抑制）
    float3 climaxColor = float3(0.0);
    
    // 使用平方根软化 + 多频段抑制
    float climaxColorFactor = sqrt(isClimax) * 0.6 * multiChannelSuppression; // 添加多频段抑制
    
    // 柔和的金色光晕
    float3 goldCore = float3(0.9, 0.8, 0.4) * climaxEffect * 0.35 * climaxColorFactor;
    // 柔和的暖橙色
    float3 orangeGlow = float3(0.8, 0.5, 0.2) * climaxEffect * 0.22 * climaxColorFactor;
    
    climaxColor = goldCore + orangeGlow;
    
    // 霓虹颜色增强（使用压缩后的值 + 多频段抑制）
    float neonBoost = sqrt(isClimax) * 0.45 * multiChannelSuppression; // 添加抑制
    cyanNeon *= (1.0 + neonBoost);
    magentaNeon *= (1.0 + neonBoost * 1.05);
    purpleNeon *= (1.0 + neonBoost * 1.1);
    
    // 数字雨颜色（绿色到青色渐变）
    float3 digitColor = mix(
        float3(0.0, 1.0, 0.2),  // 经典绿色
        float3(0.0, 1.0, 1.0),  // 青色
        digitAudioValue
    ) * digits;
    
    // ===== 8. 音频响应的粒子爆发效果 =====
    float2 particleUV = glitchUV * 50.0 + time * 2.0;
    float particleNoise = fract(sin(dot(floor(particleUV), float2(12.9898, 78.233))) * 43758.5453);
    
    // 粒子基础效果 + 高音爆发
    float baseParticleIntensity = 0.2;
    float particleTrigger = smoothstep(0.1, 0.35, trebleAudio); // 低阈值
    float particles = step(0.97, particleNoise) * (baseParticleIntensity + particleTrigger * 1.5);
    particles *= (1.0 + trebleAudio * 2.0);
    
    // 粒子颜色根据音频强度变化
    float3 particleColor = mix(
        float3(1.0, 1.0, 0.5),  // 黄白色（低强度）
        float3(1.0, 0.3, 1.0),  // 品红色（高强度）
        trebleAudio
    ) * particles;
    
    // ===== 9. 音频驱动的边缘冲击波（主要由音频控制）=====
    float edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    
    // 边缘脉冲 - 极弱基础 + 强烈音频响应
    float baseEdgeIntensity = 0.03; // 极弱基础，几乎不可见
    float edgePulse = smoothstep(0.05, 0.35, bassAudio); // 音频驱动
    float edgeGlow = exp(-edgeDist * 6.0) * (baseEdgeIntensity + edgePulse * 1.2);
    edgeGlow *= (0.5 + bassAudio * 3.0); // 主要靠音频驱动亮度
    
    // 边缘闪光效果 - 多频段触发
    // 1. 低音触发（主要触发源）
    float bassFlashTrigger = smoothstep(0.05, 0.35, bassAudio);
    
    // 2. 中音触发（让中频也能触发闪光）
    float midFlashTrigger = smoothstep(0.08, 0.38, midAudio) * 0.85;
    
    // 3. 高音触发（高频音效时也闪烁）
    float trebleFlashTrigger = smoothstep(0.1, 0.4, trebleAudio) * 0.7;
    
    // 4. 整体音频能量触发（任何频段有能量就能触发）
    float totalAudioEnergy = (bassAudio + midAudio + trebleAudio) / 3.0;
    float energyFlashTrigger = smoothstep(0.06, 0.32, totalAudioEnergy) * 0.75;
    
    // 组合所有触发源（取最大值，确保任意一个触发都能生效）
    float combinedFlashTrigger = max(max(bassFlashTrigger, midFlashTrigger), 
                                     max(trebleFlashTrigger, energyFlashTrigger));
    
    // 闪光效果（根据主要频段强度调整亮度）
    float edgeFlash = exp(-edgeDist * 12.0) * combinedFlashTrigger * (1.0 + totalAudioEnergy * 2.5);
    
    float3 edgeColor = float3(1.0, 0.0, 0.5) * (edgeGlow + edgeFlash);
    
    // ===== 10. RGB色差（Chromatic Aberration）=====
    float rgbSplit = bassAudio * 0.02;
    float2 rOffset = float2(rgbSplit, 0.0);
    float2 bOffset = float2(-rgbSplit, 0.0);
    
    // ===== 组合所有效果 =====
    float3 finalColor = float3(0.0);
    
    // 基础霓虹网格和图形
    finalColor += cyanNeon * 1.5;
    finalColor += magentaNeon * 1.3;
    finalColor += purpleNeon * 1.8;
    
    // 数字雨
    finalColor += digitColor * 1.2;
    
    // 粒子和边缘发光
    finalColor += particleColor;
    finalColor += edgeColor;
    
    // 🌟 高潮特效叠加（最高优先级）
    finalColor += climaxColor;
    
    // 🔍 调试可视化（屏幕中央显示音频强度条 - 全屏宽度版）
    // 🎛️ 通过showDebugBars开关控制显示
    // 使用未抑制的显示值，确保调试条准确反映音频
    if (showDebugBars > 0.5) {
        // 垂直居中区域显示三个频段
        float centerY = 0.5;
        float barHeight = 0.08; // 每个条的高度（缩小以便更清晰）
        float barSpacing = 0.12; // 条之间的间距
    
    // 从屏幕边缘到边缘（几乎全宽）
    float barStart = 0.02;  // 左边缘 2%
    float barEnd = 0.98;    // 右边缘 98%
    float barFullWidth = barEnd - barStart; // 96% 宽度
    
    // 低音条（红色）- 顶部 - 使用显示值
    float bassBarTop = centerY - barSpacing;
    float bassBarBottom = bassBarTop + barHeight;
    if (originalUV.y > bassBarTop && originalUV.y < bassBarBottom) {
        if (originalUV.x > barStart && originalUV.x < barEnd) {
            // 从屏幕左边缘开始计算 - 使用未抑制的显示值
            float bassBar = step(originalUV.x, barStart + bassAudioDisplay * barFullWidth);
            // 深红色条，深灰色背景
            float3 bassColor = float3(1.0, 0.0, 0.0);
            float3 bgColor = float3(0.2, 0.2, 0.2);
            finalColor = mix(bgColor, bassColor, bassBar * 0.95);
        }
    }
    
    // 中音条（绿色）- 中间 - 使用显示值
    float midBarTop = centerY;
    float midBarBottom = midBarTop + barHeight;
    if (originalUV.y > midBarTop && originalUV.y < midBarBottom) {
        if (originalUV.x > barStart && originalUV.x < barEnd) {
            float midBar = step(originalUV.x, barStart + midAudioDisplay * barFullWidth);
            float3 midColor = float3(0.0, 1.0, 0.0);
            float3 bgColor = float3(0.2, 0.2, 0.2);
            finalColor = mix(bgColor, midColor, midBar * 0.95);
        }
    }
    
    // 高音条（蓝色）- 底部 - 使用显示值
    float trebleBarTop = centerY + barSpacing;
    float trebleBarBottom = trebleBarTop + barHeight;
    if (originalUV.y > trebleBarTop && originalUV.y < trebleBarBottom) {
        if (originalUV.x > barStart && originalUV.x < barEnd) {
            float trebleBar = step(originalUV.x, barStart + trebleAudioDisplay * barFullWidth);
            float3 trebleColor = float3(0.3, 0.7, 1.0);
            float3 bgColor = float3(0.2, 0.2, 0.2);
            finalColor = mix(bgColor, trebleColor, trebleBar * 0.95);
        }
    }
    
    // isClimax强度指示器（屏幕底部 - 横向黄条）- 使用Display值，不受开关影响
    float climaxBarBottom = 0.05;
    float climaxBarTop = 0.12;
    if (originalUV.y > climaxBarBottom && originalUV.y < climaxBarTop) {
        if (originalUV.x > barStart && originalUV.x < barEnd) {
            // 使用isClimaxDisplay，即使关闭高能效果也能看到实际强度
            float climaxLength = max(isClimaxDisplay, 0.05); // 至少5%可见
            float climaxBar = step(originalUV.x, barStart + climaxLength * barFullWidth);
            // 金黄色条，深灰色背景
            float3 climaxColor = float3(1.0, 0.9, 0.0);
            float3 bgColor = float3(0.2, 0.2, 0.2);
            finalColor = mix(bgColor, climaxColor, climaxBar * 0.98);
        }
    }
    
    // 添加数值标签（色块标识）
    float labelSize = 0.015;
    // Bass标签（红色方块 - 左上）
    if (originalUV.y > bassBarTop - 0.02 && originalUV.y < bassBarTop - 0.02 + labelSize && 
        originalUV.x > 0.005 && originalUV.x < 0.005 + labelSize) {
        finalColor = float3(1.0, 0.0, 0.0);
    }
    // Mid标签（绿色方块）
    if (originalUV.y > midBarTop - 0.02 && originalUV.y < midBarTop - 0.02 + labelSize && 
        originalUV.x > 0.005 && originalUV.x < 0.005 + labelSize) {
        finalColor = float3(0.0, 1.0, 0.0);
    }
    // Treble标签（蓝色方块）
    if (originalUV.y > trebleBarTop - 0.02 && originalUV.y < trebleBarTop - 0.02 + labelSize && 
        originalUV.x > 0.005 && originalUV.x < 0.005 + labelSize) {
        finalColor = float3(0.3, 0.7, 1.0);
    }
        // Climax标签（金色方块 - 底部）
        if (originalUV.y > climaxBarBottom - 0.015 && originalUV.y < climaxBarBottom - 0.015 + labelSize && 
            originalUV.x > 0.005 && originalUV.x < 0.005 + labelSize) {
            finalColor = float3(1.0, 0.9, 0.0);
        }
    } // 结束 showDebugBars 判断
    
    // 应用扫描线效果
    finalColor *= scanlineTotal;
    
    // 整体亮度调制（柔和脉冲 + 多频段抑制）
    // 低音：柔和脉冲 + 抑制
    float bassPulse = 0.88 + bassAudio * 0.28 * multiChannelSuppression;
    // 高频：柔和闪烁 + 抑制
    float treblePulse = 1.0 + sin(time * 15.0) * trebleAudio * 0.1 * multiChannelSuppression;
    // 🔥 高潮：平方根压缩 + 多频段抑制
    float climaxPulseFactor = sqrt(isClimax) * 0.7 * multiChannelSuppression;
    float climaxPulse = 1.0 + climaxPulseFactor * (0.18 + sin(time * 20.0 + totalEnergy * 30.0) * 0.08);
    // 组合脉冲
    float pulse = bassPulse * treblePulse * climaxPulse;
    finalColor *= pulse;
    
    // 柔和的对比度调整（使用压缩 + 多频段抑制）
    float contrastBoost = sqrt(isClimax) * 0.22 * multiChannelSuppression;
    float contrast = 1.0 + averageAudio * 0.3 + contrastBoost;
    finalColor = (finalColor - 0.5) * contrast + 0.5;
    
    // 柔和的色彩增强（添加多频段抑制）
    float gammaAdjust = sqrt(isClimax) * 0.035 * multiChannelSuppression;
    finalColor = pow(finalColor, float3(0.96 - gammaAdjust));
    float brightnessBoost = sqrt(isClimax) * 0.3 * multiChannelSuppression;
    finalColor *= (1.15 + averageAudio * 0.25 + brightnessBoost);
    
    // 防止过曝
    finalColor = clamp(finalColor, 0.0, 1.0);
    
    // ===== 音频响应的透明度（防刺眼版本）=====
    float totalIntensity = (gridLine + hexRing1 + hexRing2 + rays + digits + particles + climaxEffect * 0.35);
    
    // 🔥 多频段触发时降低透明度（防止叠加刺眼）
    // activeChannels: 1个频段=正常, 2个=降低, 3个=大幅降低
    float alphaMultiplier = multiChannelSuppression; // 复用多频段抑制因子
    
    // 基础透明度计算（降低基础值）
    float baseAlpha = totalIntensity + 0.35 + averageAudio * 0.45 + isClimax * 0.3;
    
    // 应用多频段抑制
    float alpha = clamp(baseAlpha * alphaMultiplier, 0.0, 0.9); // 最高限制到90%透明度
    
    return float4(finalColor, alpha);
}

#pragma mark - 星系效果

fragment float4 galaxy_fragment(RasterizerData in [[stage_in]],
                                constant Uniforms& uniforms [[buffer(0)]]) {
    // 宽高比校正 - 保证星系是圆形不变形
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float time = uniforms.time.x;
    
    // 从控制面板获取参数
    float coreIntensity = uniforms.galaxyParams1.x;
    float edgeIntensity = uniforms.galaxyParams1.y;
    float rotationSpeedParam = uniforms.galaxyParams1.z;
    float glowRadius = uniforms.galaxyParams1.w;
    
    float colorShiftSpeed = uniforms.galaxyParams2.x;
    float nebulaIntensity = uniforms.galaxyParams2.y;
    float pulseStrength = uniforms.galaxyParams2.z;
    float audioSensitivity = uniforms.galaxyParams2.w;
    
    float starDensity = uniforms.galaxyParams3.x;
    float spiralArms = uniforms.galaxyParams3.y;
    int colorTheme = int(uniforms.galaxyParams3.z);
    
    // 星系中心
    float2 center = float2(0.5, 0.5);
    float2 diff = uv - center;
    float radius = length(diff);
    float angle = atan2(diff.y, diff.x);
    
    // 基于音频和控制面板的星系旋转速度
    float averageAudio = 0.0;
    for (int i = 0; i < 20; i++) {
        averageAudio += uniforms.audioData[i].x;
    }
    averageAudio /= 20.0;
    float rotationSpeed = rotationSpeedParam + averageAudio * audioSensitivity;
    
    // 多层螺旋臂结构（使用控制面板的螺旋臂数量）
    float spiralArm1 = sin(angle * spiralArms - radius * 8.0 + time * rotationSpeed) * 0.5 + 0.5;
    float spiralArm2 = sin(angle * spiralArms - radius * 8.0 + time * rotationSpeed + 3.14159) * 0.5 + 0.5;
    float spiralArm3 = sin(angle * (spiralArms * 2.0) - radius * 12.0 + time * rotationSpeed * 0.7) * 0.3 + 0.3;
    
    // 音频驱动的螺旋臂亮度
    float normalizedAngle = (angle + M_PI_F) / (2.0 * M_PI_F);
    int spectrumIndex = int(normalizedAngle * 79.0);
    float audioValue = uniforms.audioData[spectrumIndex].x * audioSensitivity;
    
    // 径向频谱分析
    int radiusIndex = int(clamp(radius * 79.0, 0.0, 79.0));
    float radiusAudio = uniforms.audioData[radiusIndex].x * audioSensitivity;
    
    // 星系核心亮度（基于低频和控制面板参数）
    float coreIntensityAudio = 0.0;
    for (int i = 0; i < 10; i++) {
        coreIntensityAudio += uniforms.audioData[i].x;
    }
    coreIntensityAudio /= 10.0;
    
    // 星系外围亮度（基于高频和控制面板参数）
    float edgeIntensityAudio = 0.0;
    for (int i = 60; i < 80; i++) {
        edgeIntensityAudio += uniforms.audioData[i].x;
    }
    edgeIntensityAudio /= 20.0;
    
    // 星系密度分布函数（使用控制面板参数）
    float coreDensity = exp(-radius * 15.0) * (coreIntensity + coreIntensityAudio * audioSensitivity);
    float diskDensity = exp(-radius * 2.5) * (1.0 - exp(-radius * 8.0));
    float haloDensity = exp(-radius * 0.8) * 0.3;
    
    // 螺旋臂组合
    float spiralPattern = (spiralArm1 + spiralArm2) * 0.5 + spiralArm3 * 0.3;
    spiralPattern *= (1.0 + audioValue * 1.5);
    
    // 星系结构亮度（使用控制面板参数）
    float galaxyBrightness = coreDensity + diskDensity * spiralPattern + haloDensity;
    galaxyBrightness *= (0.8 + radiusAudio * 0.4);
    
    // 动态颜色系统（使用控制面板的颜色变化速度）
    float3 coreColor = float3(1.0, 0.9, 0.7); // 温暖的核心颜色
    float3 diskColor = float3(0.8, 0.9, 1.0); // 冷色调的盘面
    float3 armColor = float3(0.9, 0.7, 1.0);  // 螺旋臂的紫色调
    
    // 基于音频频率和控制面板的颜色调制
    float colorShift = sin(time * colorShiftSpeed + averageAudio * 10.0) * 0.3;
    coreColor.r += colorShift;
    diskColor.g += colorShift * 0.5;
    armColor.b += colorShift * 0.7;
    
    // 颜色混合（使用控制面板的边缘亮度参数）
    float3 finalColor = coreColor * coreDensity;
    finalColor += diskColor * diskDensity * (0.7 + edgeIntensityAudio * edgeIntensity * 0.6);
    finalColor += armColor * spiralPattern * diskDensity;
    
    // 星光点缀系统（使用控制面板的星星密度参数）
    float2 starUV1 = uv * (30.0 * starDensity) + time * 0.1;
    float2 starUV2 = uv * (50.0 * starDensity) - time * 0.15;
    float2 starUV3 = uv * (80.0 * starDensity) + time * 0.08;
    
    // 大星星（亮星）
    float star1 = step(0.995, fractalNoise(starUV1, 2));
    float star1Brightness = star1 * (0.8 + audioValue * 0.4);
    
    // 中等星星
    float star2 = step(0.99, fractalNoise(starUV2, 3));
    float star2Brightness = star2 * (0.5 + edgeIntensityAudio * 0.3);
    
    // 小星星（密集）
    float star3 = step(0.985, fractalNoise(starUV3, 4));
    float star3Brightness = star3 * (0.3 + radiusAudio * 0.2);
    
    // 星光颜色（基于位置和音频）
    float3 starColor1 = float3(1.0, 0.95, 0.9) * star1Brightness;
    float3 starColor2 = float3(0.9, 0.95, 1.0) * star2Brightness;
    float3 starColor3 = float3(1.0, 1.0, 0.95) * star3Brightness;
    
    finalColor += starColor1 + starColor2 + starColor3;
    
    // 边缘模糊光源效果（使用控制面板的光晕半径参数）
    float glowIntensity = smoothstep(glowRadius + 0.1, glowRadius - 0.1, radius);
    
    // 多层光晕效果（使用控制面板参数）
    float innerGlow = exp(-radius * 5.0) * (0.5 + coreIntensityAudio * coreIntensity * 0.5);
    float outerGlow = exp(-radius * 1.5) * (0.2 + averageAudio * audioSensitivity * 0.3);
    float atmosphereGlow = exp(-radius * 0.5) * 0.1;
    
    // 光晕颜色
    float3 glowColor = float3(0.7, 0.8, 1.0) * (innerGlow + outerGlow + atmosphereGlow);
    
    // 脉冲效果（基于音频节拍和控制面板的脉冲强度）
    float pulse = sin(time * 3.0 + averageAudio * 20.0) * pulseStrength + (1.0 - pulseStrength);
    finalColor *= pulse;
    
    // 多彩星云效果（使用控制面板的星云强度参数）
    float2 nebulaUV1 = uv * 1.5 + time * 0.03;
    float2 nebulaUV2 = uv * 2.5 + time * 0.07;
    float2 nebulaUV3 = uv * 3.2 - time * 0.05;
    
    // 不同类型的星云（基于控制面板的星云强度）
    float nebula1 = fractalNoise(nebulaUV1, 4) * nebulaIntensity; // 红色星云
    float nebula2 = fractalNoise(nebulaUV2, 3) * nebulaIntensity; // 蓝色星云
    float nebula3 = fractalNoise(nebulaUV3, 5) * nebulaIntensity; // 绿色星云
    
    // 距离衰减
    float nebulaFalloff = exp(-radius * 0.8);
    nebula1 *= nebulaFalloff;
    nebula2 *= nebulaFalloff;
    nebula3 *= nebulaFalloff;
    
    // 音频调制不同颜色的星云
    float lowFreq = (uniforms.audioData[5].x + uniforms.audioData[6].x) * 0.5;
    float midFreq = (uniforms.audioData[25].x + uniforms.audioData[30].x) * 0.5;
    float highFreq = (uniforms.audioData[65].x + uniforms.audioData[70].x) * 0.5;
    
    // 丰富多彩的星云颜色系统
    // 主要星云层 - 基础三原色系
    float3 redNebula = float3(1.0, 0.2, 0.3) * nebula1 * (0.7 + lowFreq * 0.9);        // 深红发射星云
    float3 blueNebula = float3(0.1, 0.4, 1.0) * nebula2 * (0.6 + midFreq * 0.8);       // 深蓝反射星云
    float3 greenNebula = float3(0.2, 0.9, 0.4) * nebula3 * (0.5 + highFreq * 0.7);     // 翠绿行星状星云
    
    // 扩展彩色星云层
    float2 nebulaUV4 = uv * 1.8 + time * 0.02;
    float nebula4 = fractalNoise(nebulaUV4, 3) * 0.3 * nebulaFalloff;
    float3 purpleNebula = float3(0.8, 0.2, 1.0) * nebula4 * (0.6 + averageAudio * 0.7); // 深紫色星云
    
    float2 nebulaUV5 = uv * 2.8 - time * 0.04;
    float nebula5 = fractalNoise(nebulaUV5, 4) * 0.25 * nebulaFalloff;
    float3 orangeNebula = float3(1.0, 0.6, 0.1) * nebula5 * (0.5 + coreIntensity * 0.6); // 橙色星云
    
    // 新增多彩星云层
    float2 nebulaUV6 = uv * 2.2 + time * 0.06;
    float nebula6 = fractalNoise(nebulaUV6, 5) * 0.28 * nebulaFalloff;
    float3 yellowNebula = float3(1.0, 0.9, 0.2) * nebula6 * (0.4 + (lowFreq + midFreq) * 0.4); // 金黄色星云
    
    float2 nebulaUV7 = uv * 3.5 - time * 0.03;
    float nebula7 = fractalNoise(nebulaUV7, 3) * 0.22 * nebulaFalloff;
    float3 cyanNebula = float3(0.2, 0.8, 0.9) * nebula7 * (0.5 + highFreq * 0.5); // 青色星云
    
    float2 nebulaUV8 = uv * 1.6 + time * 0.08;
    float nebula8 = fractalNoise(nebulaUV8, 4) * 0.2 * nebulaFalloff;
    float3 magentaNebula = float3(1.0, 0.3, 0.8) * nebula8 * (0.3 + (midFreq + highFreq) * 0.4); // 洋红星云
    
    float2 nebulaUV9 = uv * 2.6 - time * 0.05;
    float nebula9 = fractalNoise(nebulaUV9, 6) * 0.18 * nebulaFalloff;
    float3 indigoNebula = float3(0.3, 0.1, 0.9) * nebula9 * (0.4 + lowFreq * 0.6); // 靛蓝星云
    
    // 主题驱动的颜色系统（使用控制面板的颜色主题参数）
    float timePhase = time * 0.2;
    float audioPhase = averageAudio * 5.0;
    
    // 定义8种不同的颜色主题（使用控制面板传递的主题ID）
    float3 nebulaColor = float3(0.0);
    
    if (colorTheme == 0) {
        // 🌈 彩虹主题 - 全光谱循环
        float3 rainbow1 = redNebula + orangeNebula + yellowNebula;
        float3 rainbow2 = greenNebula + cyanNebula + blueNebula;
        float3 rainbow3 = indigoNebula + purpleNebula + magentaNebula;
        float rainbowCycle = sin(timePhase * 2.0) * 0.5 + 0.5;
        nebulaColor = mix(mix(rainbow1, rainbow2, rainbowCycle), rainbow3, cos(timePhase) * 0.5 + 0.5);
        
    } else if (colorTheme == 1) {
        // 🔥 火焰主题 - 红橙黄为主
        nebulaColor = redNebula * 1.5 + orangeNebula * 1.3 + yellowNebula * 1.1;
        nebulaColor += purpleNebula * 0.3; // 少量紫色增加深度
        
    } else if (colorTheme == 2) {
        // ❄️ 冰霜主题 - 蓝青白为主
        nebulaColor = blueNebula * 1.4 + cyanNebula * 1.2 + indigoNebula * 0.8;
        nebulaColor = mix(nebulaColor, float3(0.9, 0.95, 1.0), 0.3); // 增加冰蓝色调
        
    } else if (colorTheme == 3) {
        // 🌸 樱花主题 - 粉色为主
        float3 pinkNebula = mix(redNebula, magentaNebula, 0.7);
        nebulaColor = pinkNebula * 1.3 + purpleNebula * 0.8 + float3(1.0, 0.8, 0.9) * 0.4;
        
    } else if (colorTheme == 4) {
        // 🌿 翠绿主题 - 绿色生机
        nebulaColor = greenNebula * 1.5 + cyanNebula * 0.7 + yellowNebula * 0.5;
        nebulaColor += float3(0.3, 0.8, 0.4) * 0.6; // 自然绿色
        
    } else if (colorTheme == 5) {
        // 🌅 日落主题 - 暖色渐变
        nebulaColor = orangeNebula * 1.4 + redNebula * 1.1 + yellowNebula * 0.9;
        nebulaColor += purpleNebula * 0.4; // 日落紫色
        
    } else if (colorTheme == 6) {
        // 🌌 深空主题 - 深蓝紫色
        nebulaColor = indigoNebula * 1.3 + purpleNebula * 1.1 + blueNebula * 0.8;
        nebulaColor += float3(0.2, 0.1, 0.4) * 0.5; // 深空色调
        
    } else {
        // ✨ 梦幻主题 - 多彩混合
        float dreamCycle = sin(timePhase * 3.0 + audioPhase) * 0.5 + 0.5;
        nebulaColor = mix(purpleNebula + magentaNebula, cyanNebula + greenNebula, dreamCycle);
        nebulaColor += (redNebula + yellowNebula) * 0.3;
    }
    
    // 通用颜色增强
    float intensityBoost = 1.2 + averageAudio * 1.8;
    float radialShift = sin(radius * 8.0 + time * 0.5) * 0.4 + 0.8;
    float angleShift = cos(angle * 3.0 + time * 0.3) * 0.3 + 0.9;
    
    nebulaColor *= intensityBoost * radialShift * angleShift;
    
    // 颜色闪烁效果
    float colorSparkle = sin(time * 2.5 + radius * 15.0) * 0.15 + 0.9;
    nebulaColor *= colorSparkle;
    
    finalColor += nebulaColor + glowColor;
    
    // 最终亮度和透明度
    float finalAlpha = clamp(galaxyBrightness + glowIntensity * 0.5, 0.0, 1.0);
    
    // 边缘软化
    float edgeSoftness = smoothstep(0.8, 0.6, radius);
    finalAlpha *= edgeSoftness;
    
    return float4(finalColor, finalAlpha);
}
