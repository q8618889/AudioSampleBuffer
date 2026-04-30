#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "RealtimeAnalyzerDSP.h"

NS_ASSUME_NONNULL_BEGIN

/// Per-frame extended analysis output (one per channel).
@interface RealtimeAnalyzerFrame : NSObject
/// 80 mixed-band magnitudes (existing visual-spectrum representation).
@property (nonatomic, copy) NSArray<NSNumber *> *bands;
/// 80 harmonic-component bands (HPSS H), nullable if extended path disabled.
@property (nonatomic, copy, nullable) NSArray<NSNumber *> *harmonicBands;
/// 80 percussive-component bands (HPSS P), nullable if extended path disabled.
@property (nonatomic, copy, nullable) NSArray<NSNumber *> *percussiveBands;
/// 80 residual/noise-component bands (HPSS R), nullable if extended path disabled.
@property (nonatomic, copy, nullable) NSArray<NSNumber *> *residualBands;
/// 4-class category features extracted from H/P/R + spectral flatness.
@property (nonatomic, assign) AnalyzerCategoryFeatures category;
@end

/// Result returned by analyseExtended:
@interface RealtimeAnalyzerResult : NSObject
@property (nonatomic, copy) NSArray<RealtimeAnalyzerFrame *> *frames; // one per channel
@end

@interface RealtimeAnalyzer : NSObject

- (instancetype)initWithFFTSize:(int)fftSize;

/// Configure the FFT window size used for analysis. The tap buffer size delivered
/// by AVAudioEngine may be smaller — the DSP accumulates samples in a sliding window.
@property (nonatomic, assign, readonly) int fftSize;
@property (nonatomic, assign) BOOL legacyExactMode;

/// Backwards-compatible API: returns NSArray of NSArray<NSNumber*> of band values per channel.
- (NSArray *)analyse:(AVAudioPCMBuffer *)buffer withAmplitudeLevel:(int)amplitudeLevel;

/// Extended API: returns RealtimeAnalyzerResult with HPSS bands and category features.
- (RealtimeAnalyzerResult *)analyseExtended:(AVAudioPCMBuffer *)buffer
                          withAmplitudeLevel:(int)amplitudeLevel;

/// Tune HPSS parameters at runtime (defaults Lh=11, Lp=17, β=1.8).
- (void)setHPSSTimeMedian:(int)timeMedianLen
                freqMedian:(int)freqMedianLen
         separationFactor:(float)separationFactor;

@end

NS_ASSUME_NONNULL_END
