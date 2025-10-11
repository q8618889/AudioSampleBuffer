//
//  LightningShader.metal
//  AudioSampleBuffer
//
//  音频闪电雷暴效果着色器 - 电光闪烁，频率驱动
//  特点：分形闪电、脉冲能量、低频主闪电、高频枝干跳动
//

#include "ShaderCommon.metal"

#pragma mark - 辅助函数

// 闪电分形噪声（增强版）
static inline float lightningNoise(float2 p, float time) {
    float2 i = floor(p);
    float2 f = fract(p);
    
    // 四角随机值
    float a = noise(i);
    float b = noise(i + float2(1.0, 0.0));
    float c = noise(i + float2(0.0, 1.0));
    float d = noise(i + float2(1.0, 1.0));
    
    // 时间扰动
    a += sin(time * 3.0 + a * 6.28) * 0.3;
    b += sin(time * 3.5 + b * 6.28) * 0.3;
    c += sin(time * 4.0 + c * 6.28) * 0.3;
    d += sin(time * 4.5 + d * 6.28) * 0.3;
    
    // 平滑插值
    float2 u = f * f * (3.0 - 2.0 * f);
    
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 分形布朗运动（增强闪电纹理）
static inline float fbmLightning(float2 p, float time, int octaves) {
    float value = 0.0;
    float amplitude = 0.6;
    float frequency = 1.0;
    
    for (int i = 0; i < octaves; i++) {
        value += lightningNoise(p * frequency + float2(time * 0.5, 0.0), time) * amplitude;
        frequency *= 2.1;
        amplitude *= 0.45;
    }
    
    return value;
}

// 闪电主干生成
static inline float lightningBolt(float2 uv, float2 start, float2 end, float thickness, float time, float audioValue) {
    float2 pa = uv - start;
    float2 ba = end - start;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    
    float2 closestPoint = start + ba * h;
    float dist = length(uv - closestPoint);
    
    // 添加扰动
    float perturbation = fbmLightning(closestPoint * 10.0, time * 5.0, 3) * 0.03;
    dist += perturbation * audioValue;
    
    // 主干亮度
    float bolt = exp(-dist / thickness * 30.0);
    
    // 增强音频响应
    bolt *= (1.0 + audioValue * 1.5);
    
    return bolt;
}

// 闪电分支生成
static inline float lightningBranches(float2 uv, float time, float audioValue, float density) {
    float branches = 0.0;
    
    // 多个分支方向
    for (int i = 0; i < 8; i++) {
        float angle = float(i) * 0.785398; // 45度间隔
        float branchPhase = sin(time * 2.0 + float(i)) * 0.5 + 0.5;
        
        if (branchPhase > (1.0 - density)) {
            float2 dir = float2(cos(angle), sin(angle));
            float2 start = float2(0.5, 0.5);
            float2 end = start + dir * (0.2 + audioValue * 0.15);
            
            branches += lightningBolt(uv, start, end, 0.008, time + float(i), audioValue) * 0.6;
        }
    }
    
    return branches;
}

// 电弧效果
static inline float electricArc(float2 uv, float time, float audioValue) {
    float2 center = float2(0.5, 0.5);
    float dist = length(uv - center);
    float angle = atan2(uv.y - center.y, uv.x - center.x);
    
    // 圆形电弧
    float arcRadius = 0.25 + audioValue * 0.1;
    float arcDist = abs(dist - arcRadius);
    
    // 电弧闪烁
    float arcPattern = sin(angle * 12.0 - time * 8.0) * 0.5 + 0.5;
    arcPattern = smoothstep(0.6, 0.8, arcPattern);
    
    float arc = exp(-arcDist * 60.0) * arcPattern;
    arc *= (0.5 + audioValue * 0.8);
    
    return arc;
}

// 辉光效果
static inline float glow(float intensity, float radius) {
    return intensity * (1.0 + radius * 2.0);
}

#pragma mark - 主片段着色器

fragment float4 lightning_fragment(RasterizerData in [[stage_in]],
                                   constant Uniforms& uniforms [[buffer(0)]]) {
    // 宽高比校正
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float time = uniforms.time.x;
    
    float2 center = float2(0.5, 0.5);
    float2 diff = uv - center;
    float radius = length(diff);
    float angle = atan2(diff.y, diff.x);
    
    // ===== 音频数据处理 =====
    float normalizedAngle = (angle + M_PI_F) / (2.0 * M_PI_F);
    int spectrumIndex = int(normalizedAngle * 79.0);
    float audioValue = uniforms.audioData[spectrumIndex].x;
    
    // 频段分析
    float bassEnergy = 0.0;
    float midEnergy = 0.0;
    float trebleEnergy = 0.0;
    
    for (int i = 0; i < 10; i++) {
        bassEnergy += uniforms.audioData[i].x;
    }
    for (int i = 10; i < 40; i++) {
        midEnergy += uniforms.audioData[i].x;
    }
    for (int i = 40; i < 79; i++) {
        trebleEnergy += uniforms.audioData[i].x;
    }
    
    bassEnergy /= 10.0;
    midEnergy /= 30.0;
    trebleEnergy /= 39.0;
    
    float totalEnergy = (bassEnergy + midEnergy + trebleEnergy) / 3.0;
    
    // ===== 🔥 高潮检测系统（多维度音乐响应 - 闪电特化版）=====
    // 1. 综合能量响应（大幅提升，让闪电更容易触发）
    float totalEnergyResponse = totalEnergy * 3.0;
    
    // 2. 低音响应（降低阈值，提高响应系数 - 闪电主要由低音驱动）
    float bassResponse = smoothstep(0.05, 0.25, bassEnergy) * 2.0; // 降低阈值到0.05
    
    // 3. 中音响应
    float midResponse = smoothstep(0.06, 0.3, midEnergy) * 1.5;
    
    // 4. 高音响应（闪电枝干）
    float trebleResponse = smoothstep(0.06, 0.3, trebleEnergy) * 1.8;
    
    // 5. 峰值响应
    float peakValue = max(max(bassEnergy, midEnergy), trebleEnergy);
    float peakResponse = smoothstep(0.08, 0.35, peakValue) * 2.0;
    
    // 6. 综合响应强度
    float responseA = totalEnergyResponse;
    float responseB = max(max(bassResponse, midResponse), trebleResponse) * 1.5;
    float responseC = (bassResponse + midResponse + trebleResponse) / 2.5;
    float responseD = peakResponse * 1.3;
    
    // 最终音乐强度
    float musicIntensity = max(max(responseA, responseB), max(responseC, responseD));
    
    // 轻微提升低值（让安静时也有基础效果）
    if (musicIntensity < 0.2) {
        musicIntensity = musicIntensity * 0.8 + 0.1;
    }
    
    // 非线性压缩高值
    if (musicIntensity > 1.0) {
        float excess = musicIntensity - 1.0;
        musicIntensity = 1.0 + sqrt(excess) * 0.6;
    }
    
    // 最终限制
    musicIntensity = clamp(musicIntensity, 0.1, 2.0); // 提高上限到2.0
    
    // ===== 低频主闪电触发（降低阈值）=====
    float bassThreshold = smoothstep(0.05, 0.25, bassEnergy); // 大幅降低阈值
    float lightningTrigger = bassThreshold * (sin(time * 10.0 + bassEnergy * 20.0) * 0.5 + 0.5);
    
    // ===== 背景层：暗色电离层（简化）=====
    float2 bgUV = uv * 3.0 + float2(time * 0.05, time * 0.03);
    float background = fbmLightning(bgUV, time, 3) * 0.3; // 减少迭代，增加亮度
    
    // 径向渐变
    float bgGradient = 1.0 - smoothstep(0.0, 0.7, radius);
    background *= bgGradient;
    
    // ===== 主闪电层：分形闪电（大幅降低阈值）=====
    float mainLightning = 0.0;
    
    // 分形噪声基础（减少迭代）
    float2 lightningUV = uv * 12.0 + float2(time * 1.5, 0.0); // 降低频率
    float n = fbmLightning(lightningUV, time, 3); // 减少迭代到3次
    
    // 音频增强（使用musicIntensity）
    float audioBoost = musicIntensity * 0.8 + bassResponse * 0.5;
    
    // 闪电阈值（大幅降低基础阈值，从0.82降到0.45）
    float threshold = 0.45 - audioBoost * 0.25; // 音频响应时阈值可降到0.2
    threshold = max(threshold, 0.2); // 最低阈值0.2
    mainLightning = smoothstep(threshold, threshold + 0.2, n);
    
    // 闪电强度（使用musicIntensity）
    mainLightning *= (0.8 + musicIntensity * 1.5);
    
    // 时间闪烁（模拟闪电瞬间）- 简化计算
    float flicker = sin(time * 25.0 + n * 8.0) * 0.25 + 0.75;
    flicker *= (0.7 + bassThreshold * 0.3);
    mainLightning *= flicker;
    
    // ===== 主闪电脉冲（降低触发阈值，使用musicIntensity）=====
    float centralBolt = 0.0;
    
    // 大幅降低触发阈值，让闪电更容易出现
    if (bassEnergy > 0.06 || musicIntensity > 0.3) { // 从0.12降到0.06
        // 中心向外的主闪电
        float2 boltStart = float2(0.5, 0.3);
        float2 boltEnd = float2(0.5, 0.7);
        
        // 音频控制长度和位置（使用musicIntensity增强）
        boltEnd.y = 0.7 + musicIntensity * 0.15;
        boltEnd.x = 0.5 + sin(time * 5.0) * 0.08;
        
        float boltStrength = max(bassEnergy, musicIntensity * 0.6);
        centralBolt = lightningBolt(uv, boltStart, boltEnd, 0.015, time, boltStrength);
        
        // 简化侧向闪电（只在高能量时出现）
        if (musicIntensity > 0.5) {
            float2 sideBolt1 = boltStart + float2(-0.15, 0.08);
            float2 sideBolt2 = boltEnd + float2(-0.12, 0.0);
            centralBolt += lightningBolt(uv, sideBolt1, sideBolt2, 0.008, time + 1.0, boltStrength * 0.6);
            
            float2 sideBolt3 = boltStart + float2(0.15, 0.08);
            float2 sideBolt4 = boltEnd + float2(0.12, 0.0);
            centralBolt += lightningBolt(uv, sideBolt3, sideBolt4, 0.008, time + 2.0, boltStrength * 0.6);
        }
    }
    
    // ===== 闪电枝干（高频跳动 - 使用trebleResponse）=====
    float branchDensity = trebleResponse * 0.8 + musicIntensity * 0.3;
    float branches = lightningBranches(uv, time, trebleEnergy, branchDensity);
    
    // ===== 电弧环（中频律动 - 使用midResponse）=====
    float arc = electricArc(uv, time, midEnergy) * (0.6 + midResponse * 0.8);
    
    // ===== 短暂的高亮闪烁光束（减少数量，优化性能）=====
    float beamFlash = 0.0;
    
    // 减少光束数量到3个，只在高能量时计算
    if (musicIntensity > 0.4) {
        for (int i = 0; i < 3; i++) { // 从6减到3
            float beamTime = fract(time * 0.6 + float(i) * 0.333);
            float beamTrigger = smoothstep(0.92, 1.0, beamTime) * smoothstep(0.08, 0.0, beamTime);
            
            if (beamTrigger > 0.01) {
                float beamAngle = float(i) * 2.094 + time; // 120度间隔
                float2 beamDir = float2(cos(beamAngle), sin(beamAngle));
                float2 beamStart = center;
                float2 beamEnd = center + beamDir * (0.35 + musicIntensity * 0.1);
                
                float beam = lightningBolt(uv, beamStart, beamEnd, 0.01, time * 8.0, musicIntensity);
                beamFlash += beam * beamTrigger * (1.2 + musicIntensity * 0.8);
            }
        }
    }
    
    // ===== 细密的闪电网格（简化，降低计算复杂度）=====
    float lightningGrid = 0.0;
    
    // 只在中高能量时显示网格
    if (musicIntensity > 0.3) {
        float2 gridUV = uv * 20.0 + float2(time * 1.2, time * 0.8); // 降低密度
        float gridNoise = fbmLightning(gridUV, time * 1.5, 2); // 减少迭代到2次
        
        // 创建网格线条
        float gridX = abs(fract(gridUV.x) - 0.5);
        float gridY = abs(fract(gridUV.y) - 0.5);
        float grid = min(gridX, gridY);
        
        // 音频控制网格可见度（降低阈值）
        float gridThreshold = 0.35 - musicIntensity * 0.15;
        lightningGrid = smoothstep(gridThreshold, gridThreshold + 0.08, gridNoise) * exp(-grid * 80.0);
        lightningGrid *= musicIntensity * 0.6;
    }
    
    // ===== 雷暴能量核心（使用musicIntensity）=====
    float core = 0.0;
    float coreDist = radius;
    
    // 核心脉冲（使用musicIntensity和bassResponse）
    float corePulse = sin(time * 6.0 + musicIntensity * 12.0) * 0.25 + 0.75;
    corePulse *= (0.5 + bassResponse * 0.8);
    
    core = exp(-coreDist * coreDist * 10.0) * corePulse;
    core *= (0.8 + musicIntensity * 1.5); // 提升基础亮度
    
    // ===== 闪电颜色系统 =====
    // 主色：明亮的青白色（主闪电）
    float3 mainColor = float3(0.3, 0.7, 1.0);
    
    // 次色：电蓝色（分支和电弧）
    float3 secondaryColor = float3(0.2, 0.5, 0.9);
    
    // 强调色：紫电（高频部分）
    float3 accentColor = float3(0.6, 0.4, 1.0);
    
    // 核心色：纯白高亮
    float3 coreColor = float3(1.0, 1.0, 1.0);
    
    // 背景色：深紫蓝
    float3 bgColor = float3(0.05, 0.08, 0.15);
    
    // ===== 组合所有层 =====
    // 背景电离层
    float3 finalColor = bgColor * (1.0 + background * 2.0);
    
    // 主闪电（分形）
    float3 lightningColor = mix(mainColor, coreColor, mainLightning * 0.5);
    finalColor += lightningColor * mainLightning * 2.5;
    
    // 主闪电脉冲（低频）
    finalColor += mainColor * centralBolt * 3.0;
    
    // 闪电枝干（高频）
    finalColor += mix(secondaryColor, accentColor, trebleEnergy) * branches * 2.0;
    
    // 电弧环（中频）
    finalColor += secondaryColor * arc * 1.5;
    
    // 短暂闪烁光束
    finalColor += coreColor * beamFlash * 2.5;
    
    // 闪电网格
    finalColor += mainColor * lightningGrid * 1.2;
    
    // 能量核心
    finalColor += coreColor * core * 2.0;
    
    // ===== 辉光增强 =====
    float glowAmount = (mainLightning + centralBolt + branches + arc + beamFlash) * 0.3;
    float3 glowColor = mix(mainColor, coreColor, glowAmount);
    finalColor += glowColor * glow(glowAmount, radius) * 0.4;
    
    // ===== 模糊发光效果 =====
    // 为所有闪电元素添加柔和发光
    float blurGlow = (mainLightning + centralBolt + branches + arc) * 0.25;
    float blurRadius = smoothstep(0.0, 0.5, radius);
    finalColor += mainColor * blurGlow * (1.0 - blurRadius) * 0.6;
    
    // ===== 闪烁强度调制（降低阈值，使用musicIntensity）=====
    // 全局闪烁（模拟雷暴瞬间）
    float globalFlicker = 0.9; // 降低基础值，增加对比度
    
    // 强烈的低频脉冲闪烁（大幅降低阈值）
    if (bassEnergy > 0.06 || bassResponse > 0.3) { // 从0.15降到0.06
        globalFlicker += sin(time * 20.0 + bassEnergy * 40.0) * bassResponse * 0.5; // 使用bassResponse
    }
    
    // 高频细微闪烁（降低阈值）
    if (trebleEnergy > 0.05 || trebleResponse > 0.2) {
        globalFlicker += sin(time * 50.0 + trebleEnergy * 80.0) * trebleResponse * 0.2; // 使用trebleResponse
    }
    
    // 音乐强度闪烁（整体律动）
    globalFlicker += sin(time * 12.0 + musicIntensity * 15.0) * musicIntensity * 0.15;
    
    finalColor *= globalFlicker;
    
    // ===== 色彩增强（使用musicIntensity）=====
    // 根据音频强度调整色彩
    float colorShift = musicIntensity * 0.25;
    finalColor.r += colorShift * 0.12;
    finalColor.b += colorShift * 0.18;
    
    // ===== 亮度控制（提高上限）=====
    float intensity = length(finalColor);
    if (intensity > 2.5) { // 从2.0提高到2.5
        finalColor *= 2.5 / intensity;
    }
    
    // 提升对比度（增强）
    finalColor = pow(finalColor, float3(0.92)); // 从0.95降到0.92，增强对比度
    
    // ===== 边缘淡化 =====
    float edgeFade = smoothstep(0.65, 0.35, radius);
    finalColor *= edgeFade;
    
    // ===== 透明度（提升可见度）=====
    float alpha = mainLightning + centralBolt + branches + arc + beamFlash + lightningGrid + core + background * 0.6;
    
    // 添加基础可见度（即使没有音频也有微弱效果）
    alpha += 0.1;
    
    alpha *= edgeFade;
    alpha = clamp(alpha * 1.0, 0.0, 0.98); // 从0.8提高到1.0，提高上限到0.98
    
    // 最终颜色限制
    finalColor = clamp(finalColor, 0.0, 1.0);
    
    return float4(finalColor, alpha);
}

