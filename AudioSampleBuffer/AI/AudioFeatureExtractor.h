//
//  AudioFeatureExtractor.h
//  AudioSampleBuffer
//
//  音频特征提取器 - 从FFT频谱数据 / HPSS 拆分结果提取高级音乐特征
//

#import <Foundation/Foundation.h>
#import "../AudioSampleBuffer/RealtimeAnalyzerDSP.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 音乐段落枚举

typedef NS_ENUM(NSUInteger, MusicSegment) {
    MusicSegmentUnknown = 0,
    MusicSegmentIntro,      // 前奏
    MusicSegmentVerse,      // 主歌
    MusicSegmentChorus,     // 副歌/高潮
    MusicSegmentBridge,     // 过渡
    MusicSegmentOutro       // 尾奏
};

#pragma mark - 音频特征模型

@interface AudioFeatures : NSObject <NSCopying>

@property (nonatomic, assign) float bpm;                    // 节拍速度
@property (nonatomic, assign) float energy;                 // 整体能量 [0-1]
@property (nonatomic, assign) float bassEnergy;             // 低频能量 (20-250Hz) [0-1]
@property (nonatomic, assign) float midEnergy;              // 中频能量 (250-4kHz) [0-1]
@property (nonatomic, assign) float highEnergy;             // 高频能量 (4k-20kHz) [0-1]
@property (nonatomic, assign) float spectralCentroid;       // 频谱重心（亮度指标）[0-1]
@property (nonatomic, assign) float spectralFlux;           // 频谱变化率（节奏强度）[0-1]
@property (nonatomic, assign) MusicSegment currentSegment;  // 当前段落
@property (nonatomic, assign) BOOL beatDetected;            // 当前帧是否检测到节拍
@property (nonatomic, assign) BOOL segmentChanged;          // 段落是否刚发生变化
@property (nonatomic, assign) NSTimeInterval timestamp;     // 时间戳

#pragma mark - HPSS 4 类特征 (Sub-Bass / Transient / Harmonic / Noise/FX)

/// Sub-Bass + Bass 能量 (20–120 Hz, 来自 HPSS 谐波分量) [0-1]
@property (nonatomic, assign) float subBassEnergy;
/// 仅 20–60 Hz 部分（重低音核心）[0-1]
@property (nonatomic, assign) float subOnlyEnergy;
/// SuperFlux 瞬态强度，来自 HPSS 瞬态分量 [0-1]
@property (nonatomic, assign) float transientStrength;
/// 谐波分量总能量 [0-1]
@property (nonatomic, assign) float harmonicStrength;
/// 谐波峰均比，越大越偏向"线条状"的纯音 [0-1, 已归一化]
@property (nonatomic, assign) float harmonicPeakRatio;
/// HPSS 残差分量能量 (噪声/FX) [0-1]
@property (nonatomic, assign) float noiseStrength;
/// Wiener 谱平坦度 (0=纯谐波, 1=白噪声)
@property (nonatomic, assign) float spectralFlatness;

/// 子类化的 hit 标志（自适应阈值触发）
@property (nonatomic, assign) BOOL subBassHit;        // 重低音 onset (kick)
@property (nonatomic, assign) BOOL transientHit;      // 瞬态 onset (snare/hihat/pluck)
@property (nonatomic, assign) BOOL noiseFXActive;     // 持续 noise burst (riser/sweep/wash)

#pragma mark - EDM Effect Detection Outputs

@property (nonatomic, assign) BOOL stutterDetected;
@property (nonatomic, assign) BOOL gateDetected;
@property (nonatomic, assign) BOOL tremoloDetected;
@property (nonatomic, assign) BOOL sidechainDetected;
@property (nonatomic, assign) BOOL filterSweepDetected;
@property (nonatomic, assign) BOOL autoPanDetected;
@property (nonatomic, assign) BOOL delayDetected;
@property (nonatomic, assign) BOOL distortionDetected; // weak-detect

@property (nonatomic, assign) float stutterConfidence;     // 0..1
@property (nonatomic, assign) float gateConfidence;        // 0..1
@property (nonatomic, assign) float tremoloConfidence;     // 0..1
@property (nonatomic, assign) float sidechainConfidence;   // 0..1
@property (nonatomic, assign) float filterSweepConfidence; // 0..1
@property (nonatomic, assign) float autoPanConfidence;     // 0..1
@property (nonatomic, assign) float delayConfidence;       // 0..1
@property (nonatomic, assign) float distortionConfidence;  // 0..1

// HPSS explainability flags (true only when HPSS category path is active)
@property (nonatomic, assign) BOOL hpssExplainable;
@property (nonatomic, assign) BOOL harmonicDriven;
@property (nonatomic, assign) BOOL transientDriven;
@property (nonatomic, assign) BOOL noiseResidualDriven;

+ (instancetype)emptyFeatures;

@end

#pragma mark - 特征观察者协议

@protocol AudioFeatureObserver <NSObject>
@optional
- (void)audioFeatureExtractor:(id)extractor didUpdateFeatures:(AudioFeatures *)features;
- (void)audioFeatureExtractor:(id)extractor didDetectBeatAtTime:(NSTimeInterval)time;
- (void)audioFeatureExtractor:(id)extractor didChangeSegmentFrom:(MusicSegment)oldSegment to:(MusicSegment)newSegment;
@end

#pragma mark - 音频特征提取器

@interface AudioFeatureExtractor : NSObject

/// 单例
+ (instancetype)sharedExtractor;

/// 当前特征
@property (nonatomic, strong, readonly) AudioFeatures *currentFeatures;

/// 平均BPM（基于历史数据计算）
@property (nonatomic, assign, readonly) float averageBPM;

/// 处理频谱数据（旧路径，仅用 80-band 输入；保留向后兼容）
/// @param spectrum FFT频谱数组（通常为80个log-spaced band）
- (void)processSpectrumData:(NSArray<NSNumber *> *)spectrum;

/// 处理频谱数据（带采样率）
- (void)processSpectrumData:(NSArray<NSNumber *> *)spectrum sampleRate:(float)sampleRate;

/// 推荐路径：注入 DSP 层算好的 4 类标量特征 + 80-band 频谱。
/// @param spectrum 已平滑的 80-band 频谱（用于段落分析）
/// @param category HPSS 拆分后的 4 类原始标量特征
- (void)processSpectrumData:(NSArray<NSNumber *> *)spectrum
                  categoryFeatures:(AnalyzerCategoryFeatures)category;

/// 双声道入口（原版/HPSS都可用）：用于 Auto-Pan 检测。
- (void)processStereoSpectrumData:(NSArray<NSNumber *> *)leftSpectrum
                    rightSpectrum:(nullable NSArray<NSNumber *> *)rightSpectrum
                       sampleRate:(float)sampleRate;

/// 双声道 + HPSS 输入（高精度路径）
- (void)processStereoSpectrumData:(NSArray<NSNumber *> *)leftSpectrum
                    rightSpectrum:(nullable NSArray<NSNumber *> *)rightSpectrum
                 categoryFeatures:(AnalyzerCategoryFeatures)category;

/// 重置状态
- (void)reset;

/// 添加观察者
- (void)addObserver:(id<AudioFeatureObserver>)observer;

/// 移除观察者
- (void)removeObserver:(id<AudioFeatureObserver>)observer;

@end

NS_ASSUME_NONNULL_END
