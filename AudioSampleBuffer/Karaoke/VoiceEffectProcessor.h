//
//  VoiceEffectProcessor.h
//  AudioSampleBuffer
//
//  音效处理器 - 实现唱将、歌神、超级混响等音效
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

// 音效类型枚举
typedef NS_ENUM(NSInteger, VoiceEffectType) {
    VoiceEffectTypeNone = 0,          // 原声（无音效）
    VoiceEffectTypeStudio,            // 录音棚（轻微混响+压缩）
    VoiceEffectTypeConcertHall,       // 音乐厅（中等混响）
    VoiceEffectTypeSuperReverb,       // 超级混响（强混响）
    VoiceEffectTypeSinger,            // 唱将（增强人声+轻混响）
    VoiceEffectTypeGodOfSong,         // 歌神（全方位增强）
    VoiceEffectTypeEthereal,          // 空灵（长混响+延迟）
    VoiceEffectTypeMagnetic,          // 磁性（低频增强）
    VoiceEffectTypeBright,            // 明亮（高频增强）
    VoiceEffectTypeAutoTune,          // 🆕 自动修音（Auto-Tune）
    VoiceEffectTypePitchUp,           // 🆕 升调（+3半音）
    VoiceEffectTypePitchDown,         // 🆕 降调（-3半音）
};

@interface VoiceEffectProcessor : NSObject

// 当前音效类型
@property (nonatomic, assign) VoiceEffectType effectType;

// 音效参数（可自定义调节）
@property (nonatomic, assign) float reverbMix;      // 混响混合度 (0.0 - 1.0)
@property (nonatomic, assign) float delayMix;       // 延迟混合度 (0.0 - 1.0)
@property (nonatomic, assign) float compressionRatio; // 压缩比例 (1.0 - 10.0)
@property (nonatomic, assign) float bassGain;       // 低频增益 (-12dB to +12dB)
@property (nonatomic, assign) float trebleGain;     // 高频增益 (-12dB to +12dB)
@property (nonatomic, assign) float volumeGain;     // 整体增益 (0.0 - 3.0)

// 🆕 高级音效参数
@property (nonatomic, assign) BOOL enableNoiseReduction;  // 启用降噪
@property (nonatomic, assign) float pitchShift;           // 音高偏移（半音，-12 to +12）
@property (nonatomic, assign) BOOL enableAutoTune;        // 启用自动修音

/**
 * 创建音效处理引擎
 * @param sampleRate 采样率 (通常是 44100 Hz)
 * @return 音效处理器实例
 */
- (instancetype)initWithSampleRate:(double)sampleRate;

/**
 * 应用音效到音频缓冲区（实时处理）
 * @param buffer 音频样本缓冲区（int16格式）
 * @param sampleCount 样本数量
 */
- (void)processAudioBuffer:(SInt16 *)buffer sampleCount:(UInt32)sampleCount;

/**
 * 设置预设音效
 * @param effectType 音效类型
 */
- (void)setPresetEffect:(VoiceEffectType)effectType;

/**
 * 重置音效处理器（清除历史缓冲）
 */
- (void)reset;

/**
 * 获取音效名称
 */
+ (NSString *)nameForEffectType:(VoiceEffectType)type;

/**
 * 🆕 单独启用/禁用降噪（独立于音效类型）
 */
- (void)setNoiseReductionEnabled:(BOOL)enabled;

/**
 * 🆕 设置音高偏移（独立于音效类型）
 * @param semitones 半音数 (-12 to +12)
 */
- (void)setPitchShiftSemitones:(float)semitones;

/**
 * 🆕 启用 Auto-Tune 自动修音
 * @param enabled 是否启用
 * @param key 音乐调性 (0-11: C, C#, D, ..., B)
 * @param scale 音阶 (0=大调, 1=小调)
 */
- (void)setAutoTuneEnabled:(BOOL)enabled musicalKey:(NSInteger)key scale:(NSInteger)scale;

@end

NS_ASSUME_NONNULL_END

