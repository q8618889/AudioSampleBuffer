//
//  HolographicShader.metal
//  AudioSampleBuffer
//
//  全息效果着色器
//

#include "ShaderCommon.metal"

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

