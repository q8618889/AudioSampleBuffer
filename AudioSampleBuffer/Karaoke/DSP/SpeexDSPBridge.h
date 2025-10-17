//
//  SpeexDSPBridge.h
//  AudioSampleBuffer
//
//  SpeexDSP 音频处理桥接层
//  提供语音增强、AGC、降噪、回声消除等功能
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - SpeexDSP 预处理器 (AGC + 降噪 + VAD)

/**
 * SpeexDSP 预处理器
 * 
 * 功能：
 * - 自动增益控制 (AGC)
 * - 噪声抑制 (Noise Suppression)
 * - 语音活动检测 (VAD)
 * - 去混响 (Dereverb)
 */
@interface SpeexPreprocessor : NSObject

/**
 * 初始化预处理器
 * @param frameSize 每帧样本数 (推荐: 160 @ 48kHz = 3.33ms)
 * @param sampleRate 采样率 (Hz)
 */
- (instancetype)initWithFrameSize:(int)frameSize sampleRate:(int)sampleRate;

#pragma mark - 处理方法

/**
 * 处理音频帧（float 格式，原地处理）
 * @param frame 音频帧缓冲区（float 数组，长度 = frameSize）
 * @return 1 = 检测到语音, 0 = 静音
 */
- (int)processFrame:(float *)frame;

/**
 * 处理音频帧（SInt16 格式）
 * @param frame 音频帧缓冲区（SInt16 数组）
 * @return 1 = 检测到语音, 0 = 静音
 */
- (int)processInt16Frame:(SInt16 *)frame;

/**
 * 批量处理音频样本（自动分帧）
 * @param samples 音频样本（SInt16 格式）
 * @param sampleCount 样本数量
 * @return 平均语音活动概率 (0.0 - 1.0)
 */
- (float)processSamples:(SInt16 *)samples count:(NSUInteger)sampleCount;

#pragma mark - AGC (自动增益控制)

/**
 * 启用/禁用 AGC
 */
- (void)setAGCEnabled:(BOOL)enabled;

/**
 * 设置 AGC 目标电平
 * @param level 目标电平 (推荐: 8000 - 24000)
 */
- (void)setAGCLevel:(int)level;

/**
 * 设置 AGC 最大增益
 * @param maxGain 最大增益 (dB, 推荐: 10 - 30)
 */
- (void)setAGCMaxGain:(int)maxGain;

/**
 * 设置 AGC 增益调整速度
 * @param increment 增益调整增量 (dB, 默认: 12)
 */
- (void)setAGCIncrement:(int)increment;

/**
 * 设置 AGC 衰减速度
 * @param decrement 增益衰减值 (dB, 默认: -40)
 */
- (void)setAGCDecrement:(int)decrement;

#pragma mark - 噪声抑制

/**
 * 启用/禁用噪声抑制
 */
- (void)setDenoiseEnabled:(BOOL)enabled;

/**
 * 设置噪声抑制级别
 * @param suppress 抑制级别 (dB, 范围: -30 到 0, 推荐: -15)
 */
- (void)setNoiseSuppress:(int)suppress;

#pragma mark - VAD (语音活动检测)

/**
 * 启用/禁用 VAD
 */
- (void)setVADEnabled:(BOOL)enabled;

/**
 * 设置 VAD 概率阈值
 * @param prob 概率阈值 (0.0 - 1.0, 默认: 0.5)
 */
- (void)setVADProbability:(float)prob;

#pragma mark - 去混响

/**
 * 启用/禁用去混响
 */
- (void)setDereverbEnabled:(BOOL)enabled;

/**
 * 设置去混响级别
 * @param level 去混响级别 (0.0 - 1.0)
 */
- (void)setDereverbLevel:(float)level;

/**
 * 设置去混响衰减
 * @param decay 混响衰减系数 (0.0 - 1.0)
 */
- (void)setDereverbDecay:(float)decay;

#pragma mark - 实用方法

/**
 * 重置处理器状态
 */
- (void)reset;

/**
 * 获取当前配置信息
 */
- (NSString *)getConfigInfo;

@end

#pragma mark - SpeexDSP 回声消除器 (AEC)

/**
 * SpeexDSP 回声消除器
 * 
 * 用于消除扬声器/耳机回声，适合卡拉OK实时监听场景
 */
@interface SpeexEchoCanceller : NSObject

/**
 * 初始化回声消除器
 * @param frameSize 每帧样本数
 * @param filterLength 滤波器长度（ms，推荐: 200-400）
 * @param sampleRate 采样率 (Hz)
 */
- (instancetype)initWithFrameSize:(int)frameSize 
                     filterLength:(int)filterLength 
                       sampleRate:(int)sampleRate;

/**
 * 处理音频帧（回声消除）
 * @param inputFrame 输入音频帧（麦克风采集，包含回声）
 * @param echoFrame 参考音频帧（播放的背景音乐）
 * @param outputFrame 输出音频帧（消除回声后）
 */
- (void)processInputFrame:(SInt16 *)inputFrame 
                echoFrame:(SInt16 *)echoFrame 
              outputFrame:(SInt16 *)outputFrame;

/**
 * float 版本
 */
- (void)processFloatInputFrame:(float *)inputFrame 
                     echoFrame:(float *)echoFrame 
                   outputFrame:(float *)outputFrame;

/**
 * 重置消除器状态
 */
- (void)reset;

@end

#pragma mark - SpeexDSP 重采样器

/**
 * SpeexDSP 高质量重采样器
 * 
 * 提供比线性插值更好的音质
 */
@interface SpeexResampler : NSObject

/**
 * 初始化重采样器
 * @param channels 声道数 (1=单声道, 2=立体声)
 * @param inputRate 输入采样率 (Hz)
 * @param outputRate 输出采样率 (Hz)
 * @param quality 质量等级 (0-10, 推荐: 4-6)
 */
- (instancetype)initWithChannels:(int)channels 
                       inputRate:(int)inputRate 
                      outputRate:(int)outputRate 
                         quality:(int)quality;

/**
 * 重采样音频数据（SInt16 格式）
 * @param inputSamples 输入样本
 * @param inputLength 输入长度（每声道样本数）
 * @param outputSamples 输出缓冲区
 * @param maxOutputLength 输出缓冲区最大容量
 * @return 实际输出的样本数（每声道）
 */
- (int)processInt16Input:(SInt16 *)inputSamples 
             inputLength:(int)inputLength 
                  output:(SInt16 *)outputSamples 
           maxOutputLength:(int)maxOutputLength;

/**
 * 重采样音频数据（float 格式）
 */
- (int)processFloatInput:(float *)inputSamples 
             inputLength:(int)inputLength 
                  output:(float *)outputSamples 
         maxOutputLength:(int)maxOutputLength;

/**
 * 设置新的采样率比率
 */
- (void)setInputRate:(int)inputRate outputRate:(int)outputRate;

/**
 * 设置质量等级
 */
- (void)setQuality:(int)quality;

/**
 * 重置重采样器状态
 */
- (void)reset;

/**
 * 跳过样本（用于同步）
 */
- (void)skipZeros:(int)samples;

@end

NS_ASSUME_NONNULL_END
