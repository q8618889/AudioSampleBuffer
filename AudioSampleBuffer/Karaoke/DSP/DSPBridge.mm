//
//  DSPBridge.mm
//  AudioSampleBuffer
//
//  DSP 音效处理桥接层实现 (Objective-C++)
//

#import "DSPBridge.h"
#import "RNNoise/rnnoise.h"
#import "SoundTouch/SoundTouch.h"
#include <vector>

#pragma mark - 降噪处理器实现

@interface NoiseReductionProcessor ()
@property (nonatomic, assign) DenoiseState *denoiseState;
@property (nonatomic, assign) double sampleRate;
@property (nonatomic, assign) std::vector<float> *floatBuffer;
@end

@implementation NoiseReductionProcessor

- (instancetype)initWithSampleRate:(double)sampleRate {
    self = [super init];
    if (self) {
        _sampleRate = sampleRate;
        _denoiseState = rnnoise_create(NULL);
        _floatBuffer = new std::vector<float>();
        
        if (!_denoiseState) {
            NSLog(@"❌ 降噪处理器初始化失败");
            return nil;
        }
        
        NSLog(@"✅ 降噪处理器初始化成功 (采样率: %.0f Hz, 帧大小: %d)", 
              sampleRate, rnnoise_get_frame_size());
    }
    return self;
}

- (void)dealloc {
    if (_denoiseState) {
        rnnoise_destroy(_denoiseState);
        _denoiseState = NULL;
    }
    if (_floatBuffer) {
        delete _floatBuffer;
        _floatBuffer = nullptr;
    }
}

- (float)processSamples:(float *)samples count:(NSUInteger)sampleCount {
    if (!_denoiseState || !samples || sampleCount == 0) return 0.0f;
    
    int frameSize = rnnoise_get_frame_size();
    float vadProb = 0.0f;
    
    // RNNoise 按帧处理（通常 480 样本/帧 @ 48kHz，或调整到 44.1kHz）
    NSUInteger processedSamples = 0;
    while (processedSamples + frameSize <= sampleCount) {
        vadProb = rnnoise_process_frame(_denoiseState, &samples[processedSamples]);
        processedSamples += frameSize;
    }
    
    return vadProb;
}

- (float)processInt16Samples:(SInt16 *)samples count:(NSUInteger)sampleCount {
    if (!samples || sampleCount == 0) return 0.0f;
    
    // SInt16 转 float
    _floatBuffer->resize(sampleCount);
    for (NSUInteger i = 0; i < sampleCount; i++) {
        (*_floatBuffer)[i] = samples[i] / 32768.0f;
    }
    
    // 处理
    float vadProb = [self processSamples:_floatBuffer->data() count:sampleCount];
    
    // float 转回 SInt16
    for (NSUInteger i = 0; i < sampleCount; i++) {
        float sample = (*_floatBuffer)[i];
        // 限幅
        sample = fmaxf(-1.0f, fminf(1.0f, sample));
        samples[i] = (SInt16)(sample * 32767.0f);
    }
    
    return vadProb;
}

- (void)reset {
    if (_denoiseState) {
        rnnoise_destroy(_denoiseState);
        _denoiseState = rnnoise_create(NULL);
    }
}

@end

#pragma mark - 音高修正处理器实现

@interface PitchCorrectionProcessor ()
@property (nonatomic, assign) SoundTouchHandle *soundTouchHandle;
@property (nonatomic, assign) double sampleRate;
@property (nonatomic, assign) NSUInteger channels;
@property (nonatomic, assign) BOOL autoTuneEnabled;
@property (nonatomic, assign) NSInteger musicalKey;
@property (nonatomic, assign) NSInteger musicalScale;
@property (nonatomic, assign) std::vector<float> *floatBuffer;
@end

@implementation PitchCorrectionProcessor

- (instancetype)initWithSampleRate:(double)sampleRate channels:(NSUInteger)channels {
    self = [super init];
    if (self) {
        _sampleRate = sampleRate;
        _channels = channels;
        _autoTuneEnabled = NO;
        _musicalKey = 0; // C
        _musicalScale = 0; // Major
        _floatBuffer = new std::vector<float>();
        
        _soundTouchHandle = soundtouch_create();
        if (!_soundTouchHandle) {
            NSLog(@"❌ 音高修正处理器初始化失败");
            return nil;
        }
        
        soundtouch_setSampleRate(_soundTouchHandle, (unsigned int)sampleRate);
        soundtouch_setChannels(_soundTouchHandle, (unsigned int)channels);
        
        NSLog(@"✅ 音高修正处理器初始化成功 (采样率: %.0f Hz, 声道: %lu)", 
              sampleRate, (unsigned long)channels);
    }
    return self;
}

- (void)dealloc {
    if (_soundTouchHandle) {
        soundtouch_destroy(_soundTouchHandle);
        _soundTouchHandle = NULL;
    }
    if (_floatBuffer) {
        delete _floatBuffer;
        _floatBuffer = nullptr;
    }
}

- (void)setPitchShift:(float)semitones {
    if (_soundTouchHandle) {
        soundtouch_setPitch(_soundTouchHandle, semitones);
    }
}

- (void)setRate:(float)rate {
    if (_soundTouchHandle) {
        soundtouch_setRate(_soundTouchHandle, rate);
    }
}

- (void)setAutoTuneEnabled:(BOOL)enabled key:(NSInteger)key scale:(NSInteger)scale {
    _autoTuneEnabled = enabled;
    _musicalKey = key;
    _musicalScale = scale;
    
    // Auto-Tune 实现需要音高检测算法，这里简化处理
    NSLog(@"🎵 Auto-Tune %@: Key=%ld %@", 
          enabled ? @"启用" : @"禁用", 
          (long)key, 
          scale == 0 ? @"Major" : @"Minor");
}

- (NSUInteger)processInputSamples:(const float *)inputSamples
                       inputCount:(NSUInteger)inputCount
                    outputSamples:(float *)outputSamples
                   maxOutputCount:(NSUInteger)maxOutputCount {
    if (!_soundTouchHandle || !inputSamples || !outputSamples) return 0;
    
    // 输入样本到 SoundTouch
    soundtouch_putSamples(_soundTouchHandle, inputSamples, (unsigned int)inputCount);
    
    // 接收处理后的样本
    unsigned int receivedSamples = soundtouch_receiveSamples(_soundTouchHandle, 
                                                              outputSamples, 
                                                              (unsigned int)maxOutputCount);
    
    return (NSUInteger)receivedSamples;
}

- (NSUInteger)processInt16InputSamples:(const SInt16 *)inputSamples
                            inputCount:(NSUInteger)inputCount
                         outputSamples:(SInt16 *)outputSamples
                        maxOutputCount:(NSUInteger)maxOutputCount {
    if (!inputSamples || !outputSamples) return 0;
    
    // SInt16 转 float
    NSUInteger totalSamples = inputCount * _channels;
    _floatBuffer->resize(std::max(totalSamples, maxOutputCount * _channels));
    
    for (NSUInteger i = 0; i < totalSamples; i++) {
        (*_floatBuffer)[i] = inputSamples[i] / 32768.0f;
    }
    
    // 处理
    NSUInteger outputCount = [self processInputSamples:_floatBuffer->data()
                                            inputCount:inputCount
                                         outputSamples:_floatBuffer->data()
                                        maxOutputCount:maxOutputCount];
    
    // float 转回 SInt16
    for (NSUInteger i = 0; i < outputCount * _channels; i++) {
        float sample = (*_floatBuffer)[i];
        sample = fmaxf(-1.0f, fminf(1.0f, sample));
        outputSamples[i] = (SInt16)(sample * 32767.0f);
    }
    
    return outputCount;
}

- (void)clear {
    if (_soundTouchHandle) {
        soundtouch_clear(_soundTouchHandle);
    }
}

- (void)flush {
    if (_soundTouchHandle) {
        soundtouch_flush(_soundTouchHandle);
    }
}

@end

