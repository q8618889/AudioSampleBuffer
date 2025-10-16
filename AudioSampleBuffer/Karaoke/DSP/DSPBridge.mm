//
//  DSPBridge.mm
//  AudioSampleBuffer
//
//  DSP 音效处理桥接层实现 (Objective-C++)
//

#import "DSPBridge.h"
#import "RNNoise/rnnoise.h"
#import "SoundTouch/SoundTouchBridge.h"
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
@property (nonatomic, assign) std::vector<float> *outputBuffer;  // 输出缓冲区
@property (nonatomic, assign) NSUInteger outputBufferPos;         // 输出缓冲区读取位置
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
        _outputBuffer = new std::vector<float>();
        _outputBufferPos = 0;
        
        _soundTouchHandle = soundtouch_create();
        if (!_soundTouchHandle) {
            NSLog(@"❌ 音高修正处理器初始化失败");
            return nil;
        }
        
        soundtouch_setSampleRate(_soundTouchHandle, (unsigned int)sampleRate);
        soundtouch_setChannels(_soundTouchHandle, (unsigned int)channels);
        
        // 🎵 优化设置：降低延迟
        soundtouch_setSetting(_soundTouchHandle, SETTING_SEQUENCE_MS, 40);     // 序列长度（默认82ms，减少到40ms）
        soundtouch_setSetting(_soundTouchHandle, SETTING_SEEKWINDOW_MS, 15);   // 搜索窗口（默认28ms，减少到15ms）
        soundtouch_setSetting(_soundTouchHandle, SETTING_OVERLAP_MS, 8);       // 重叠长度（默认12ms，减少到8ms）
        
        NSLog(@"✅ SoundTouch v%s 初始化成功", soundtouch_getVersionString());
        NSLog(@"   采样率: %.0f Hz, 声道: %lu", sampleRate, (unsigned long)channels);
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
    if (_outputBuffer) {
        delete _outputBuffer;
        _outputBuffer = nullptr;
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
    
    NSUInteger totalChannelSamples = inputCount * _channels;
    NSUInteger outputChannelSamples = maxOutputCount * _channels;
    
    // 输入样本到 SoundTouch
    soundtouch_putSamples(_soundTouchHandle, inputSamples, (unsigned int)inputCount);
    
    // 🎵 关键优化：使用内部缓冲区累积输出
    NSUInteger outputPos = 0;
    
    // 1. 先从内部缓冲区读取剩余样本
    if (_outputBufferPos < _outputBuffer->size()) {
        NSUInteger available = _outputBuffer->size() - _outputBufferPos;
        NSUInteger toCopy = (available < outputChannelSamples) ? available : outputChannelSamples;
        
        memcpy(outputSamples, &(*_outputBuffer)[_outputBufferPos], toCopy * sizeof(float));
        _outputBufferPos += toCopy;
        outputPos += toCopy;
        
        // 如果已经满足需求，返回
        if (outputPos >= outputChannelSamples) {
            return outputPos / _channels;
        }
    }
    
    // 2. 从 SoundTouch 读取新样本
    _outputBuffer->resize(outputChannelSamples * 2);  // 预留足够空间
    unsigned int receivedSamples = soundtouch_receiveSamples(_soundTouchHandle, 
                                                              &(*_outputBuffer)[0], 
                                                              (unsigned int)maxOutputCount * 2);
    
    // 3. 复制到输出缓冲区
    if (receivedSamples > 0) {
        NSUInteger receivedChannelSamples = receivedSamples * _channels;
        NSUInteger remaining = outputChannelSamples - outputPos;
        NSUInteger toCopy = (receivedChannelSamples < remaining) ? receivedChannelSamples : remaining;
        
        memcpy(&outputSamples[outputPos], &(*_outputBuffer)[0], toCopy * sizeof(float));
        outputPos += toCopy;
        
        // 保存剩余样本到内部缓冲区
        if (receivedChannelSamples > toCopy) {
            _outputBuffer->resize(receivedChannelSamples);
            memmove(&(*_outputBuffer)[0], &(*_outputBuffer)[toCopy], 
                    (receivedChannelSamples - toCopy) * sizeof(float));
            _outputBuffer->resize(receivedChannelSamples - toCopy);
            _outputBufferPos = 0;
        } else {
            _outputBuffer->clear();
            _outputBufferPos = 0;
        }
    }
    
    // 4. 如果仍然不足，用零填充（避免静音）
    if (outputPos < outputChannelSamples) {
        // 用输入样本填充（直通模式）
        NSUInteger remaining = outputChannelSamples - outputPos;
        NSUInteger toCopy = (remaining < totalChannelSamples) ? remaining : totalChannelSamples;
        memcpy(&outputSamples[outputPos], inputSamples, toCopy * sizeof(float));
        outputPos += toCopy;
        
        static int fillCount = 0;
        if (++fillCount % 100 == 0) {
            NSLog(@"⚠️ SoundTouch 输出不足，使用直通填充: %lu/%lu", 
                  (unsigned long)receivedSamples, (unsigned long)inputCount);
        }
    }
    
    return outputPos / _channels;
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
    _outputBuffer->clear();
    _outputBufferPos = 0;
}

- (void)flush {
    if (_soundTouchHandle) {
        soundtouch_flush(_soundTouchHandle);
    }
}

@end

