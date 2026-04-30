#import "RealtimeAnalyzer.h"
#import "RealtimeAnalyzerDSP.h"

@implementation RealtimeAnalyzerFrame
@end

@implementation RealtimeAnalyzerResult
@end

@interface RealtimeAnalyzer ()

@property (nonatomic, assign) NSUInteger frequencyBands;
@property (nonatomic, assign) AnalyzerDSPRef dspRef;

@end

@implementation RealtimeAnalyzer

- (void)dealloc {
    if (_dspRef != NULL) {
        AnalyzerDSP_Destroy(_dspRef);
        _dspRef = NULL;
    }
}

- (instancetype)initWithFFTSize:(int)fftSize {
    if (self = [super init]) {
        _fftSize = fftSize;
        _frequencyBands = 80;
        _legacyExactMode = NO;
        _dspRef = AnalyzerDSP_Create(fftSize,
                                      (int)_frequencyBands,
                                      50.0f,      // startFrequency
                                      18000.0f,   // endFrequency
                                      44100.0f);  // sampleRate for A-weight
    }
    return self;
}

- (void)setHPSSTimeMedian:(int)timeMedianLen
                freqMedian:(int)freqMedianLen
         separationFactor:(float)separationFactor {
    if (!_dspRef) return;
    AnalyzerDSP_SetHPSSParameters(_dspRef, timeMedianLen, freqMedianLen, separationFactor);
}

#pragma mark - Internal helpers

/// Run AnalyzerDSP_ProcessChannel on each channel; outputs the bands NSArray.
- (NSArray *)analyse:(AVAudioPCMBuffer *)buffer withAmplitudeLevel:(int)amplitudeLevel {
    if (!_dspRef) return @[];

    float *const *floatChannelData = buffer.floatChannelData;
    if (!floatChannelData) return @[];

    AVAudioChannelCount channelCount = buffer.format.channelCount;
    BOOL isInterleaved = buffer.format.isInterleaved;
    float actualSampleRate = (float)buffer.format.sampleRate;
    AVAudioFrameCount frameLength = buffer.frameLength;
    int fftSize = self.fftSize;
    int bands = (int)_frequencyBands;

    float outBands[bands];

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:channelCount];

    if (isInterleaved && channelCount > 1) {
        float *interleaved = floatChannelData[0];
        int totalSamples = (int)frameLength * (int)channelCount;

        for (AVAudioChannelCount ch = 0; ch < channelCount && ch < 2; ch++) {
            float channelSamples[fftSize];
            memset(channelSamples, 0, sizeof(float) * (size_t)fftSize);
            int idx = 0;
            for (int j = (int)ch; j < totalSamples; j += (int)channelCount) {
                if (idx < fftSize) channelSamples[idx++] = interleaved[j];
            }
            if (self.legacyExactMode) {
                AnalyzerDSP_ProcessChannelLegacyExact(_dspRef, channelSamples,
                                                      (int)ch, amplitudeLevel,
                                                      actualSampleRate, outBands);
            } else {
                AnalyzerDSP_ProcessChannel(_dspRef, channelSamples,
                                           (int)frameLength,
                                           (int)ch, amplitudeLevel,
                                           actualSampleRate, outBands);
            }

            NSMutableArray *channelResult = [NSMutableArray arrayWithCapacity:bands];
            for (int i = 0; i < bands; i++) {
                [channelResult addObject:@(outBands[i])];
            }
            [result addObject:channelResult];
        }
    } else {
        for (AVAudioChannelCount ch = 0; ch < channelCount && ch < 2; ch++) {
            float *channelData = floatChannelData[ch];
            if (self.legacyExactMode) {
                float channelSamples[fftSize];
                memset(channelSamples, 0, sizeof(float) * (size_t)fftSize);
                if (channelData) {
                    int copyCount = MIN((int)frameLength, fftSize);
                    memcpy(channelSamples, channelData, sizeof(float) * (size_t)copyCount);
                }
                AnalyzerDSP_ProcessChannelLegacyExact(_dspRef, channelSamples,
                                                      (int)ch, amplitudeLevel,
                                                      actualSampleRate, outBands);
            } else {
                AnalyzerDSP_ProcessChannel(_dspRef, channelData,
                                           (int)frameLength,
                                           (int)ch, amplitudeLevel,
                                           actualSampleRate, outBands);
            }

            NSMutableArray *channelResult = [NSMutableArray arrayWithCapacity:bands];
            for (int i = 0; i < bands; i++) {
                [channelResult addObject:@(outBands[i])];
            }
            [result addObject:channelResult];
        }
    }

    return result.copy;
}

- (RealtimeAnalyzerResult *)analyseExtended:(AVAudioPCMBuffer *)buffer
                          withAmplitudeLevel:(int)amplitudeLevel {
    RealtimeAnalyzerResult *out = [[RealtimeAnalyzerResult alloc] init];
    out.frames = @[];
    if (!_dspRef) return out;

    float *const *floatChannelData = buffer.floatChannelData;
    if (!floatChannelData) return out;

    AVAudioChannelCount channelCount = buffer.format.channelCount;
    BOOL isInterleaved = buffer.format.isInterleaved;
    float actualSampleRate = (float)buffer.format.sampleRate;
    AVAudioFrameCount frameLength = buffer.frameLength;
    int bands = (int)_frequencyBands;

    float outBands[bands];
    float outH[bands];
    float outP[bands];
    float outR[bands];

    NSMutableArray<RealtimeAnalyzerFrame *> *frames = [NSMutableArray arrayWithCapacity:channelCount];

    if (isInterleaved && channelCount > 1) {
        float *interleaved = floatChannelData[0];
        int totalSamples = (int)frameLength * (int)channelCount;

        for (AVAudioChannelCount ch = 0; ch < channelCount && ch < 2; ch++) {
            float channelSamples[frameLength];
            int idx = 0;
            for (int j = (int)ch; j < totalSamples; j += (int)channelCount) {
                if (idx < (int)frameLength) channelSamples[idx++] = interleaved[j];
            }
            AnalyzerCategoryFeatures cat;
            memset(&cat, 0, sizeof(cat));
            AnalyzerDSP_ProcessChannelExtended(_dspRef, channelSamples,
                                                (int)frameLength,
                                                (int)ch, amplitudeLevel,
                                                actualSampleRate,
                                                outBands, outH, outP, outR, &cat);
            [frames addObject:[self frameFromBands:outBands H:outH P:outP R:outR
                                          category:cat bandCount:bands]];
        }
    } else {
        for (AVAudioChannelCount ch = 0; ch < channelCount && ch < 2; ch++) {
            float *channelData = floatChannelData[ch];

            AnalyzerCategoryFeatures cat;
            memset(&cat, 0, sizeof(cat));
            AnalyzerDSP_ProcessChannelExtended(_dspRef, channelData,
                                                (int)frameLength,
                                                (int)ch, amplitudeLevel,
                                                actualSampleRate,
                                                outBands, outH, outP, outR, &cat);
            [frames addObject:[self frameFromBands:outBands H:outH P:outP R:outR
                                          category:cat bandCount:bands]];
        }
    }

    out.frames = frames.copy;
    return out;
}

- (RealtimeAnalyzerFrame *)frameFromBands:(const float *)bandsBuf
                                          H:(const float *)hBuf
                                          P:(const float *)pBuf
                                          R:(const float *)rBuf
                                   category:(AnalyzerCategoryFeatures)cat
                                  bandCount:(int)count {
    RealtimeAnalyzerFrame *frame = [[RealtimeAnalyzerFrame alloc] init];
    NSMutableArray<NSNumber *> *b  = [NSMutableArray arrayWithCapacity:count];
    NSMutableArray<NSNumber *> *bh = [NSMutableArray arrayWithCapacity:count];
    NSMutableArray<NSNumber *> *bp = [NSMutableArray arrayWithCapacity:count];
    NSMutableArray<NSNumber *> *br = [NSMutableArray arrayWithCapacity:count];
    for (int i = 0; i < count; i++) {
        [b  addObject:@(bandsBuf[i])];
        [bh addObject:@(hBuf[i])];
        [bp addObject:@(pBuf[i])];
        [br addObject:@(rBuf[i])];
    }
    frame.bands           = b.copy;
    frame.harmonicBands   = bh.copy;
    frame.percussiveBands = bp.copy;
    frame.residualBands   = br.copy;
    frame.category        = cat;
    return frame;
}

@end
