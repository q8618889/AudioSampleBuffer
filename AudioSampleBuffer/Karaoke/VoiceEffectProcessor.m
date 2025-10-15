//
//  VoiceEffectProcessor.m
//  AudioSampleBuffer
//
//  音效处理器实现
//

#import "VoiceEffectProcessor.h"
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
        
        NSLog(@"✅ 音效处理器初始化完成 (采样率: %.0f Hz)", sampleRate);
    }
    return self;
}

- (void)dealloc {
    if (_reverbBuffer1) free(_reverbBuffer1);
    if (_reverbBuffer2) free(_reverbBuffer2);
    if (_reverbBuffer3) free(_reverbBuffer3);
    if (_reverbBuffer4) free(_reverbBuffer4);
    if (_delayBuffer) free(_delayBuffer);
}

#pragma mark - 音效处理主函数

- (void)processAudioBuffer:(SInt16 *)buffer sampleCount:(UInt32)sampleCount {
    static int debugCounter = 0;
    BOOL shouldLog = (debugCounter++ % 1000 == 0);  // 每1000次回调打印一次
    
    if (_effectType == VoiceEffectTypeNone) {
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
        default: return @"未知";
    }
}

@end

