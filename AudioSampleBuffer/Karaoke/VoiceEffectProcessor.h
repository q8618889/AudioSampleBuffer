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
    // ❌ 已移除人声升降调（改用背景音乐升降调功能）
    // VoiceEffectTypePitchUp/Down - 请使用 player.pitchShift 调整背景音乐
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

// 🆕 自动增益控制（AGC）参数
@property (nonatomic, assign) BOOL enableAGC;             // 启用AGC
@property (nonatomic, assign) float agcStrength;          // AGC强度 (0.0=弱, 0.5=中, 1.0=强)

// 🆕 SpeexDSP 高级音频处理
@property (nonatomic, assign) BOOL useSpeexDSP;           // 使用 SpeexDSP (更专业的AGC和降噪)
@property (nonatomic, assign) BOOL enableSpeexAGC;        // 启用 SpeexDSP AGC (替代简单AGC)
@property (nonatomic, assign) BOOL enableSpeexDenoise;    // 启用 SpeexDSP 降噪 (补充 RNNoise)
@property (nonatomic, assign) BOOL enableVAD;             // 启用语音活动检测 (VAD)
@property (nonatomic, assign) BOOL enableEchoCancellation; // 启用回声消除 (AEC)

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

/**
 * 🆕 设置自动增益控制（AGC）
 * @param enabled 是否启用AGC
 * @param strength AGC强度 (0.0=弱, 0.5=中, 1.0=强)
 */
- (void)setAGCEnabled:(BOOL)enabled strength:(float)strength;

/**
 * 🆕 获取当前AGC增益值（用于UI显示）
 * @return 当前应用的增益倍数
 */
- (float)getCurrentAGCGain;

#pragma mark - SpeexDSP 配置方法

/**
 * 🆕 配置 SpeexDSP 预处理器
 * @param enabled 是否启用 SpeexDSP
 * @param agc 启用自动增益控制
 * @param denoise 启用降噪
 * @param vad 启用语音活动检测
 */
- (void)configureSpeexDSP:(BOOL)enabled 
                       agc:(BOOL)agc 
                   denoise:(BOOL)denoise 
                       vad:(BOOL)vad;

/**
 * 🆕 设置 SpeexDSP AGC 参数
 * @param level 目标电平 (推荐: 8000-24000)
 * @param maxGain 最大增益 (dB, 推荐: 10-30)
 */
- (void)setSpeexAGCLevel:(int)level maxGain:(int)maxGain;

/**
 * 🆕 设置 SpeexDSP 降噪级别
 * @param level 降噪级别 (dB, -30 to 0, 推荐: -15)
 */
- (void)setSpeexDenoiseLevel:(int)level;

/**
 * 🆕 启用回声消除 (需要提供 BGM 参考信号)
 * @param enabled 是否启用
 * @param filterLength 滤波器长度 (ms, 推荐: 200-400)
 */
- (void)setEchoCancellation:(BOOL)enabled filterLength:(int)filterLength;

/**
 * 🆕 处理音频帧（带回声消除）
 * @param micBuffer 麦克风输入缓冲区
 * @param bgmBuffer BGM 参考缓冲区 (用于回声消除)
 * @param sampleCount 样本数量
 */
- (void)processAudioWithEcho:(SInt16 *)micBuffer 
                bgmReference:(SInt16 *)bgmBuffer 
                 sampleCount:(UInt32)sampleCount;

/**
 * 🆕 获取 VAD 状态（语音活动检测）
 * @return 当前是否检测到语音 (0=静音, 1=有声)
 */
- (int)getVADStatus;

/**
 * 🆕 获取 SpeexDSP 信息（用于调试）
 */
- (NSString *)getSpeexDSPInfo;

@end

NS_ASSUME_NONNULL_END

