//
//  VoiceEffectProcessor.mm
//  AudioSampleBuffer
//
//  音效处理器实现 (Objective-C++)
//

#import "VoiceEffectProcessor.h"
#import "DSP/DSPBridge.h"
#import <Accelerate/Accelerate.h>

// 混响参数
#define MAX_REVERB_DELAY 88200  // 2秒 @ 44100Hz
#define MAX_DELAY_BUFFER 44100  // 1秒 @ 44100Hz

@interface VoiceEffectProcessor ()

@property (nonatomic, assign) double sampleRate;

// 混响缓冲区（多个延迟线组成）
@property (nonatomic, assign) SInt16 *reverbBuffer1;
@property (nonatomic, assign) SInt16 *reverbBuffer2;
@property (nonatomic, assign) SInt16 *reverbBuffer3;
@property (nonatomic, assign) SInt16 *reverbBuffer4;

@property (nonatomic, assign) NSUInteger reverbPos1;
@property (nonatomic, assign) NSUInteger reverbPos2;
@property (nonatomic, assign) NSUInteger reverbPos3;
@property (nonatomic, assign) NSUInteger reverbPos4;

// 延迟缓冲区
@property (nonatomic, assign) SInt16 *delayBuffer;
@property (nonatomic, assign) NSUInteger delayPos;

// 压缩器历史峰值
@property (nonatomic, assign) float peakLevel;

// 低通/高通滤波器状态
@property (nonatomic, assign) float lowPassPrev;
@property (nonatomic, assign) float highPassPrev;
@property (nonatomic, assign) float highPassInput;

// 🆕 高级 DSP 处理器
@property (nonatomic, strong) NoiseReductionProcessor *noiseReducer;
@property (nonatomic, strong) PitchCorrectionProcessor *pitchCorrector;

// 🆕 音高处理缓冲区（堆内存，避免栈溢出）
@property (nonatomic, assign) SInt16 *pitchTempBuffer;
@property (nonatomic, assign) NSUInteger pitchBufferSize;
@property (nonatomic, assign) float *pitchFloatBuffer;  // 浮点缓冲区

// 🆕 自动增益控制（AGC）状态变量
@property (nonatomic, assign) float agcTargetLevel;      // 目标RMS电平
@property (nonatomic, assign) float agcCurrentGain;      // 当前自适应增益
@property (nonatomic, assign) float agcMaxGain;          // 最大增益限制
@property (nonatomic, assign) float agcMinGain;          // 最小增益限制
@property (nonatomic, assign) float agcAttackCoef;       // 增益上升平滑系数
@property (nonatomic, assign) float agcReleaseCoef;      // 增益下降平滑系数
@property (nonatomic, assign) float agcSmoothedRMS;      // 平滑的RMS值

@end

@implementation VoiceEffectProcessor

- (instancetype)initWithSampleRate:(double)sampleRate {
    self = [super init];
    if (self) {
        _sampleRate = sampleRate;
        
        // 分配混响缓冲区（4个不同延迟的梳状滤波器）
        _reverbBuffer1 = (SInt16 *)calloc(MAX_REVERB_DELAY, sizeof(SInt16));
        _reverbBuffer2 = (SInt16 *)calloc(MAX_REVERB_DELAY, sizeof(SInt16));
        _reverbBuffer3 = (SInt16 *)calloc(MAX_REVERB_DELAY, sizeof(SInt16));
        _reverbBuffer4 = (SInt16 *)calloc(MAX_REVERB_DELAY, sizeof(SInt16));
        
        // 分配延迟缓冲区
        _delayBuffer = (SInt16 *)calloc(MAX_DELAY_BUFFER, sizeof(SInt16));
        
        // 默认参数
        _effectType = VoiceEffectTypeNone;
        _reverbMix = 0.3;
        _delayMix = 0.0;
        _compressionRatio = 2.0;
        _bassGain = 0.0;
        _trebleGain = 0.0;
        _volumeGain = 1.5;  // 降低默认增益，防止过载
        
        _peakLevel = 0.0;
        _lowPassPrev = 0.0;
        _highPassPrev = 0.0;
        _highPassInput = 0.0;
        
        // 🆕 初始化高级 DSP 处理器
        _enableNoiseReduction = NO;
        _pitchShift = 0.0f;
        _enableAutoTune = NO;
        
        _noiseReducer = [[NoiseReductionProcessor alloc] initWithSampleRate:sampleRate];
        _pitchCorrector = [[PitchCorrectionProcessor alloc] initWithSampleRate:sampleRate channels:1];
        
        // 🆕 初始化音高处理缓冲区（堆内存）
        _pitchBufferSize = 8192;  // 初始大小
        _pitchTempBuffer = (SInt16 *)malloc(_pitchBufferSize * sizeof(SInt16));
        _pitchFloatBuffer = (float *)malloc(_pitchBufferSize * sizeof(float));
        
        // 🆕 初始化 AGC（自动增益控制）参数
        _enableAGC = NO;  // 默认关闭，让用户手动开启
        _agcStrength = 0.5f;  // 默认中等强度
        _agcCurrentGain = 1.0f;  // 初始增益为1.0
        _agcSmoothedRMS = 0.0f;
        [self updateAGCParameters];  // 根据强度更新AGC参数
        
        NSLog(@"✅ 音效处理器初始化完成 (采样率: %.0f Hz)", sampleRate);
        NSLog(@"   🔊 降噪处理器: %@", _noiseReducer ? @"已加载" : @"未加载");
        NSLog(@"   🎵 音高修正器: %@", _pitchCorrector ? @"已加载" : @"未加载");
        NSLog(@"   💾 音高缓冲区: %lu samples", (unsigned long)_pitchBufferSize);
        NSLog(@"   🎚️ AGC 状态: %@, 强度: %.1f", _enableAGC ? @"启用" : @"禁用", _agcStrength);
    }
    return self;
}

- (void)dealloc {
    if (_reverbBuffer1) free(_reverbBuffer1);
    if (_reverbBuffer2) free(_reverbBuffer2);
    if (_reverbBuffer3) free(_reverbBuffer3);
    if (_reverbBuffer4) free(_reverbBuffer4);
    if (_delayBuffer) free(_delayBuffer);
    
    // 🆕 释放音高处理缓冲区
    if (_pitchTempBuffer) free(_pitchTempBuffer);
    if (_pitchFloatBuffer) free(_pitchFloatBuffer);
}

#pragma mark - 音效处理主函数

- (void)processAudioBuffer:(SInt16 *)buffer sampleCount:(UInt32)sampleCount {
    static int debugCounter = 0;
    BOOL shouldLog = (debugCounter++ % 1000 == 0);  // 每1000次回调打印一次
    
    // 🆕 1. 降噪处理（总是优先执行，在其他音效之前）
    if (_enableNoiseReduction && _noiseReducer) {
        [_noiseReducer processInt16Samples:buffer count:sampleCount];
        if (shouldLog) {
            NSLog(@"🔇 降噪处理完成，样本数: %u", sampleCount);
        }
    }
    
    // 🆕 2. 自动增益控制（AGC，在降噪后、音效前）
    if (_enableAGC) {
        [self applyAGC:buffer sampleCount:sampleCount];
        if (shouldLog) {
            NSLog(@"🎚️ AGC 处理完成，当前增益: %.2fx, RMS: %.4f", _agcCurrentGain, _agcSmoothedRMS);
        }
    }
    
    // ❌ 已禁用人声音高修正（改为调整背景音乐）
    // 如需升降调，请使用 player.pitchShift 调整背景音乐
    if (NO && (_pitchShift != 0.0f || _enableAutoTune) && _pitchCorrector) {
        // 确保缓冲区足够大（现在输出样本数=输入样本数，不会增加）
        NSUInteger requiredSize = sampleCount * 2;  // 预留一些空间
        if (requiredSize > _pitchBufferSize) {
            // 动态扩展缓冲区
            _pitchBufferSize = requiredSize;
            _pitchTempBuffer = (SInt16 *)realloc(_pitchTempBuffer, _pitchBufferSize * sizeof(SInt16));
            _pitchFloatBuffer = (float *)realloc(_pitchFloatBuffer, _pitchBufferSize * sizeof(float));
            
            if (shouldLog) {
                NSLog(@"🔄 音高缓冲区扩展至: %lu samples", (unsigned long)_pitchBufferSize);
            }
        }
        
        // 使用堆内存处理音高修正（输出样本数=输入样本数）
        NSUInteger outputCount = [_pitchCorrector processInt16InputSamples:buffer
                                                                inputCount:sampleCount
                                                             outputSamples:_pitchTempBuffer
                                                            maxOutputCount:sampleCount * 2];
        
        // 复制处理后的数据（现在输出样本数应该等于输入）
        if (outputCount == sampleCount) {
            memcpy(buffer, _pitchTempBuffer, outputCount * sizeof(SInt16));
            
            if (shouldLog) {
                NSLog(@"🎵 音高修正完成: %.1f半音, 输入/输出: %u samples", _pitchShift, sampleCount);
            }
        } else {
            // 样本数不匹配，使用输出数据但保持原样本数
            NSUInteger copyCount = (outputCount < sampleCount) ? outputCount : sampleCount;
            memcpy(buffer, _pitchTempBuffer, copyCount * sizeof(SInt16));
            
            if (shouldLog || (outputCount != sampleCount)) {
                NSLog(@"⚠️ 音高修正样本数变化: %u → %lu (使用 %lu)", 
                      sampleCount, (unsigned long)outputCount, (unsigned long)copyCount);
            }
        }
    }
    
    if (_effectType == VoiceEffectTypeNone && _pitchShift == 0.0f && !_enableAutoTune) {
        // 无音效，只应用音量增益
        if (_volumeGain != 1.0) {
            [self applyVolumeGain:buffer sampleCount:sampleCount];
        }
        return;
    }
    
    if (shouldLog) {
        NSLog(@"🎵 [音效处理] 类型:%@, 混响:%.0f%%, 延迟:%.0f%%, 样本数:%u", 
              [VoiceEffectProcessor nameForEffectType:_effectType],
              _reverbMix * 100, _delayMix * 100, sampleCount);
    }
    
    // 1. 应用音量增益（放大输入信号）
    [self applyVolumeGain:buffer sampleCount:sampleCount];
    
    // 2. 应用压缩（防止削波并增加响度）
    if (_compressionRatio > 1.0) {
        [self applyCompression:buffer sampleCount:sampleCount];
    }
    
    // 3. 应用EQ（均衡器）
    if (_bassGain != 0.0 || _trebleGain != 0.0) {
        [self applyEQ:buffer sampleCount:sampleCount];
    }
    
    // 4. 应用混响
    if (_reverbMix > 0.0) {
        if (shouldLog) {
            NSLog(@"   ✅ 开始应用混响: %.0f%%", _reverbMix * 100);
        }
        [self applyReverb:buffer sampleCount:sampleCount];
    }
    
    // 5. 应用延迟（回声）
    if (_delayMix > 0.0) {
        if (shouldLog) {
            NSLog(@"   ✅ 开始应用延迟: %.0f%%", _delayMix * 100);
        }
        [self applyDelay:buffer sampleCount:sampleCount];
    }
}

#pragma mark - 🆕 AGC（自动增益控制）模块

/**
 * 根据AGC强度更新参数
 * 强度范围: 0.0(弱) ~ 0.5(中) ~ 1.0(强)
 */
- (void)updateAGCParameters {
    // 根据强度设置不同的参数
    if (_agcStrength <= 0.33f) {
        // 弱（0.0 - 0.33）：温和的增益调整，更自然
        _agcTargetLevel = 0.25f;     // 目标25% RMS
        _agcMaxGain = 3.0f;          // 最大3倍增益（约9.5dB）
        _agcMinGain = 0.5f;          // 最小0.5倍增益
        _agcAttackCoef = 0.98f;      // 慢速上升（约43ms @ 44100Hz）
        _agcReleaseCoef = 0.995f;    // 慢速下降（约200ms）
    } else if (_agcStrength <= 0.66f) {
        // 中（0.34 - 0.66）：平衡的增益调整
        _agcTargetLevel = 0.30f;     // 目标30% RMS
        _agcMaxGain = 5.0f;          // 最大5倍增益（约14dB）
        _agcMinGain = 0.4f;          // 最小0.4倍增益
        _agcAttackCoef = 0.96f;      // 中速上升（约25ms）
        _agcReleaseCoef = 0.992f;    // 中速下降（约125ms）
    } else {
        // 强（0.67 - 1.0）：激进的增益调整，最大化音量稳定性
        _agcTargetLevel = 0.35f;     // 目标35% RMS
        _agcMaxGain = 8.0f;          // 最大8倍增益（约18dB）
        _agcMinGain = 0.3f;          // 最小0.3倍增益
        _agcAttackCoef = 0.93f;      // 快速上升（约14ms）
        _agcReleaseCoef = 0.988f;    // 快速下降（约83ms）
    }
    
    NSLog(@"🎚️ AGC 参数更新 - 强度:%.2f, 目标:%.0f%%, 增益范围:%.1f-%.1fx",
          _agcStrength, _agcTargetLevel * 100, _agcMinGain, _agcMaxGain);
}

/**
 * AGC核心算法：自适应增益控制
 * 原理：
 * 1. 计算音频块的RMS（均方根）电平
 * 2. 与目标电平比较，计算所需增益
 * 3. 平滑调整增益（带Attack/Release时间）
 * 4. 应用增益到音频信号
 */
- (void)applyAGC:(SInt16 *)buffer sampleCount:(UInt32)sampleCount {
    // 1. 计算当前音频块的RMS电平（均方根）
    float sumSquares = 0.0f;
    for (UInt32 i = 0; i < sampleCount; i++) {
        float sample = buffer[i] / 32768.0f;
        sumSquares += sample * sample;
    }
    float currentRMS = sqrtf(sumSquares / sampleCount);
    
    // 2. 平滑RMS值（避免增益突变导致的咔嗒声）
    // 使用一阶低通滤波器
    float rmsAlpha = 0.8f;  // 平滑系数
    _agcSmoothedRMS = rmsAlpha * _agcSmoothedRMS + (1.0f - rmsAlpha) * currentRMS;
    
    // 3. 计算目标增益
    // 如果当前RMS太小（接近静音），不要过度放大（防止噪声放大）
    float minRMSThreshold = 0.001f;  // 静音阈值（约-60dB）
    float targetGain = 1.0f;
    
    if (_agcSmoothedRMS > minRMSThreshold) {
        // 计算达到目标电平所需的增益
        targetGain = _agcTargetLevel / _agcSmoothedRMS;
        
        // 限制增益范围
        targetGain = fmaxf(_agcMinGain, fminf(targetGain, _agcMaxGain));
    } else {
        // 静音段落，保持当前增益或缓慢降低
        targetGain = _agcCurrentGain * 0.95f;
        targetGain = fmaxf(_agcMinGain, targetGain);
    }
    
    // 4. 平滑增益调整（带Attack/Release特性）
    // Attack: 增益上升时的速度（快速响应音量增大）
    // Release: 增益下降时的速度（缓慢响应音量减小，避免突变）
    float gainCoef = (targetGain > _agcCurrentGain) ? _agcAttackCoef : _agcReleaseCoef;
    _agcCurrentGain = gainCoef * _agcCurrentGain + (1.0f - gainCoef) * targetGain;
    
    // 5. 应用增益到音频缓冲区
    for (UInt32 i = 0; i < sampleCount; i++) {
        // 转换为浮点数并应用增益
        float sample = (buffer[i] / 32768.0f) * _agcCurrentGain;
        
        // 软限幅（防止削波失真）
        // 使用tanh软削波，比硬削波更平滑
        if (fabsf(sample) > 0.9f) {
            sample = 0.9f * tanhf(sample / 0.9f);
        }
        
        // 最终硬限幅（安全保护）
        if (sample > 1.0f) sample = 1.0f;
        if (sample < -1.0f) sample = -1.0f;
        
        // 转回int16
        buffer[i] = (SInt16)(sample * 32767.0f);
    }
}

#pragma mark - 音效模块

// 音量增益
- (void)applyVolumeGain:(SInt16 *)buffer sampleCount:(UInt32)sampleCount {
    for (UInt32 i = 0; i < sampleCount; i++) {
        int32_t sample = (int32_t)(buffer[i] * _volumeGain);
        
        // 软削波
        if (sample > 32767) sample = 32767;
        if (sample < -32768) sample = -32768;
        
        buffer[i] = (SInt16)sample;
    }
}

// 动态压缩器（修复版 - 更强的限幅和软削波）
- (void)applyCompression:(SInt16 *)buffer sampleCount:(UInt32)sampleCount {
    float threshold = 0.4;  // 降低压缩阈值（40%）
    float attackTime = 0.001;  // 1ms攻击时间
    float releaseTime = 0.1;   // 100ms释放时间
    
    float attackCoef = expf(-1.0f / (_sampleRate * attackTime));
    float releaseCoef = expf(-1.0f / (_sampleRate * releaseTime));
    
    for (UInt32 i = 0; i < sampleCount; i++) {
        float sample = buffer[i] / 32768.0f;
        float absSample = fabsf(sample);
        
        // 峰值检测（带平滑）
        if (absSample > _peakLevel) {
            _peakLevel = attackCoef * _peakLevel + (1.0f - attackCoef) * absSample;
        } else {
            _peakLevel = releaseCoef * _peakLevel + (1.0f - releaseCoef) * absSample;
        }
        
        // 计算增益衰减
        float gain = 1.0f;
        if (_peakLevel > threshold) {
            // 超过阈值，应用压缩
            float overThreshold = _peakLevel - threshold;
            gain = 1.0f - (overThreshold / _compressionRatio);
            gain = fmaxf(gain, 0.15f);  // 提高最小增益到15%
        }
        
        // 应用增益
        float compressed = sample * gain;
        
        // 软削波（避免硬削波产生的爆音）
        if (compressed > 0.9f) {
            compressed = 0.9f + 0.1f * tanhf((compressed - 0.9f) * 10.0f);
        } else if (compressed < -0.9f) {
            compressed = -0.9f + 0.1f * tanhf((compressed + 0.9f) * 10.0f);
        }
        
        // 最终限幅
        if (compressed > 1.0f) compressed = 1.0f;
        if (compressed < -1.0f) compressed = -1.0f;
        
        buffer[i] = (SInt16)(compressed * 32767.0f);
    }
}

// EQ均衡器（增强的低通/高通滤波）- 修复版
- (void)applyEQ:(SInt16 *)buffer sampleCount:(UInt32)sampleCount {
    // 低频增强（低通滤波器增益）- 降低系数防止过载
    float bassCoef = 0.2;  // 降低滤波系数
    float bassMultiplier = powf(10.0f, _bassGain / 20.0f);  // dB转线性
    
    // 高频增强（高通滤波器增益）- 降低系数防止过载
    float trebleCoef = 0.7;  // 调整高通滤波器系数
    float trebleMultiplier = powf(10.0f, _trebleGain / 20.0f);
    
    for (UInt32 i = 0; i < sampleCount; i++) {
        float sample = buffer[i] / 32768.0f;
        
        // 低通滤波器（提取低频）
        _lowPassPrev = _lowPassPrev * (1.0f - bassCoef) + sample * bassCoef;
        float lowFreq = _lowPassPrev * (bassMultiplier - 1.0f);  // 只增强差值部分
        
        // 高通滤波器（提取高频）
        float highFreq = sample - _highPassPrev;
        _highPassPrev = _highPassPrev * (1.0f - trebleCoef) + sample * trebleCoef;
        highFreq *= (trebleMultiplier - 1.0f);  // 只增强差值部分
        
        // 重组信号 - 降低混合比例防止过载
        float output = sample + lowFreq * 0.5f + highFreq * 0.5f;  // 降低混合比例
        
        // 软削波
        if (output > 0.95f) {
            output = 0.95f + 0.05f * tanhf((output - 0.95f) * 10.0f);
        } else if (output < -0.95f) {
            output = -0.95f + 0.05f * tanhf((output + 0.95f) * 10.0f);
        }
        
        // 最终限幅
        if (output > 1.0f) output = 1.0f;
        if (output < -1.0f) output = -1.0f;
        
        buffer[i] = (SInt16)(output * 32767.0f);
    }
}

// 混响（多个梳状滤波器 + 全通滤波器） - 修复版（降低增益防止爆鸣）
- (void)applyReverb:(SInt16 *)buffer sampleCount:(UInt32)sampleCount {
    // 4个不同延迟时间的梳状滤波器（模拟房间反射）
    NSUInteger delay1 = (NSUInteger)(_sampleRate * 0.0297);  // ~29.7ms
    NSUInteger delay2 = (NSUInteger)(_sampleRate * 0.0371);  // ~37.1ms
    NSUInteger delay3 = (NSUInteger)(_sampleRate * 0.0411);  // ~41.1ms
    NSUInteger delay4 = (NSUInteger)(_sampleRate * 0.0437);  // ~43.7ms
    
    // 降低反馈系数，防止自激振荡和爆音
    float feedback = fminf(0.5f * _reverbMix, 0.6f);  // 最大0.6
    
    static int logCounter = 0;
    BOOL shouldLog = (logCounter++ % 5000 == 0);
    
    for (UInt32 i = 0; i < sampleCount; i++) {
        float input = buffer[i] / 32768.0f;
        
        // 从4个延迟线读取
        float reverb1 = _reverbBuffer1[_reverbPos1] / 32768.0f;
        float reverb2 = _reverbBuffer2[_reverbPos2] / 32768.0f;
        float reverb3 = _reverbBuffer3[_reverbPos3] / 32768.0f;
        float reverb4 = _reverbBuffer4[_reverbPos4] / 32768.0f;
        
        // 混合所有混响
        float reverbSum = (reverb1 + reverb2 + reverb3 + reverb4) * 0.25f;
        
        if (shouldLog && i == 0) {
            NSLog(@"      [混响] 输入:%.4f, 反馈:%.2f, 混响和:%.4f", input, feedback, reverbSum);
        }
        
        // 写入延迟线（输入 + 反馈），并加入低通滤波防止高频堆积
        float dampingCoef = 0.7f;  // 阻尼系数（模拟空气吸收高频）
        _reverbBuffer1[_reverbPos1] = (SInt16)((input * 0.8f + reverb1 * feedback * dampingCoef) * 32767.0f);
        _reverbBuffer2[_reverbPos2] = (SInt16)((input * 0.8f + reverb2 * feedback * dampingCoef) * 32767.0f);
        _reverbBuffer3[_reverbPos3] = (SInt16)((input * 0.8f + reverb3 * feedback * dampingCoef) * 32767.0f);
        _reverbBuffer4[_reverbPos4] = (SInt16)((input * 0.8f + reverb4 * feedback * dampingCoef) * 32767.0f);
        
        // 更新位置
        _reverbPos1 = (_reverbPos1 + 1) % delay1;
        _reverbPos2 = (_reverbPos2 + 1) % delay2;
        _reverbPos3 = (_reverbPos3 + 1) % delay3;
        _reverbPos4 = (_reverbPos4 + 1) % delay4;
        
        // 混合原始信号和混响信号 - 大幅降低增益防止爆音
        float dryGain = 1.0f - _reverbMix * 0.6f;  // 保留更多原声
        float wetGain = _reverbMix * 1.2f;  // 降低混响增益（原来是3.0）
        float output = input * dryGain + reverbSum * wetGain;
        
        if (shouldLog && i == 0) {
            NSLog(@"      干声增益:%.2f, 湿声增益:%.2f, 输出:%.4f", dryGain, wetGain, output);
        }
        
        // 软削波防止爆音
        if (output > 0.95f) {
            output = 0.95f + 0.05f * tanhf((output - 0.95f) * 10.0f);
        } else if (output < -0.95f) {
            output = -0.95f + 0.05f * tanhf((output + 0.95f) * 10.0f);
        }
        
        // 最终限幅
        if (output > 1.0f) output = 1.0f;
        if (output < -1.0f) output = -1.0f;
        
        buffer[i] = (SInt16)(output * 32767.0f);
    }
}

// 延迟（回声效果） - 修复版（降低增益防止爆鸣）
- (void)applyDelay:(SInt16 *)buffer sampleCount:(UInt32)sampleCount {
    NSUInteger delayTime = (NSUInteger)(_sampleRate * 0.25);  // 250ms延迟
    float feedback = fminf(0.45f, 0.4f + _delayMix * 0.15f);  // 动态反馈，最大0.45
    
    static int logCounter = 0;
    BOOL shouldLog = (logCounter++ % 5000 == 0);
    
    for (UInt32 i = 0; i < sampleCount; i++) {
        float input = buffer[i] / 32768.0f;
        float delayed = _delayBuffer[_delayPos] / 32768.0f;
        
        if (shouldLog && i == 0) {
            NSLog(@"      [延迟] 输入:%.4f, 延迟信号:%.4f, 反馈:%.2f", input, delayed, feedback);
        }
        
        // 写入延迟线（加入阻尼防止堆积）
        float dampedInput = input * 0.8f + delayed * feedback * 0.8f;  // 阻尼
        _delayBuffer[_delayPos] = (SInt16)(dampedInput * 32767.0f);
        _delayPos = (_delayPos + 1) % delayTime;
        
        // 混合原始信号和延迟信号 - 降低增益防止爆音
        float dryGain = 1.0f - _delayMix * 0.5f;  // 保留更多原声
        float wetGain = _delayMix * 1.0f;  // 降低延迟增益（原来是3.0）
        float output = input * dryGain + delayed * wetGain;
        
        // 软削波防止爆音
        if (output > 0.95f) {
            output = 0.95f + 0.05f * tanhf((output - 0.95f) * 10.0f);
        } else if (output < -0.95f) {
            output = -0.95f + 0.05f * tanhf((output + 0.95f) * 10.0f);
        }
        
        // 最终限幅
        if (output > 1.0f) output = 1.0f;
        if (output < -1.0f) output = -1.0f;
        
        buffer[i] = (SInt16)(output * 32767.0f);
    }
}

#pragma mark - 预设音效

- (void)setPresetEffect:(VoiceEffectType)effectType {
    _effectType = effectType;
    
    switch (effectType) {
        case VoiceEffectTypeNone:
            // 原声
            _reverbMix = 0.0;
            _delayMix = 0.0;
            _compressionRatio = 1.0;
            _bassGain = 0.0;
            _trebleGain = 0.0;
            _volumeGain = 1.5;  // 降低增益
            break;
            
        case VoiceEffectTypeStudio:
            // 录音棚（轻微混响 + 压缩）
            _reverbMix = 0.30;
            _delayMix = 0.08;
            _compressionRatio = 4.0;
            _bassGain = 1.5;    // 降低EQ增益
            _trebleGain = 2.0;  // 降低EQ增益
            _volumeGain = 1.8;  // 降低音量增益
            break;
            
        case VoiceEffectTypeConcertHall:
            // 音乐厅（中等混响）
            _reverbMix = 0.55;  // 略降低混响
            _delayMix = 0.12;   // 略降低延迟
            _compressionRatio = 3.5;
            _bassGain = 0.5;    // 降低EQ增益
            _trebleGain = 1.5;  // 降低EQ增益
            _volumeGain = 1.9;  // 降低音量增益
            break;
            
        case VoiceEffectTypeSuperReverb:
            // 超级混响（强混响 + 延迟）
            _reverbMix = 0.70;  // 降低混响强度
            _delayMix = 0.30;   // 降低延迟强度
            _compressionRatio = 3.5;
            _bassGain = 0.5;    // 降低EQ增益
            _trebleGain = 1.5;  // 降低EQ增益
            _volumeGain = 2.0;  // 降低音量增益
            break;
            
        case VoiceEffectTypeSinger:
            // 唱将（增强人声 + 轻混响）
            _reverbMix = 0.35;  // 降低混响
            _delayMix = 0.10;   // 降低延迟
            _compressionRatio = 5.0;
            _bassGain = 2.0;    // 降低EQ增益
            _trebleGain = 3.0;  // 降低EQ增益
            _volumeGain = 2.0;  // 降低音量增益
            break;
            
        case VoiceEffectTypeGodOfSong:
            // 歌神（全方位增强 - 专业级效果）
            _reverbMix = 0.60;  // 降低混响强度
            _delayMix = 0.25;   // 降低延迟
            _compressionRatio = 6.0;
            _bassGain = 2.5;    // 降低EQ增益
            _trebleGain = 3.5;  // 降低EQ增益
            _volumeGain = 2.2;  // 降低音量增益
            break;
            
        case VoiceEffectTypeEthereal:
            // 空灵（长混响 + 延迟）- 保持效果但降低增益
            _reverbMix = 0.80;  // 略降低混响
            _delayMix = 0.50;   // 略降低延迟
            _compressionRatio = 3.5;
            _bassGain = -2.0;   // 适度降低
            _trebleGain = 4.0;  // 降低高频增益
            _volumeGain = 2.2;  // 降低音量增益
            break;
            
        case VoiceEffectTypeMagnetic:
            // 磁性（低频增强）
            _reverbMix = 0.30;  // 降低混响
            _delayMix = 0.06;   // 降低延迟
            _compressionRatio = 4.0;
            _bassGain = 4.0;    // 降低低频增益（原6.0）
            _trebleGain = -1.5;
            _volumeGain = 2.0;  // 降低音量增益
            break;
            
        case VoiceEffectTypeBright:
            // 明亮（高频增强）
            _reverbMix = 0.30;  // 降低混响
            _delayMix = 0.08;   // 降低延迟
            _compressionRatio = 4.0;
            _bassGain = -1.5;
            _trebleGain = 4.0;  // 降低高频增益（原6.0）
            _volumeGain = 2.0;  // 降低音量增益
            break;
            
        // ❌ 已移除人声升降调音效
        // 如需调整伴奏音高，请使用：player.pitchShift = ±3.0f
    }
    
    NSLog(@"🎵 音效切换: %@", [VoiceEffectProcessor nameForEffectType:effectType]);
    NSLog(@"   混响: %.0f%%, 延迟: %.0f%%, 压缩: %.1f:1", 
          _reverbMix * 100, _delayMix * 100, _compressionRatio);
    NSLog(@"   低音: %.1fdB, 高音: %.1fdB, 增益: %.1fx", 
          _bassGain, _trebleGain, _volumeGain);
}

- (void)reset {
    // 清除所有缓冲区
    memset(_reverbBuffer1, 0, MAX_REVERB_DELAY * sizeof(SInt16));
    memset(_reverbBuffer2, 0, MAX_REVERB_DELAY * sizeof(SInt16));
    memset(_reverbBuffer3, 0, MAX_REVERB_DELAY * sizeof(SInt16));
    memset(_reverbBuffer4, 0, MAX_REVERB_DELAY * sizeof(SInt16));
    memset(_delayBuffer, 0, MAX_DELAY_BUFFER * sizeof(SInt16));
    
    _reverbPos1 = 0;
    _reverbPos2 = 0;
    _reverbPos3 = 0;
    _reverbPos4 = 0;
    _delayPos = 0;
    
    _peakLevel = 0.0;
    _lowPassPrev = 0.0;
    _highPassPrev = 0.0;
    _highPassInput = 0.0;
    
    // 🆕 重置高级 DSP 处理器
    [_noiseReducer reset];
    [_pitchCorrector clear];
    
    NSLog(@"🔄 音效处理器已重置");
}

#pragma mark - 工具方法

+ (NSString *)nameForEffectType:(VoiceEffectType)type {
    switch (type) {
        case VoiceEffectTypeNone: return @"原声";
        case VoiceEffectTypeStudio: return @"录音棚";
        case VoiceEffectTypeConcertHall: return @"音乐厅";
        case VoiceEffectTypeSuperReverb: return @"超级混响";
        case VoiceEffectTypeSinger: return @"唱将";
        case VoiceEffectTypeGodOfSong: return @"歌神";
        case VoiceEffectTypeEthereal: return @"空灵";
        case VoiceEffectTypeMagnetic: return @"磁性";
        case VoiceEffectTypeBright: return @"明亮";
        // ❌ 已移除升降调音效（改为调整背景音乐）
        default: return @"未知";
    }
}

#pragma mark - 🆕 高级音效控制方法

- (void)setNoiseReductionEnabled:(BOOL)enabled {
    _enableNoiseReduction = enabled;
    NSLog(@"🔇 降噪功能: %@", enabled ? @"开启" : @"关闭");
}

- (void)setPitchShiftSemitones:(float)semitones {
    _pitchShift = fmaxf(-12.0f, fminf(12.0f, semitones));
    [_pitchCorrector setPitchShift:_pitchShift];
    NSLog(@"🎵 音高偏移设置为: %.1f 半音", _pitchShift);
    
    // 如果手动设置音高，关闭 Auto-Tune
    if (_pitchShift != 0.0f) {
        _enableAutoTune = NO;
        [_pitchCorrector setAutoTuneEnabled:NO key:0 scale:0];
    }
}

- (void)setAutoTuneEnabled:(BOOL)enabled musicalKey:(NSInteger)key scale:(NSInteger)scale {
    _enableAutoTune = enabled;
    [_pitchCorrector setAutoTuneEnabled:enabled key:key scale:scale];
    
    // Auto-Tune 启用时，清除手动音高偏移
    if (enabled) {
        _pitchShift = 0.0f;
        [_pitchCorrector setPitchShift:0.0f];
    }
    
    NSLog(@"🎤 Auto-Tune %@, 调性: %ld %@", 
          enabled ? @"启用" : @"禁用", 
          (long)key, 
          scale == 0 ? @"Major" : @"Minor");
}

#pragma mark - 🆕 AGC 控制方法

- (void)setAGCEnabled:(BOOL)enabled strength:(float)strength {
    _enableAGC = enabled;
    _agcStrength = fmaxf(0.0f, fminf(1.0f, strength));  // 限制范围 [0.0, 1.0]
    
    // 更新AGC参数
    [self updateAGCParameters];
    
    // 如果启用AGC，重置增益状态
    if (enabled) {
        _agcCurrentGain = 1.0f;
        _agcSmoothedRMS = 0.0f;
    }
    
    NSLog(@"🎚️ AGC %@, 强度: %.2f (%@)", 
          enabled ? @"启用" : @"禁用",
          _agcStrength,
          _agcStrength < 0.34f ? @"弱" : (_agcStrength < 0.67f ? @"中" : @"强"));
}

- (float)getCurrentAGCGain {
    return _agcCurrentGain;
}

@end

