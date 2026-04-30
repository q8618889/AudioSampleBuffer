//
//  AudioFeatureExtractor.m
//  AudioSampleBuffer
//

#import "AudioFeatureExtractor.h"
#import <Accelerate/Accelerate.h>
#import <QuartzCore/QuartzCore.h>

static const NSInteger kBeatHistorySize = 128;
static const NSInteger kEnergyHistorySize = 64;
static const float kBeatThresholdMultiplier = 1.4f;
static const float kEMAAlpha = 0.3f;

@implementation AudioFeatures

+ (instancetype)emptyFeatures {
    AudioFeatures *features = [[AudioFeatures alloc] init];
    features.bpm = 120.0f;
    features.energy = 0.0f;
    features.bassEnergy = 0.0f;
    features.midEnergy = 0.0f;
    features.highEnergy = 0.0f;
    features.spectralCentroid = 0.5f;
    features.spectralFlux = 0.0f;
    features.currentSegment = MusicSegmentUnknown;
    features.beatDetected = NO;
    features.segmentChanged = NO;
    features.timestamp = 0;
    features.subBassEnergy = 0.0f;
    features.subOnlyEnergy = 0.0f;
    features.transientStrength = 0.0f;
    features.harmonicStrength = 0.0f;
    features.harmonicPeakRatio = 0.0f;
    features.noiseStrength = 0.0f;
    features.spectralFlatness = 0.0f;
    features.subBassHit = NO;
    features.transientHit = NO;
    features.noiseFXActive = NO;
    features.stutterDetected = NO;
    features.gateDetected = NO;
    features.tremoloDetected = NO;
    features.sidechainDetected = NO;
    features.filterSweepDetected = NO;
    features.autoPanDetected = NO;
    features.delayDetected = NO;
    features.distortionDetected = NO;
    features.stutterConfidence = 0.0f;
    features.gateConfidence = 0.0f;
    features.tremoloConfidence = 0.0f;
    features.sidechainConfidence = 0.0f;
    features.filterSweepConfidence = 0.0f;
    features.autoPanConfidence = 0.0f;
    features.delayConfidence = 0.0f;
    features.distortionConfidence = 0.0f;
    features.hpssExplainable = NO;
    features.harmonicDriven = NO;
    features.transientDriven = NO;
    features.noiseResidualDriven = NO;
    return features;
}

- (id)copyWithZone:(NSZone *)zone {
    AudioFeatures *copy = [[AudioFeatures alloc] init];
    copy.bpm = self.bpm;
    copy.energy = self.energy;
    copy.bassEnergy = self.bassEnergy;
    copy.midEnergy = self.midEnergy;
    copy.highEnergy = self.highEnergy;
    copy.spectralCentroid = self.spectralCentroid;
    copy.spectralFlux = self.spectralFlux;
    copy.currentSegment = self.currentSegment;
    copy.beatDetected = self.beatDetected;
    copy.segmentChanged = self.segmentChanged;
    copy.timestamp = self.timestamp;
    copy.subBassEnergy = self.subBassEnergy;
    copy.subOnlyEnergy = self.subOnlyEnergy;
    copy.transientStrength = self.transientStrength;
    copy.harmonicStrength = self.harmonicStrength;
    copy.harmonicPeakRatio = self.harmonicPeakRatio;
    copy.noiseStrength = self.noiseStrength;
    copy.spectralFlatness = self.spectralFlatness;
    copy.subBassHit = self.subBassHit;
    copy.transientHit = self.transientHit;
    copy.noiseFXActive = self.noiseFXActive;
    copy.stutterDetected = self.stutterDetected;
    copy.gateDetected = self.gateDetected;
    copy.tremoloDetected = self.tremoloDetected;
    copy.sidechainDetected = self.sidechainDetected;
    copy.filterSweepDetected = self.filterSweepDetected;
    copy.autoPanDetected = self.autoPanDetected;
    copy.delayDetected = self.delayDetected;
    copy.distortionDetected = self.distortionDetected;
    copy.stutterConfidence = self.stutterConfidence;
    copy.gateConfidence = self.gateConfidence;
    copy.tremoloConfidence = self.tremoloConfidence;
    copy.sidechainConfidence = self.sidechainConfidence;
    copy.filterSweepConfidence = self.filterSweepConfidence;
    copy.autoPanConfidence = self.autoPanConfidence;
    copy.delayConfidence = self.delayConfidence;
    copy.distortionConfidence = self.distortionConfidence;
    copy.hpssExplainable = self.hpssExplainable;
    copy.harmonicDriven = self.harmonicDriven;
    copy.transientDriven = self.transientDriven;
    copy.noiseResidualDriven = self.noiseResidualDriven;
    return copy;
}

@end

@interface AudioFeatureExtractor ()

@property (nonatomic, strong) AudioFeatures *currentFeatures;
@property (nonatomic, strong) NSHashTable<id<AudioFeatureObserver>> *observers;

// 历史数据
@property (nonatomic, strong) NSMutableArray<NSNumber *> *energyHistory;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *beatTimeHistory;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *previousSpectrum;

// 节拍检测
@property (nonatomic, assign) float lastBassEnergy;
@property (nonatomic, assign) NSTimeInterval lastBeatTime;
@property (nonatomic, assign) float beatThreshold;
@property (nonatomic, assign) float averageBPM;

// 段落检测 - 增强版
@property (nonatomic, assign) float longTermEnergy;
@property (nonatomic, assign) float shortTermEnergy;
@property (nonatomic, assign) MusicSegment previousSegment;
@property (nonatomic, assign) NSTimeInterval segmentStartTime;

// 段落分析增强
@property (nonatomic, strong) NSMutableArray<NSNumber *> *energyEnvelope;      // 能量包络
@property (nonatomic, strong) NSMutableArray<NSNumber *> *spectralContrast;    // 频谱对比
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *segmentHistory;  // 段落历史
@property (nonatomic, assign) float peakEnergy;                                // 峰值能量
@property (nonatomic, assign) float energyVariance;                            // 能量方差
@property (nonatomic, assign) float averageEnergy;                             // 平均能量
@property (nonatomic, assign) NSTimeInterval estimatedDuration;                // 估计时长
@property (nonatomic, assign) BOOL introDetected;                              // 是否检测到前奏
@property (nonatomic, assign) BOOL firstChorusDetected;                        // 是否检测到第一个副歌
@property (nonatomic, assign) NSTimeInterval firstChorusTime;                  // 第一个副歌时间
@property (nonatomic, assign) NSInteger chorusCount;                           // 副歌次数
@property (nonatomic, assign) float chorusEnergyThreshold;                     // 副歌能量阈值
@property (nonatomic, assign) NSInteger stableFrameCount;                      // 稳定帧计数

// EMA滤波后的值
@property (nonatomic, assign) float smoothedEnergy;
@property (nonatomic, assign) float smoothedBassEnergy;
@property (nonatomic, assign) float smoothedMidEnergy;
@property (nonatomic, assign) float smoothedHighEnergy;

// HPSS 特征 EMA 与门限状态
@property (nonatomic, assign) float smoothedSubBass;          // 平滑过的 subBass+bass 总能量
@property (nonatomic, assign) float smoothedSubOnly;          // 平滑过的 20-60Hz 部分
@property (nonatomic, assign) float smoothedTransient;
@property (nonatomic, assign) float smoothedHarmonic;
@property (nonatomic, assign) float smoothedNoise;
@property (nonatomic, assign) float smoothedFlatness;
@property (nonatomic, assign) float smoothedHarmonicPeakRatio;

// Adaptive thresholds for sub-bass / transient hits
@property (nonatomic, strong) NSMutableArray<NSNumber *> *subBassEnvHistory;   // 32-frame ring
@property (nonatomic, strong) NSMutableArray<NSNumber *> *transientEnvHistory; // 32-frame ring
@property (nonatomic, assign) NSTimeInterval lastSubBassHitTime;
@property (nonatomic, assign) NSTimeInterval lastTransientHitTime;
@property (nonatomic, assign) NSTimeInterval lastNoiseFXTime;
@property (nonatomic, assign) BOOL hasCategoryFeatures;       // 是否使用了 HPSS 路径

// EDM effect histories
@property (nonatomic, strong) NSMutableArray<NSNumber *> *centroidHistory;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *envelopeHistory;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *onsetHistory;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *panHistory;
@property (nonatomic, assign) float latestPanValue;

// 时间
@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, assign) NSInteger frameCount;

@end

@implementation AudioFeatureExtractor

+ (instancetype)sharedExtractor {
    static AudioFeatureExtractor *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AudioFeatureExtractor alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentFeatures = [AudioFeatures emptyFeatures];
        _observers = [NSHashTable weakObjectsHashTable];
        _energyHistory = [NSMutableArray arrayWithCapacity:kEnergyHistorySize];
        _beatTimeHistory = [NSMutableArray arrayWithCapacity:kBeatHistorySize];
        _previousSpectrum = [NSMutableArray array];
        
        _lastBassEnergy = 0;
        _lastBeatTime = 0;
        _beatThreshold = 0.3f;
        _averageBPM = 120.0f;
        
        _longTermEnergy = 0;
        _shortTermEnergy = 0;
        _previousSegment = MusicSegmentUnknown;
        _segmentStartTime = 0;
        
        // 段落分析增强初始化
        _energyEnvelope = [NSMutableArray arrayWithCapacity:300];  // 约5秒数据 @60fps
        _spectralContrast = [NSMutableArray arrayWithCapacity:300];
        _segmentHistory = [NSMutableArray array];
        _peakEnergy = 0;
        _energyVariance = 0;
        _averageEnergy = 0;
        _estimatedDuration = 180.0;  // 默认3分钟
        _introDetected = NO;
        _firstChorusDetected = NO;
        _firstChorusTime = 0;
        _chorusCount = 0;
        _chorusEnergyThreshold = 0.6;
        _stableFrameCount = 0;
        
        _smoothedEnergy = 0;
        _smoothedBassEnergy = 0;
        _smoothedMidEnergy = 0;
        _smoothedHighEnergy = 0;

        _smoothedSubBass = 0;
        _smoothedSubOnly = 0;
        _smoothedTransient = 0;
        _smoothedHarmonic = 0;
        _smoothedNoise = 0;
        _smoothedFlatness = 0;
        _smoothedHarmonicPeakRatio = 0;

        _subBassEnvHistory = [NSMutableArray arrayWithCapacity:32];
        _transientEnvHistory = [NSMutableArray arrayWithCapacity:32];
        _lastSubBassHitTime = 0;
        _lastTransientHitTime = 0;
        _lastNoiseFXTime = 0;
        _hasCategoryFeatures = NO;

        _centroidHistory = [NSMutableArray arrayWithCapacity:96];
        _envelopeHistory = [NSMutableArray arrayWithCapacity:96];
        _onsetHistory = [NSMutableArray arrayWithCapacity:96];
        _panHistory = [NSMutableArray arrayWithCapacity:96];
        _latestPanValue = 0.0f;
        
        _startTime = CACurrentMediaTime();
        _frameCount = 0;
    }
    return self;
}

- (void)reset {
    self.currentFeatures = [AudioFeatures emptyFeatures];
    [self.energyHistory removeAllObjects];
    [self.beatTimeHistory removeAllObjects];
    [self.previousSpectrum removeAllObjects];
    
    self.lastBassEnergy = 0;
    self.lastBeatTime = 0;
    self.beatThreshold = 0.3f;
    self.averageBPM = 120.0f;
    
    self.longTermEnergy = 0;
    self.shortTermEnergy = 0;
    self.previousSegment = MusicSegmentUnknown;
    self.segmentStartTime = 0;
    
    // 重置增强段落分析
    [self.energyEnvelope removeAllObjects];
    [self.spectralContrast removeAllObjects];
    [self.segmentHistory removeAllObjects];
    self.peakEnergy = 0;
    self.energyVariance = 0;
    self.averageEnergy = 0;
    self.introDetected = NO;
    self.firstChorusDetected = NO;
    self.firstChorusTime = 0;
    self.chorusCount = 0;
    self.chorusEnergyThreshold = 0.6;
    self.stableFrameCount = 0;
    
    self.smoothedEnergy = 0;
    self.smoothedBassEnergy = 0;
    self.smoothedMidEnergy = 0;
    self.smoothedHighEnergy = 0;

    self.smoothedSubBass = 0;
    self.smoothedSubOnly = 0;
    self.smoothedTransient = 0;
    self.smoothedHarmonic = 0;
    self.smoothedNoise = 0;
    self.smoothedFlatness = 0;
    self.smoothedHarmonicPeakRatio = 0;
    [self.subBassEnvHistory removeAllObjects];
    [self.transientEnvHistory removeAllObjects];
    self.lastSubBassHitTime = 0;
    self.lastTransientHitTime = 0;
    self.lastNoiseFXTime = 0;
    self.hasCategoryFeatures = NO;
    [self.centroidHistory removeAllObjects];
    [self.envelopeHistory removeAllObjects];
    [self.onsetHistory removeAllObjects];
    [self.panHistory removeAllObjects];
    self.latestPanValue = 0.0f;
    
    self.startTime = CACurrentMediaTime();
    self.frameCount = 0;
}

#pragma mark - Process Spectrum

- (void)processSpectrumData:(NSArray<NSNumber *> *)spectrum {
    [self processSpectrumData:spectrum sampleRate:44100.0f];
}

- (void)processStereoSpectrumData:(NSArray<NSNumber *> *)leftSpectrum
                    rightSpectrum:(NSArray<NSNumber *> *)rightSpectrum
                       sampleRate:(float)sampleRate {
    float pan = [self computePanValueFromLeft:leftSpectrum right:rightSpectrum];
    self.latestPanValue = pan;
    [self processSpectrumData:leftSpectrum sampleRate:sampleRate];
}

- (void)processStereoSpectrumData:(NSArray<NSNumber *> *)leftSpectrum
                    rightSpectrum:(NSArray<NSNumber *> *)rightSpectrum
                 categoryFeatures:(AnalyzerCategoryFeatures)category {
    float pan = [self computePanValueFromLeft:leftSpectrum right:rightSpectrum];
    self.latestPanValue = pan;
    [self processSpectrumData:leftSpectrum categoryFeatures:category];
}

- (void)processSpectrumData:(NSArray<NSNumber *> *)spectrum sampleRate:(float)sampleRate {
    if (spectrum.count == 0) return;
    
    self.frameCount++;
    NSTimeInterval currentTime = CACurrentMediaTime() - self.startTime;
    
    AudioFeatures *features = [[AudioFeatures alloc] init];
    features.timestamp = currentTime;
    
    NSInteger spectrumSize = spectrum.count;
    float nyquist = sampleRate / 2.0f;
    float binWidth = nyquist / spectrumSize;
    
    // 频段划分（基于FFT bin索引）
    NSInteger bassEnd = (NSInteger)(250.0f / binWidth);
    NSInteger midEnd = (NSInteger)(4000.0f / binWidth);
    
    bassEnd = MIN(bassEnd, spectrumSize);
    midEnd = MIN(midEnd, spectrumSize);
    
    // 计算各频段能量
    float bassSum = 0, midSum = 0, highSum = 0, totalSum = 0;
    float weightedSum = 0;
    
    for (NSInteger i = 0; i < spectrumSize; i++) {
        float value = [spectrum[i] floatValue];
        float absValue = fabsf(value);
        totalSum += absValue;
        
        if (i < bassEnd) {
            bassSum += absValue;
        } else if (i < midEnd) {
            midSum += absValue;
        } else {
            highSum += absValue;
        }
        
        weightedSum += absValue * i;
    }
    
    // 归一化
    float bassEnergy = (bassEnd > 0) ? (bassSum / bassEnd) : 0;
    float midEnergy = (midEnd > bassEnd) ? (midSum / (midEnd - bassEnd)) : 0;
    float highEnergy = (spectrumSize > midEnd) ? (highSum / (spectrumSize - midEnd)) : 0;
    float totalEnergy = totalSum / spectrumSize;
    
    // 频谱重心（亮度指标）
    float spectralCentroid = (totalSum > 0) ? (weightedSum / totalSum / spectrumSize) : 0.5f;
    
    // 频谱变化率（与上一帧的差异）
    float spectralFlux = [self calculateSpectralFlux:spectrum];
    
    // EMA平滑
    self.smoothedEnergy = kEMAAlpha * totalEnergy + (1 - kEMAAlpha) * self.smoothedEnergy;
    self.smoothedBassEnergy = kEMAAlpha * bassEnergy + (1 - kEMAAlpha) * self.smoothedBassEnergy;
    self.smoothedMidEnergy = kEMAAlpha * midEnergy + (1 - kEMAAlpha) * self.smoothedMidEnergy;
    self.smoothedHighEnergy = kEMAAlpha * highEnergy + (1 - kEMAAlpha) * self.smoothedHighEnergy;
    
    // 限制到 [0, 1]
    features.energy = MIN(1.0f, self.smoothedEnergy * 3.0f);
    features.bassEnergy = MIN(1.0f, self.smoothedBassEnergy * 4.0f);
    features.midEnergy = MIN(1.0f, self.smoothedMidEnergy * 4.0f);
    features.highEnergy = MIN(1.0f, self.smoothedHighEnergy * 5.0f);
    features.spectralCentroid = spectralCentroid;
    features.spectralFlux = MIN(1.0f, spectralFlux * 5.0f);
    
    // 节拍检测
    features.beatDetected = [self detectBeat:bassEnergy atTime:currentTime];
    
    // BPM估算
    features.bpm = self.averageBPM;
    
    // 段落检测
    MusicSegment newSegment = [self detectSegment:features];
    features.currentSegment = newSegment;
    features.segmentChanged = (newSegment != self.previousSegment);
    
    if (features.segmentChanged) {
        [self notifySegmentChange:self.previousSegment to:newSegment];
        self.previousSegment = newSegment;
        self.segmentStartTime = currentTime;
    }
    
    // 保存当前频谱用于下一帧比较
    self.previousSpectrum = [spectrum mutableCopy];
    
    // 更新历史
    [self updateEnergyHistory:features.energy];
    
    // 更新当前特征
    [self updateEDMEffectsWithFeatures:features useHPSS:NO];
    self.currentFeatures = features;
    
    // 通知观察者
    [self notifyFeaturesUpdate:features];
    
    if (features.beatDetected) {
        [self notifyBeatDetected:currentTime];
    }
}

- (void)processSpectrumData:(NSArray<NSNumber *> *)spectrum
          categoryFeatures:(AnalyzerCategoryFeatures)category {
    if (spectrum.count == 0) return;

    self.hasCategoryFeatures = YES;
    self.frameCount++;
    NSTimeInterval currentTime = CACurrentMediaTime() - self.startTime;

    AudioFeatures *features = [[AudioFeatures alloc] init];
    features.timestamp = currentTime;

    // Keep existing broadband statistics for segment detection compatibility.
    NSInteger spectrumSize = spectrum.count;
    float bassSum = 0, midSum = 0, highSum = 0, totalSum = 0, weightedSum = 0;
    NSInteger bassEnd = MIN((NSInteger)(spectrumSize * 0.22f), spectrumSize);
    NSInteger midEnd = MIN((NSInteger)(spectrumSize * 0.62f), spectrumSize);
    for (NSInteger i = 0; i < spectrumSize; i++) {
        float absValue = fabsf([spectrum[i] floatValue]);
        totalSum += absValue;
        if (i < bassEnd) bassSum += absValue;
        else if (i < midEnd) midSum += absValue;
        else highSum += absValue;
        weightedSum += absValue * (float)i;
    }
    float bassEnergy = (bassEnd > 0) ? bassSum / bassEnd : 0.0f;
    float midEnergy = (midEnd > bassEnd) ? midSum / (midEnd - bassEnd) : 0.0f;
    float highEnergy = (spectrumSize > midEnd) ? highSum / (spectrumSize - midEnd) : 0.0f;
    float totalEnergy = (spectrumSize > 0) ? totalSum / spectrumSize : 0.0f;
    float spectralCentroid = (totalSum > 0) ? (weightedSum / totalSum / MAX(1.0f, (float)spectrumSize)) : 0.5f;

    self.smoothedEnergy = kEMAAlpha * totalEnergy + (1 - kEMAAlpha) * self.smoothedEnergy;
    self.smoothedBassEnergy = kEMAAlpha * bassEnergy + (1 - kEMAAlpha) * self.smoothedBassEnergy;
    self.smoothedMidEnergy = kEMAAlpha * midEnergy + (1 - kEMAAlpha) * self.smoothedMidEnergy;
    self.smoothedHighEnergy = kEMAAlpha * highEnergy + (1 - kEMAAlpha) * self.smoothedHighEnergy;
    features.energy = MIN(1.0f, self.smoothedEnergy * 3.0f);
    features.bassEnergy = MIN(1.0f, self.smoothedBassEnergy * 4.0f);
    features.midEnergy = MIN(1.0f, self.smoothedMidEnergy * 4.0f);
    features.highEnergy = MIN(1.0f, self.smoothedHighEnergy * 5.0f);
    features.spectralCentroid = spectralCentroid;

    // 4-category HPSS metrics
    self.smoothedSubOnly = 0.28f * category.subBass + 0.72f * self.smoothedSubOnly;
    self.smoothedSubBass = 0.28f * category.lowEnergy + 0.72f * self.smoothedSubBass;
    self.smoothedTransient = 0.24f * category.transient + 0.76f * self.smoothedTransient;
    self.smoothedHarmonic = 0.20f * category.harmonic + 0.80f * self.smoothedHarmonic;
    self.smoothedNoise = 0.20f * category.noise + 0.80f * self.smoothedNoise;
    self.smoothedFlatness = 0.18f * category.spectralFlatness + 0.82f * self.smoothedFlatness;
    self.smoothedHarmonicPeakRatio = 0.18f * category.harmonicPeakRatio + 0.82f * self.smoothedHarmonicPeakRatio;

    features.subOnlyEnergy = MIN(1.0f, self.smoothedSubOnly * 6.2f);
    features.subBassEnergy = MIN(1.0f, self.smoothedSubBass * 4.6f);
    features.transientStrength = MIN(1.0f, self.smoothedTransient * 7.2f);
    features.harmonicStrength = MIN(1.0f, self.smoothedHarmonic * 4.0f);
    features.noiseStrength = MIN(1.0f, self.smoothedNoise * 5.0f);
    features.spectralFlatness = MIN(1.0f, MAX(0.0f, self.smoothedFlatness));
    features.harmonicPeakRatio = MIN(1.0f, self.smoothedHarmonicPeakRatio / 6.0f);
    features.spectralFlux = features.transientStrength;

    [self pushAdaptiveValue:features.subBassEnergy toHistory:self.subBassEnvHistory maxLen:32];
    [self pushAdaptiveValue:features.transientStrength toHistory:self.transientEnvHistory maxLen:32];
    features.subBassHit = [self detectAdaptiveHitWithValue:features.subBassEnergy
                                                    history:self.subBassEnvHistory
                                                      floor:0.10f
                                                   sigmaMul:1.85f
                                                minInterval:0.23
                                                  lastStamp:&_lastSubBassHitTime
                                                        now:currentTime];
    features.transientHit = [self detectAdaptiveHitWithValue:features.transientStrength
                                                      history:self.transientEnvHistory
                                                        floor:0.08f
                                                     sigmaMul:1.65f
                                                  minInterval:0.08
                                                    lastStamp:&_lastTransientHitTime
                                                          now:currentTime];
    BOOL noiseGate = (features.noiseStrength > 0.30f && features.spectralFlatness > 0.40f);
    if (noiseGate) self.lastNoiseFXTime = currentTime;
    features.noiseFXActive = (currentTime - self.lastNoiseFXTime) < 0.22;

    features.beatDetected = (features.subBassHit ||
                            (features.transientHit && features.subBassEnergy > 0.10f));
    if (features.subBassHit) {
        [self.beatTimeHistory addObject:@(currentTime)];
        if (self.beatTimeHistory.count > kBeatHistorySize) {
            [self.beatTimeHistory removeObjectAtIndex:0];
        }
        [self updateBPMEstimate];
    }
    features.bpm = self.averageBPM;

    MusicSegment newSegment = [self detectSegment:features];
    features.currentSegment = newSegment;
    features.segmentChanged = (newSegment != self.previousSegment);
    if (features.segmentChanged) {
        [self notifySegmentChange:self.previousSegment to:newSegment];
        self.previousSegment = newSegment;
        self.segmentStartTime = currentTime;
    }

    self.previousSpectrum = [spectrum mutableCopy];
    [self updateEnergyHistory:features.energy];
    [self updateEDMEffectsWithFeatures:features useHPSS:YES];
    self.currentFeatures = features;
    [self notifyFeaturesUpdate:features];
    if (features.beatDetected) [self notifyBeatDetected:currentTime];
}

#pragma mark - Beat Detection

- (BOOL)detectBeat:(float)bassEnergy atTime:(NSTimeInterval)currentTime {
    // 动态阈值：基于历史能量平均值
    float threshold = self.beatThreshold * kBeatThresholdMultiplier;
    
    // 检测低频能量突增
    BOOL energySpike = (bassEnergy > self.lastBassEnergy * 1.5f) && (bassEnergy > threshold);
    
    // 最小间隔（避免重复检测，假设最快200 BPM = 300ms间隔）
    BOOL minIntervalPassed = (currentTime - self.lastBeatTime) > 0.25;
    
    self.lastBassEnergy = bassEnergy;
    
    if (energySpike && minIntervalPassed) {
        // 记录节拍时间
        [self.beatTimeHistory addObject:@(currentTime)];
        if (self.beatTimeHistory.count > kBeatHistorySize) {
            [self.beatTimeHistory removeObjectAtIndex:0];
        }
        
        // 计算BPM
        [self updateBPMEstimate];
        
        // 更新动态阈值
        [self updateBeatThreshold:bassEnergy];
        
        self.lastBeatTime = currentTime;
        return YES;
    }
    
    return NO;
}

- (void)updateBPMEstimate {
    if (self.beatTimeHistory.count < 4) return;
    
    // 计算节拍间隔
    NSMutableArray<NSNumber *> *intervals = [NSMutableArray array];
    for (NSInteger i = 1; i < self.beatTimeHistory.count; i++) {
        float interval = [self.beatTimeHistory[i] floatValue] - [self.beatTimeHistory[i-1] floatValue];
        if (interval > 0.2 && interval < 2.0) { // 30-300 BPM范围
            [intervals addObject:@(interval)];
        }
    }
    
    if (intervals.count == 0) return;
    
    // 计算平均间隔
    float sum = 0;
    for (NSNumber *interval in intervals) {
        sum += interval.floatValue;
    }
    float avgInterval = sum / intervals.count;
    
    // 转换为BPM
    float bpm = 60.0f / avgInterval;
    
    // 限制到合理范围
    bpm = MAX(60.0f, MIN(200.0f, bpm));
    
    // 平滑更新
    self.averageBPM = 0.1f * bpm + 0.9f * self.averageBPM;
}

- (void)updateBeatThreshold:(float)currentEnergy {
    // 自适应阈值
    self.beatThreshold = 0.8f * self.beatThreshold + 0.2f * currentEnergy * 0.7f;
    self.beatThreshold = MAX(0.1f, MIN(0.5f, self.beatThreshold));
}

#pragma mark - Spectral Flux

- (float)calculateSpectralFlux:(NSArray<NSNumber *> *)spectrum {
    if (self.previousSpectrum.count == 0 || self.previousSpectrum.count != spectrum.count) {
        return 0;
    }
    
    float flux = 0;
    for (NSInteger i = 0; i < spectrum.count; i++) {
        float diff = [spectrum[i] floatValue] - [self.previousSpectrum[i] floatValue];
        if (diff > 0) {
            flux += diff * diff;
        }
    }
    
    return sqrtf(flux / spectrum.count);
}

#pragma mark - Segment Detection

- (MusicSegment)detectSegment:(AudioFeatures *)features {
    NSTimeInterval currentTime = features.timestamp;
    NSTimeInterval timeSinceStart = currentTime - self.startTime;
    NSTimeInterval timeSinceSegmentStart = currentTime - self.segmentStartTime;
    
    // === 参数配置 ===
    static const NSTimeInterval kMinSegmentDuration = 6.0;   // 段落至少6秒
    static const NSTimeInterval kMinChorusDuration = 8.0;    // 副歌至少8秒
    static const NSInteger kMaxChorusCount = 5;              // 一首歌最多5个副歌
    
    // 更新能量统计 (每帧都更新)
    float alphaLong = 0.008f;
    float alphaShort = 0.1f;
    
    self.longTermEnergy = alphaLong * features.energy + (1 - alphaLong) * self.longTermEnergy;
    self.shortTermEnergy = alphaShort * features.energy + (1 - alphaShort) * self.shortTermEnergy;
    
    // 更新能量包络历史
    [self.energyEnvelope addObject:@(features.energy)];
    if (self.energyEnvelope.count > 300) {
        [self.energyEnvelope removeObjectAtIndex:0];
    }
    
    // 更新频谱对比历史
    float contrast = features.highEnergy - features.bassEnergy;
    [self.spectralContrast addObject:@(contrast)];
    if (self.spectralContrast.count > 300) {
        [self.spectralContrast removeObjectAtIndex:0];
    }
    
    // 计算统计量
    [self updateSegmentStatistics:features];
    
    // === 防抖动：前几秒不切换 ===
    if (timeSinceSegmentStart < kMinSegmentDuration && self.previousSegment != MusicSegmentUnknown) {
        return self.previousSegment;
    }
    
    // === 检测音乐类型 ===
    BOOL isLowEnergyMusic = (self.peakEnergy < 0.35);
    BOOL isVeryLowEnergyMusic = (self.peakEnergy < 0.2);
    
    // === 智能段落检测 ===
    
    // 1. 前奏检测 (开头8-20秒)
    if (!self.introDetected) {
        if (timeSinceStart < 8.0) {
            return MusicSegmentIntro;
        }
        if (timeSinceStart < 20.0) {
            // 能量还在上升阶段
            float energyRatio = (self.averageEnergy > 0.01) ? 
                (features.energy / self.averageEnergy) : 1.0;
            if (energyRatio < 1.15) {
                return MusicSegmentIntro;
            }
        }
        self.introDetected = YES;
    }
    
    // 2. 尾奏检测
    if (timeSinceStart > 120.0) {
        float recentEnergyTrend = [self calculateRecentEnergyTrend];
        if (recentEnergyTrend < -0.01 && 
            self.shortTermEnergy < self.averageEnergy * 0.7) {
            self.stableFrameCount++;
            if (self.stableFrameCount > 90) {
                return MusicSegmentOutro;
            }
        } else {
            self.stableFrameCount = 0;
        }
    }
    
    // 3. 计算副歌评分
    float energyRatio = (self.averageEnergy > 0.005) ? 
        (features.energy / self.averageEnergy) : 1.0;
    float shortLongRatio = (self.longTermEnergy > 0.005) ?
        (self.shortTermEnergy / self.longTermEnergy) : 1.0;
    
    float chorusScore = 0;
    
    if (isVeryLowEnergyMusic) {
        // 非常低能量音乐（如氛围音乐）：主要看相对变化
        if (energyRatio > 1.15) chorusScore += 0.4;
        if (shortLongRatio > 1.1) chorusScore += 0.3;
        if (features.spectralFlux > 0.1) chorusScore += 0.3;
    } else if (isLowEnergyMusic) {
        // 低能量音乐：混合策略
        if (energyRatio > 1.2) chorusScore += 0.35;
        if (shortLongRatio > 1.15) chorusScore += 0.25;
        if (features.spectralFlux > 0.15) chorusScore += 0.2;
        if (features.bassEnergy > self.averageEnergy) chorusScore += 0.2;
    } else {
        // 正常/高能量音乐
        if (features.energy > self.chorusEnergyThreshold) chorusScore += 0.3;
        if (energyRatio > 1.25) chorusScore += 0.25;
        if (shortLongRatio > 1.2) chorusScore += 0.2;
        if (features.highEnergy > 0.25) chorusScore += 0.15;
        if (features.bassEnergy > 0.3) chorusScore += 0.1;
    }
    
    // 滞后阈值
    float enterThreshold = 0.55;  // 进入副歌
    float exitThreshold = 0.35;   // 退出副歌
    
    BOOL inChorus = (self.previousSegment == MusicSegmentChorus);
    BOOL shouldBeChorus = inChorus ? 
        (chorusScore >= exitThreshold) : 
        (chorusScore >= enterThreshold);
    
    // 副歌数量限制
    if (shouldBeChorus && !inChorus && self.chorusCount >= kMaxChorusCount) {
        shouldBeChorus = NO;
    }
    
    // 副歌最小持续时间
    if (inChorus && timeSinceSegmentStart < kMinChorusDuration) {
        return MusicSegmentChorus;
    }
    
    // 副歌判定
    if (shouldBeChorus) {
        if (!inChorus) {
            self.chorusCount++;
            if (!self.firstChorusDetected) {
                self.firstChorusDetected = YES;
                self.firstChorusTime = currentTime;
                self.chorusEnergyThreshold = features.energy * 0.85;
            }
        }
        return MusicSegmentChorus;
    }
    
    // 4. 过渡段检测
    if (self.previousSegment == MusicSegmentChorus && !shouldBeChorus) {
        // 从副歌出来，先进入过渡段
        return MusicSegmentBridge;
    }
    
    // 5. 从过渡段进入主歌
    if (self.previousSegment == MusicSegmentBridge && timeSinceSegmentStart >= 4.0) {
        return MusicSegmentVerse;
    }
    
    // 6. 从前奏进入主歌
    if (self.previousSegment == MusicSegmentIntro) {
        return MusicSegmentVerse;
    }
    
    // 保持当前段落
    if (self.previousSegment != MusicSegmentUnknown) {
        return self.previousSegment;
    }
    
    return MusicSegmentVerse;
}

#pragma mark - Segment Analysis Helpers

- (void)updateSegmentStatistics:(AudioFeatures *)features {
    // 更新峰值能量
    if (features.energy > self.peakEnergy) {
        self.peakEnergy = features.energy;
        // 动态调整副歌阈值
        self.chorusEnergyThreshold = self.peakEnergy * 0.75;
    }
    
    // 计算平均能量（使用长期滑动平均）
    if (self.energyEnvelope.count > 0) {
        float sum = 0;
        for (NSNumber *e in self.energyEnvelope) {
            sum += e.floatValue;
        }
        self.averageEnergy = sum / self.energyEnvelope.count;
        
        // 计算能量方差
        float variance = 0;
        for (NSNumber *e in self.energyEnvelope) {
            float diff = e.floatValue - self.averageEnergy;
            variance += diff * diff;
        }
        self.energyVariance = variance / self.energyEnvelope.count;
    }
}

- (float)calculateRecentEnergyTrend {
    // 计算最近能量的趋势（正=上升，负=下降）
    if (self.energyEnvelope.count < 60) return 0;  // 至少需要1秒数据
    
    NSInteger recentCount = MIN(60, self.energyEnvelope.count);
    NSInteger startIdx = self.energyEnvelope.count - recentCount;
    
    float firstHalf = 0, secondHalf = 0;
    NSInteger halfCount = recentCount / 2;
    
    for (NSInteger i = 0; i < halfCount; i++) {
        firstHalf += [self.energyEnvelope[startIdx + i] floatValue];
        secondHalf += [self.energyEnvelope[startIdx + halfCount + i] floatValue];
    }
    
    firstHalf /= halfCount;
    secondHalf /= halfCount;
    
    return secondHalf - firstHalf;
}

- (float)calculateSpectralChange {
    // 计算频谱对比度的变化
    if (self.spectralContrast.count < 30) return 0;
    
    NSInteger recentCount = MIN(30, self.spectralContrast.count);
    NSInteger startIdx = self.spectralContrast.count - recentCount;
    
    float maxChange = 0;
    float prevContrast = [self.spectralContrast[startIdx] floatValue];
    
    for (NSInteger i = 1; i < recentCount; i++) {
        float currentContrast = [self.spectralContrast[startIdx + i] floatValue];
        float change = fabsf(currentContrast - prevContrast);
        if (change > maxChange) {
            maxChange = change;
        }
        prevContrast = currentContrast;
    }
    
    return maxChange;
}

#pragma mark - Energy History

- (void)updateEnergyHistory:(float)energy {
    [self.energyHistory addObject:@(energy)];
    if (self.energyHistory.count > kEnergyHistorySize) {
        [self.energyHistory removeObjectAtIndex:0];
    }
}

- (void)pushAdaptiveValue:(float)value
                toHistory:(NSMutableArray<NSNumber *> *)history
                   maxLen:(NSUInteger)maxLen {
    [history addObject:@(value)];
    if (history.count > maxLen) {
        [history removeObjectAtIndex:0];
    }
}

- (BOOL)detectAdaptiveHitWithValue:(float)value
                           history:(NSArray<NSNumber *> *)history
                             floor:(float)floor
                          sigmaMul:(float)sigmaMul
                       minInterval:(NSTimeInterval)minInterval
                         lastStamp:(NSTimeInterval *)lastStamp
                               now:(NSTimeInterval)now {
    if (history.count < 8) return NO;
    float mean = 0.0f;
    for (NSNumber *n in history) mean += n.floatValue;
    mean /= (float)history.count;
    float var = 0.0f;
    for (NSNumber *n in history) {
        float d = n.floatValue - mean;
        var += d * d;
    }
    float stdv = sqrtf(var / (float)history.count);
    float threshold = MAX(floor, mean + sigmaMul * stdv);
    BOOL intervalPassed = (now - *lastStamp) > minInterval;
    BOOL hit = intervalPassed && value > threshold;
    if (hit) *lastStamp = now;
    return hit;
}

- (float)computePanValueFromLeft:(NSArray<NSNumber *> *)left right:(NSArray<NSNumber *> *)right {
    if (left.count == 0 || right.count == 0) return 0.0f;
    NSUInteger N = MIN(left.count, right.count);
    float l = 0.0f, r = 0.0f;
    for (NSUInteger i = 0; i < N; i++) {
        l += fabsf([left[i] floatValue]);
        r += fabsf([right[i] floatValue]);
    }
    if (N == 0) return 0.0f;
    l /= (float)N;
    r /= (float)N;
    float den = l + r + 1e-6f;
    return (l - r) / den;
}

- (float)envelopePeriodicityFromHistory:(NSArray<NSNumber *> *)history {
    // Simple normalized autocorrelation peak in 3..30 frame lags (~2..20Hz at ~60fps)
    NSInteger N = history.count;
    if (N < 32) return 0.0f;
    float mean = 0.0f;
    for (NSNumber *n in history) mean += n.floatValue;
    mean /= (float)N;

    float denom = 0.0f;
    for (NSNumber *n in history) {
        float d = n.floatValue - mean;
        denom += d * d;
    }
    if (denom < 1e-6f) return 0.0f;

    float best = 0.0f;
    for (NSInteger lag = 3; lag <= 30; lag++) {
        float num = 0.0f;
        for (NSInteger i = lag; i < N; i++) {
            float a = history[i].floatValue - mean;
            float b = history[i - lag].floatValue - mean;
            num += a * b;
        }
        float corr = num / denom;
        if (corr > best) best = corr;
    }
    return MAX(0.0f, MIN(best, 1.0f));
}

- (void)updateEDMEffectsWithFeatures:(AudioFeatures *)features useHPSS:(BOOL)useHPSS {
    // Update histories
    [self pushAdaptiveValue:features.spectralCentroid toHistory:self.centroidHistory maxLen:96];
    [self pushAdaptiveValue:features.energy toHistory:self.envelopeHistory maxLen:96];
    [self pushAdaptiveValue:(features.transientHit || features.beatDetected) ? 1.0f : 0.0f
                  toHistory:self.onsetHistory
                     maxLen:96];
    [self pushAdaptiveValue:self.latestPanValue toHistory:self.panHistory maxLen:96];

    float periodicity = [self envelopePeriodicityFromHistory:self.envelopeHistory];

    // Onset density in last ~1s (60 frames)
    NSInteger onsetCount = 0;
    NSInteger onsetWindow = MIN((NSInteger)self.onsetHistory.count, 60);
    for (NSInteger i = self.onsetHistory.count - onsetWindow; i < self.onsetHistory.count; i++) {
        if (i >= 0 && self.onsetHistory[i].floatValue > 0.5f) onsetCount++;
    }
    float onsetDensityHz = (float)onsetCount; // ~per second

    // Centroid trend / slope
    float centroidSlope = 0.0f;
    NSInteger cN = MIN((NSInteger)self.centroidHistory.count, 24);
    if (cN >= 6) {
        float first = self.centroidHistory[self.centroidHistory.count - cN].floatValue;
        float last = self.centroidHistory.lastObject.floatValue;
        centroidSlope = (last - first) / (float)cN;
    }

    // Pan movement strength
    float panStd = 0.0f;
    NSInteger pN = MIN((NSInteger)self.panHistory.count, 64);
    if (pN >= 8) {
        float mean = 0.0f;
        for (NSInteger i = self.panHistory.count - pN; i < self.panHistory.count; i++) mean += self.panHistory[i].floatValue;
        mean /= (float)pN;
        float var = 0.0f;
        for (NSInteger i = self.panHistory.count - pN; i < self.panHistory.count; i++) {
            float d = self.panHistory[i].floatValue - mean;
            var += d * d;
        }
        panStd = sqrtf(var / (float)pN);
    }

    // Delay: autocorr multi-peak proxy (periodicity + moderate onset density)
    float delayConf = MIN(1.0f, periodicity * 0.8f + MIN(1.0f, onsetDensityHz / 12.0f) * 0.2f);

    // Stutter / Gate
    features.stutterConfidence = MIN(1.0f, MIN(1.0f, onsetDensityHz / 12.0f) * 0.7f + periodicity * 0.3f);
    features.gateConfidence = MIN(1.0f, periodicity * 0.75f + (1.0f - features.energy) * 0.25f);
    features.stutterDetected = features.stutterConfidence > 0.55f;
    features.gateDetected = features.gateConfidence > 0.58f;

    // Tremolo / Sidechain
    features.tremoloConfidence = MIN(1.0f, periodicity * 0.75f + MIN(1.0f, features.spectralFlux) * 0.25f);
    float bpmSync = (features.bpm > 70.0f && features.bpm < 180.0f) ? 1.0f : 0.0f;
    if (useHPSS) {
        features.sidechainConfidence = MIN(1.0f,
                                           features.subBassEnergy * 0.45f +
                                           features.transientStrength * 0.30f +
                                           periodicity * 0.15f +
                                           bpmSync * 0.10f);
    } else {
        features.sidechainConfidence = MIN(1.0f,
                                           features.bassEnergy * 0.55f +
                                           periodicity * 0.30f +
                                           bpmSync * 0.15f);
    }
    features.tremoloDetected = features.tremoloConfidence > 0.58f;
    features.sidechainDetected = features.sidechainConfidence > 0.62f;

    // Filter Sweep
    features.filterSweepConfidence = MIN(1.0f, fabsf(centroidSlope) * 18.0f);
    features.filterSweepDetected = features.filterSweepConfidence > 0.42f;

    // Auto-Pan
    features.autoPanConfidence = MIN(1.0f, panStd * 8.0f);
    features.autoPanDetected = features.autoPanConfidence > 0.40f;

    // Delay
    features.delayConfidence = delayConf;
    features.delayDetected = features.delayConfidence > 0.55f;

    // Distortion weak detect
    if (useHPSS) {
        float harmonicNoiseRatio = features.harmonicStrength / MAX(0.05f, features.noiseStrength);
        float distortion = (1.0f - MIN(1.0f, harmonicNoiseRatio / 2.0f)) * 0.45f
                         + features.spectralFlatness * 0.35f
                         + features.highEnergy * 0.20f;
        features.distortionConfidence = MIN(1.0f, MAX(0.0f, distortion));
    } else {
        features.distortionConfidence = MIN(1.0f, features.highEnergy * 0.65f + features.spectralFlux * 0.35f);
    }
    features.distortionDetected = features.distortionConfidence > 0.65f;

    // Explainability flags (HPSS only)
    features.hpssExplainable = useHPSS;
    if (useHPSS) {
        features.harmonicDriven = features.harmonicStrength > MAX(features.noiseStrength, features.transientStrength);
        features.transientDriven = features.transientStrength > MAX(features.harmonicStrength, features.noiseStrength);
        features.noiseResidualDriven = features.noiseStrength > MAX(features.harmonicStrength, features.transientStrength);
    } else {
        features.harmonicDriven = NO;
        features.transientDriven = NO;
        features.noiseResidualDriven = NO;
    }
}

#pragma mark - Observer Management

- (void)addObserver:(id<AudioFeatureObserver>)observer {
    [self.observers addObject:observer];
}

- (void)removeObserver:(id<AudioFeatureObserver>)observer {
    [self.observers removeObject:observer];
}

- (void)notifyFeaturesUpdate:(AudioFeatures *)features {
    for (id<AudioFeatureObserver> observer in self.observers) {
        if ([observer respondsToSelector:@selector(audioFeatureExtractor:didUpdateFeatures:)]) {
            [observer audioFeatureExtractor:self didUpdateFeatures:features];
        }
    }
}

- (void)notifyBeatDetected:(NSTimeInterval)time {
    for (id<AudioFeatureObserver> observer in self.observers) {
        if ([observer respondsToSelector:@selector(audioFeatureExtractor:didDetectBeatAtTime:)]) {
            [observer audioFeatureExtractor:self didDetectBeatAtTime:time];
        }
    }
}

- (void)notifySegmentChange:(MusicSegment)oldSegment to:(MusicSegment)newSegment {
    NSString *oldName = [self segmentNameForType:oldSegment];
    NSString *newName = [self segmentNameForType:newSegment];
    
    NSLog(@"🎭 段落变化: %@ → %@ (能量:%.2f, 峰值:%.2f, 平均:%.2f, 副歌次数:%ld)",
          oldName, newName, 
          self.shortTermEnergy, self.peakEnergy, self.averageEnergy,
          (long)self.chorusCount);
    
    // 记录段落历史
    [self.segmentHistory addObject:@{
        @"from": @(oldSegment),
        @"to": @(newSegment),
        @"time": @(self.currentFeatures.timestamp),
        @"energy": @(self.shortTermEnergy)
    }];
    
    for (id<AudioFeatureObserver> observer in self.observers) {
        if ([observer respondsToSelector:@selector(audioFeatureExtractor:didChangeSegmentFrom:to:)]) {
            [observer audioFeatureExtractor:self didChangeSegmentFrom:oldSegment to:newSegment];
        }
    }
}

- (NSString *)segmentNameForType:(MusicSegment)segment {
    switch (segment) {
        case MusicSegmentIntro: return @"前奏";
        case MusicSegmentVerse: return @"主歌";
        case MusicSegmentChorus: return @"副歌";
        case MusicSegmentBridge: return @"过渡";
        case MusicSegmentOutro: return @"尾奏";
        default: return @"未知";
    }
}

@end
