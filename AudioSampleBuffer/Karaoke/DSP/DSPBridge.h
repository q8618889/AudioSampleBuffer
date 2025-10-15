//
//  DSPBridge.h
//  AudioSampleBuffer
//
//  DSP 音效处理桥接层 - 统一接口
//  桥接 C/C++ 算法库到 Objective-C
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 降噪处理器

@interface NoiseReductionProcessor : NSObject

/**
 * 初始化降噪处理器
 * @param sampleRate 采样率 (通常 44100 或 48000)
 */
- (instancetype)initWithSampleRate:(double)sampleRate;

/**
 * 处理音频样本（原地处理）
 * @param samples 音频样本缓冲区 (float 格式，范围 -1.0 到 +1.0)
 * @param sampleCount 样本数量
 * @return 语音活动概率 (0.0 - 1.0)
 */
- (float)processSamples:(float *)samples count:(NSUInteger)sampleCount;

/**
 * 从 SInt16 处理并转换
 */
- (float)processInt16Samples:(SInt16 *)samples count:(NSUInteger)sampleCount;

/**
 * 重置处理器状态
 */
- (void)reset;

@end

#pragma mark - 音高修正处理器

@interface PitchCorrectionProcessor : NSObject

/**
 * 初始化音高修正处理器
 * @param sampleRate 采样率
 * @param channels 声道数 (1=单声道, 2=立体声)
 */
- (instancetype)initWithSampleRate:(double)sampleRate channels:(NSUInteger)channels;

/**
 * 设置音高偏移（半音）
 * @param semitones 半音数，范围 -12.0 到 +12.0
 *                  0 = 不变，+1 = 升高一个半音，-1 = 降低一个半音
 *                  +12 = 升高一个八度，-12 = 降低一个八度
 */
- (void)setPitchShift:(float)semitones;

/**
 * 设置速度比率（不改变音高）
 * @param rate 速度比率，1.0 = 原速
 */
- (void)setRate:(float)rate;

/**
 * 启用/禁用 Auto-Tune 模式（自动音高修正）
 * @param enabled 是否启用
 * @param key 音乐调性 (0-11: C, C#, D, D#, E, F, F#, G, G#, A, A#, B)
 * @param scale 音阶 (0=大调, 1=小调)
 */
- (void)setAutoTuneEnabled:(BOOL)enabled key:(NSInteger)key scale:(NSInteger)scale;

/**
 * 处理音频样本
 * @param inputSamples 输入样本 (float 格式)
 * @param inputCount 输入样本数（每个声道）
 * @param outputSamples 输出样本缓冲区
 * @param maxOutputCount 输出缓冲区最大容量
 * @return 实际输出的样本数
 */
- (NSUInteger)processInputSamples:(const float *)inputSamples
                       inputCount:(NSUInteger)inputCount
                    outputSamples:(float *)outputSamples
                   maxOutputCount:(NSUInteger)maxOutputCount;

/**
 * 处理 SInt16 格式样本
 */
- (NSUInteger)processInt16InputSamples:(const SInt16 *)inputSamples
                            inputCount:(NSUInteger)inputCount
                         outputSamples:(SInt16 *)outputSamples
                        maxOutputCount:(NSUInteger)maxOutputCount;

/**
 * 清空内部缓冲区
 */
- (void)clear;

/**
 * 刷新缓冲区（处理完所有待处理样本）
 */
- (void)flush;

@end

NS_ASSUME_NONNULL_END

