//
//  CyberpunkShader.metal
//  AudioSampleBuffer
//
//  赛博朋克效果着色器
//

#include "ShaderCommon.metal"

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
    
    // 根据活跃频段数量计算抑制因子（加强版）
    // 1个频段：不抑制 (1.0)
    // 2个频段：抑制35% (0.65)
    // 3个频段：抑制60% (0.4)
    float multiChannelSuppression = 1.0;
    if (activeChannels >= 2.0) {
        multiChannelSuppression = 1.0 - (activeChannels - 1.0) * 0.3; // 每增加1个频段，抑制30%
    }
    
    // 对用于视觉效果的音频数据应用抑制（调试显示不受影响）
    bassAudio *= multiChannelSuppression;
    midAudio *= multiChannelSuppression;
    trebleAudio *= multiChannelSuppression;
    
    // 🎛️ 读取赛博朋克控制参数
    float enableClimaxEffect = uniforms.cyberpunkControls.x; // 0.0=关闭, 1.0=开启
    float showDebugBars = uniforms.cyberpunkControls.y;      // 0.0=隐藏, 1.0=显示
    float enableGrid = uniforms.cyberpunkControls.z;         // 0.0=隐藏网格, 1.0=显示网格
    float backgroundMode = uniforms.cyberpunkControls.w;     // 背景模式: 0=网格, 1=纯色, 2=粒子, 3=渐变, 4=无
    
    // 🎨 读取频段特效控制参数
    float enableBassEffect = uniforms.cyberpunkFrequencyControls.x;   // 0.0=关闭, 1.0=开启（红色低音）
    float enableMidEffect = uniforms.cyberpunkFrequencyControls.y;    // 0.0=关闭, 1.0=开启（绿色中音）
    float enableTrebleEffect = uniforms.cyberpunkFrequencyControls.z; // 0.0=关闭, 1.0=开启（蓝色高音）
    
    // 🎨 读取背景参数
    float3 solidColor = float3(uniforms.cyberpunkBackgroundParams.x, 
                               uniforms.cyberpunkBackgroundParams.y, 
                               uniforms.cyberpunkBackgroundParams.z);
    float backgroundIntensity = uniforms.cyberpunkBackgroundParams.w;
    
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
    
    // 🎛️ 应用网格开关：如果关闭网格，gridLine归零
    if (enableGrid < 0.5) {
        gridLine = 0.0;
    }
    
    // ===== 🌟 高潮专属效果：全屏能量爆发（移除条件判断，始终计算）=====
    float climaxEffect = 0.0;
    
    // 移除 if 判断，让效果强度完全由 isClimax 控制
    {
        // 1. 全屏径向脉冲波（从中心爆发）
        float2 climaxCenter = float2(0.5, 0.5);
        float climaxDist = length(glitchUV - climaxCenter);
        
        // 多层冲击波（快速扩散）- 降低强度版本
        // 创建一个压缩因子：isClimax越高，压缩越多（加强压缩）
        float climaxSoftFactor = 1.0 / (1.0 + isClimax * 0.5); // 提高压缩(0.3→0.5)
        
        float wave1 = sin(climaxDist * 15.0 - time * 20.0 - totalEnergy * 30.0);
        wave1 = smoothstep(0.4, 1.0, wave1) * isClimax * 0.15 * climaxSoftFactor; // 降低(0.25→0.15)
        
        float wave2 = sin(climaxDist * 25.0 - time * 25.0 - bassAudio * 40.0);
        wave2 = smoothstep(0.5, 1.0, wave2) * isClimax * 0.13 * climaxSoftFactor; // 降低(0.22→0.13)
        
        float wave3 = sin(climaxDist * 35.0 - time * 30.0 - midAudio * 35.0);
        wave3 = smoothstep(0.6, 1.0, wave3) * isClimax * 0.11 * climaxSoftFactor; // 降低(0.18→0.11)
        
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
    
    // 🔥 高潮时的特殊配色（降低强度版本 + 多频段抑制）
    float3 climaxColor = float3(0.0);
    
    // 使用平方根软化 + 多频段抑制 + 进一步降低系数
    float climaxColorFactor = sqrt(isClimax) * 0.4 * multiChannelSuppression; // 降低(0.6→0.4)
    
    // 柔和的金色光晕（降低强度）
    float3 goldCore = float3(0.9, 0.8, 0.4) * climaxEffect * 0.22 * climaxColorFactor; // 降低(0.35→0.22)
    // 柔和的暖橙色（降低强度）
    float3 orangeGlow = float3(0.8, 0.5, 0.2) * climaxEffect * 0.15 * climaxColorFactor; // 降低(0.22→0.15)
    
    climaxColor = goldCore + orangeGlow;
    
    // 霓虹颜色增强（使用压缩后的值 + 多频段抑制 + 降低系数）
    float neonBoost = sqrt(isClimax) * 0.3 * multiChannelSuppression; // 降低(0.45→0.3)
    cyanNeon *= (1.0 + neonBoost * 0.8); // 降低增益
    magentaNeon *= (1.0 + neonBoost * 0.85);
    purpleNeon *= (1.0 + neonBoost * 0.9);
    
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
    
    // ===== 9. 音频驱动的边缘冲击波（单频段响应版本）=====
    float edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    
    // 🎯 只响应最强的单个频段（避免叠加）
    float maxAudio = max(max(bassAudio, midAudio), trebleAudio);
    
    // 边缘脉冲 - 使用最强频段
    float baseEdgeIntensity = 0.01; // 极低基础
    float edgePulse = smoothstep(0.05, 0.35, maxAudio); // 只使用最强音频
    float edgeGlow = exp(-edgeDist * 15.0) * (baseEdgeIntensity + edgePulse * 0.3);
    edgeGlow *= (0.15 + maxAudio * 0.8); // 使用最强音频，移除抑制因子
    
    // 边缘闪光效果 - 只使用最强频段触发（避免叠加）
    float maxFlashTrigger = smoothstep(0.05, 0.35, maxAudio) * 0.5;
    
    // 闪光效果（极致缩小范围，降低亮度）
    float edgeFlash = exp(-edgeDist * 25.0) * maxFlashTrigger * (0.3 + maxAudio * 0.5);
    
    // 固定深紫蓝色（不随强度变白）- 始终保持颜色
    float edgeIntensity = (edgeGlow + edgeFlash) * 0.45;
    edgeIntensity = clamp(edgeIntensity, 0.0, 1.0); // 限制强度，防止过亮
    float3 edgeColor = float3(0.4, 0.2, 0.8) * edgeIntensity; // 固定颜色 × 强度
    
    // ===== 10. RGB色差（Chromatic Aberration）===== 
    // 注：RGB色差效果已在组合阶段实现
    
    // ===== 🎨 背景模式系统 =====
    float3 backgroundColor = float3(0.0);
    
    // 根据backgroundMode选择不同的背景
    // 0 = 网格背景（默认，通过gridLine渲染）
    // 1 = 纯色背景
    // 2 = 动态粒子背景
    // 3 = 音频响应渐变背景
    // 4 = 无背景（纯透明）
    
    if (backgroundMode > 0.5 && backgroundMode < 1.5) {
        // 模式1: 纯色背景（可自定义颜色）
        backgroundColor = solidColor * backgroundIntensity * (0.3 + averageAudio * 0.4);
    } else if (backgroundMode > 1.5 && backgroundMode < 2.5) {
        // 模式2: 动态粒子背景
        float2 particleBgUV = glitchUV * 30.0 + time * 0.5;
        float particleBgNoise = fract(sin(dot(floor(particleBgUV), float2(12.9898, 78.233))) * 43758.5453);
        float particleBg = step(0.92, particleBgNoise) * (0.4 + averageAudio * 0.6);
        
        // 粒子颜色随音频变化
        backgroundColor = mix(
            float3(0.1, 0.15, 0.25),  // 深蓝色
            float3(0.3, 0.1, 0.4),    // 紫色
            sin(time * 0.5 + averageAudio * 3.0) * 0.5 + 0.5
        ) * particleBg * backgroundIntensity;
    } else if (backgroundMode > 2.5 && backgroundMode < 3.5) {
        // 模式3: 音频响应渐变背景
        float2 gradientCenter = float2(0.5, 0.5);
        float gradientDist = length(glitchUV - gradientCenter);
        
        // 从中心到边缘的渐变
        float gradientValue = smoothstep(0.0, 1.0, gradientDist);
        
        // 根据音频调制渐变
        float audioGradient = sin(gradientDist * 5.0 - time * 2.0 + averageAudio * 10.0) * 0.5 + 0.5;
        
        // 渐变颜色（从青色到紫色）
        float3 gradientColor1 = float3(0.0, 0.4, 0.6) * (1.0 + bassAudio);
        float3 gradientColor2 = float3(0.4, 0.0, 0.6) * (1.0 + trebleAudio);
        backgroundColor = mix(gradientColor1, gradientColor2, gradientValue) * audioGradient * backgroundIntensity * 0.5;
    }
    // else: 模式0（网格）或模式4（无背景）不添加额外背景色
    
    // ===== 组合所有效果 =====
    float3 finalColor = float3(0.0);
    
    // 先添加背景
    finalColor += backgroundColor;
    
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
                float3 climaxColorBar = float3(1.0, 0.9, 0.0);
                float3 bgColor = float3(0.2, 0.2, 0.2);
                finalColor = mix(bgColor, climaxColorBar, climaxBar * 0.98);
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

