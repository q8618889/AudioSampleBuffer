//
//  KaraokeAudioEngine.m
//  AudioSampleBuffer
//
//  Created on 2025/10/14.
//  参考：https://blog.csdn.net/weixin_43030741/article/details/103477017
//  使用AudioUnit + AUGraph实现录音和耳返功能
//

#import "KaraokeAudioEngine.h"

#define kInputBus 1
#define kOutputBus 0

// 错误检查宏
static void CheckError(OSStatus error, const char *operation) {
    if (error == noErr) return;
    char errorString[20];
    *(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(error);
    if (isprint(errorString[1]) && isprint(errorString[2]) &&
        isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    } else {
        sprintf(errorString, "%d", (int)error);
    }
    NSLog(@"❌ Error: %s (%s)", operation, errorString);
}

#pragma mark - RecordingSegment 实现

@implementation RecordingSegment

- (instancetype)init {
    self = [super init];
    if (self) {
        _audioData = [NSMutableData data];
        _vocalData = [NSMutableData data];  // 🆕 初始化人声数据
        _startTime = 0.0;
        _duration = 0.0;
        _isRecorded = YES;
        _appliedEffect = VoiceEffectTypeNone;  // 🆕 默认无音效
        _appliedMicVolume = 1.0;  // 🆕 默认麦克风音量100%
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<RecordingSegment: %.2f~%.2fs, %@, %.2fMB>",
            self.startTime,
            self.startTime + self.duration,
            self.isRecorded ? @"录制" : @"BGM",
            self.audioData.length / (1024.0 * 1024.0)];
}

@end

#pragma mark - KaraokeAudioEngine

@interface KaraokeAudioEngine ()

// AudioUnit相关（重新声明为readwrite）
@property (nonatomic, assign, readwrite) AUGraph auGraph;
@property (nonatomic, assign) AudioUnit remoteIOUnit;
@property (nonatomic, assign) AUNode remoteIONode;

// 音频播放器（重新声明为readwrite）
@property (nonatomic, strong, readwrite) AVAudioPlayer *audioPlayer;

// BGM音频文件读取
@property (nonatomic, strong) AVAudioFile *bgmAudioFile;
@property (nonatomic, strong) NSData *bgmPCMData;  // 存储完整的BGM PCM数据
@property (nonatomic, assign) NSUInteger bgmPCMDataLength;  // PCM数据长度（样本数）
@property (atomic, assign) NSUInteger bgmReadPosition;  // 当前读取位置（样本索引）- 使用 atomic
@property (nonatomic, assign) BOOL shouldLoopBGM;
@property (nonatomic, assign) float bgmVolume;

// 分段录音相关（重新声明为readwrite）
@property (nonatomic, strong) NSMutableArray<RecordingSegment *> *recordingSegmentsInternal;  // 内部可变数组
@property (nonatomic, strong) RecordingSegment *currentSegment;  // 当前正在录制的段落
@property (nonatomic, assign) NSTimeInterval currentSegmentStartTime;  // 当前段落开始时间
@property (nonatomic, assign, readwrite) BOOL isRecordingPaused;  // 录音暂停状态
@property (nonatomic, copy) NSString *recordingFilePath;  // 最终合成文件路径

// 录音状态（重新声明为readwrite）
@property (nonatomic, assign, readwrite) BOOL isRecording;
@property (nonatomic, assign, readwrite) BOOL isPlaying;

// 🆕 预览播放相关
@property (nonatomic, strong) AVAudioPlayer *previewPlayer;  // 预览播放器
@property (nonatomic, strong) NSData *previewAudioData;  // 预览音频数据（缓存）
@property (nonatomic, copy) void (^previewCompletion)(NSError *error);  // 预览播放完成回调

// 混音缓冲区（预分配，避免实时 malloc/free）
@property (nonatomic, assign) SInt16 *mixBuffer;
@property (nonatomic, assign) UInt32 mixBufferSize;

// VU表更新节流（避免过于频繁的主线程调度）
@property (nonatomic, assign) int vuUpdateCounter;

// 耳返控制（重新声明为readwrite）
@property (nonatomic, assign, readwrite) BOOL enableEarReturn;
@property (nonatomic, assign, readwrite) float earReturnVolume;
@property (nonatomic, assign, readwrite) float microphoneVolume;

// 音效处理器（重新声明为readwrite）
@property (nonatomic, strong, readwrite) VoiceEffectProcessor *voiceEffectProcessor;

@end

@implementation KaraokeAudioEngine

// 🆕 录音段落的getter - 返回不可变副本
- (NSArray<RecordingSegment *> *)recordingSegments {
    return [self.recordingSegmentsInternal copy];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSLog(@"🔧 KaraokeAudioEngine init 开始");
        
        // 默认设置
        _enableEarReturn = YES;
        _earReturnVolume = 0.5;
        _microphoneVolume = 1.0;
        _bgmVolume = 0.3;  // 默认BGM音量30%
        _bgmReadPosition = 0;
        _shouldLoopBGM = NO;  // 不循环播放
        
        // 🆕 初始化分段录音
        _recordingSegmentsInternal = [NSMutableArray array];
        _currentSegment = nil;
        _currentSegmentStartTime = 0.0;
        _isRecordingPaused = NO;
        
        // 预分配混音缓冲区（避免实时 malloc/free）
        // 44100 Hz, 每次回调约 5-10ms，最大约 512 samples
        _mixBufferSize = 2048;  // 预留足够空间
        _mixBuffer = (SInt16 *)malloc(_mixBufferSize * sizeof(SInt16));
        if (!_mixBuffer) {
            NSLog(@"❌ 无法分配混音缓冲区");
            return nil;
        }
        NSLog(@"✅ 预分配混音缓冲区: %u samples", _mixBufferSize);
        
        // VU表更新计数器
        _vuUpdateCounter = 0;
        
        NSLog(@"🔧 Step 1: initAudioSession");
        [self initAudioSession];
        
        // 初始化音效处理器
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        double systemSampleRate = audioSession.sampleRate;
        _voiceEffectProcessor = [[VoiceEffectProcessor alloc] initWithSampleRate:systemSampleRate];
        [_voiceEffectProcessor setPresetEffect:VoiceEffectTypeNone];  // 默认无音效
        NSLog(@"✅ 音效处理器已初始化");
        
        NSLog(@"🔧 Step 2: setupAudioUnit");
        [self setupAudioUnit];
        
        NSLog(@"✅ KaraokeAudioEngine初始化完成（分段录音模式，支持跳转和回退）");
    }
    return self;
}

#pragma mark - AudioSession初始化

- (void)initAudioSession {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSError *error;
    
    // 🔧 关键修复：强制设置采样率为 44.1 kHz
    // 策略：先停用，设置参数，再激活
    
    // 1. 先停用 AudioSession（如果已激活）
    [audioSession setActive:NO error:&error];
    if (error) {
        NSLog(@"⚠️ 停用AudioSession失败: %@", error.localizedDescription);
        error = nil;
    }
    
    // 2. 设置采样率（必须在 category 之前）
    [audioSession setPreferredSampleRate:44100.0 error:&error];
    if (error) {
        NSLog(@"⚠️ 设置采样率失败: %@", error.localizedDescription);
        error = nil;
    } else {
        NSLog(@"✅ 设置首选采样率: 44100 Hz");
    }
    
    // 3. 设置为播放和录音模式
    // 关键：使用MixWithOthers让BGM和麦克风分离，避免麦克风捕获BGM
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                  withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker | 
                              AVAudioSessionCategoryOptionMixWithOthers |  // 允许混音但不捕获其他音频
                              AVAudioSessionCategoryOptionAllowBluetooth
                        error:&error];
    
    if (error) {
        NSLog(@"❌ 设置AudioSession category失败: %@", error.localizedDescription);
        error = nil;
    }
    
    // 4. 再次强制设置采样率（某些设备在 setCategory 后会重置）
    [audioSession setPreferredSampleRate:44100.0 error:&error];
    if (error) {
        NSLog(@"⚠️ 重新设置采样率失败: %@", error.localizedDescription);
        error = nil;
    }
    
    // 5. 设置 IO 缓冲区时长
    [audioSession setPreferredIOBufferDuration:0.005 error:&error];
    if (error) {
        NSLog(@"⚠️ 设置buffer duration失败: %@", error.localizedDescription);
        error = nil;
    }
    
    // 6. 激活 AudioSession
    [audioSession setActive:YES error:&error];
    if (error) {
        NSLog(@"❌ 激活AudioSession失败: %@", error.localizedDescription);
    } else {
        // 验证实际采样率
        double actualSampleRate = audioSession.sampleRate;
        NSLog(@"✅ AudioSession配置成功（MixWithOthers模式）");
        NSLog(@"   首选采样率: 44100 Hz");
        NSLog(@"   实际采样率: %.0f Hz", actualSampleRate);
        
        if (fabs(actualSampleRate - 44100.0) > 1.0) {
            NSLog(@"⚠️ 警告：实际采样率与预期不一致！");
            NSLog(@"   这会导致 BGM 速度错误 (比例: %.2fx)", actualSampleRate / 44100.0);
            NSLog(@"   建议：将所有音频组件改为 %.0f Hz", actualSampleRate);
        }
    }
}

#pragma mark - AudioUnit设置

- (void)setupAudioUnit {
    NSLog(@"🔧 setupAudioUnit 开始");
    
    // 1. 创建AUGraph
    NSLog(@"🔧 1/8: NewAUGraph");
    CheckError(NewAUGraph(&_auGraph), "NewAUGraph");
    
    // 2. 添加RemoteIO节点
    NSLog(@"🔧 2/8: AUGraphAddNode");
    AudioComponentDescription ioDescription;
    ioDescription.componentType = kAudioUnitType_Output;
    ioDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    ioDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    ioDescription.componentFlags = 0;
    ioDescription.componentFlagsMask = 0;
    
    CheckError(AUGraphAddNode(_auGraph, &ioDescription, &_remoteIONode), "AUGraphAddNode");
    
    // 3. 打开AUGraph
    NSLog(@"🔧 3/8: AUGraphOpen");
    CheckError(AUGraphOpen(_auGraph), "AUGraphOpen");
    
    // 4. 获取RemoteIO Unit
    NSLog(@"🔧 4/8: AUGraphNodeInfo");
    CheckError(AUGraphNodeInfo(_auGraph, _remoteIONode, NULL, &_remoteIOUnit), "AUGraphNodeInfo");
    
    // 5. 启用录音（Input）
    NSLog(@"🔧 5/8: Enable Input");
    UInt32 enableIO = 1;
    CheckError(AudioUnitSetProperty(_remoteIOUnit,
                                   kAudioOutputUnitProperty_EnableIO,
                                   kAudioUnitScope_Input,
                                   kInputBus,
                                   &enableIO,
                                   sizeof(enableIO)),
              "Enable input");
    
    // 6. 启用播放（Output）
    NSLog(@"🔧 6/8: Enable Output");
    CheckError(AudioUnitSetProperty(_remoteIOUnit,
                                   kAudioOutputUnitProperty_EnableIO,
                                   kAudioUnitScope_Output,
                                   kOutputBus,
                                   &enableIO,
                                   sizeof(enableIO)),
              "Enable output");
    
    // 7. 设置音频格式
    NSLog(@"🔧 7/8: Set Audio Format");
    
    // 🔧 动态获取系统实际采样率
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    double actualSampleRate = audioSession.sampleRate;
    
    // 如果系统采样率不是 44.1k，使用系统采样率
    double targetSampleRate = 44100.0;
    if (fabs(actualSampleRate - 44100.0) > 1.0) {
        NSLog(@"⚠️ 系统不支持 44.1kHz，使用系统采样率: %.0f Hz", actualSampleRate);
        targetSampleRate = actualSampleRate;
    }
    
    AudioStreamBasicDescription audioFormat;
    audioFormat.mSampleRate = targetSampleRate;
    audioFormat.mFormatID = kAudioFormatLinearPCM;
    audioFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    audioFormat.mFramesPerPacket = 1;
    audioFormat.mChannelsPerFrame = 1;
    audioFormat.mBitsPerChannel = 16;
    audioFormat.mBytesPerPacket = 2;
    audioFormat.mBytesPerFrame = 2;
    
    NSLog(@"   使用采样率: %.0f Hz", targetSampleRate);
    
    // 设置输入格式
    CheckError(AudioUnitSetProperty(_remoteIOUnit,
                                   kAudioUnitProperty_StreamFormat,
                                   kAudioUnitScope_Output,
                                   kInputBus,
                                   &audioFormat,
                                   sizeof(audioFormat)),
              "Set input format");
    
    // 设置输出格式
    CheckError(AudioUnitSetProperty(_remoteIOUnit,
                                   kAudioUnitProperty_StreamFormat,
                                   kAudioUnitScope_Input,
                                   kOutputBus,
                                   &audioFormat,
                                   sizeof(audioFormat)),
              "Set output format");
    
    // 8. 设置输入回调（用于耳返，从输入获取数据并输出）
    NSLog(@"🔧 8/8: Set Render Callback");
    // 注意：这个回调实际上是输出回调，会自动从输入获取数据
    AURenderCallbackStruct renderCallback;
    renderCallback.inputProc = RenderCallback;
    renderCallback.inputProcRefCon = (__bridge void *)self;
    
    CheckError(AUGraphSetNodeInputCallback(_auGraph,
                                          _remoteIONode,
                                          kOutputBus,
                                          &renderCallback),
              "Set render callback");
    
    // 10. 初始化AUGraph
    NSLog(@"🔧 Initialize AUGraph");
    CheckError(AUGraphInitialize(_auGraph), "AUGraphInitialize");
    
    NSLog(@"✅ AudioUnit设置完成");
}

#pragma mark - AudioUnit回调函数

// 渲染回调（统一处理耳返和录音）
// 注意：这个回调由AUGraphSetNodeInputCallback触发，用于处理输出数据
// 它会自动从麦克风输入获取数据，然后输出到扬声器（耳返）
static OSStatus RenderCallback(void *inRefCon,
                               AudioUnitRenderActionFlags *ioActionFlags,
                               const AudioTimeStamp *inTimeStamp,
                               UInt32 inBusNumber,
                               UInt32 inNumberFrames,
                               AudioBufferList *ioData) {
    KaraokeAudioEngine *engine = (__bridge KaraokeAudioEngine *)inRefCon;
    
    // 创建独立的输入缓冲区，避免输入输出循环
    AudioBufferList inputBufferList;
    inputBufferList.mNumberBuffers = 1;
    inputBufferList.mBuffers[0].mNumberChannels = 1;
    inputBufferList.mBuffers[0].mDataByteSize = inNumberFrames * sizeof(SInt16);
    SInt16 *inputBuffer = (SInt16 *)malloc(inputBufferList.mBuffers[0].mDataByteSize);
    inputBufferList.mBuffers[0].mData = inputBuffer;
    
    if (!inputBuffer) {
        NSLog(@"❌ 无法分配输入缓冲区");
        return noErr;
    }
    
    // 1. 从麦克风输入获取数据到独立缓冲区
    OSStatus status = AudioUnitRender(engine->_remoteIOUnit,
                                     ioActionFlags,
                                     inTimeStamp,
                                     kInputBus,  // 从输入总线获取麦克风数据
                                     inNumberFrames,
                                     &inputBufferList);
    
    if (status != noErr) {
        NSLog(@"❌ RenderCallback AudioUnitRender error: %d", (int)status);
        free(inputBuffer);
        return status;
    }
    
    // 2. 获取麦克风音频数据
    UInt32 sampleCount = inputBufferList.mBuffers[0].mDataByteSize / sizeof(SInt16);
    
    // 3. 🆕 如果正在录音且未暂停，写入当前段落的内存缓冲区
    if (engine.isRecording && !engine.isRecordingPaused && engine.currentSegment) {
        // 使用预分配的混音缓冲区（避免 malloc/free）
        SInt16 *mixedSamples = engine->_mixBuffer;
        
        // 检查缓冲区大小是否足够
        if (sampleCount <= engine->_mixBufferSize && mixedSamples) {
            // 复制麦克风数据并应用音量（使用 memcpy + 就地修改，更快）
            memcpy(mixedSamples, inputBuffer, sampleCount * sizeof(SInt16));
            
            // 应用麦克风音量
            float micVol = engine.microphoneVolume;
            if (micVol != 1.0f) {  // 优化：只在非 100% 时才计算
                for (UInt32 i = 0; i < sampleCount; i++) {
                    mixedSamples[i] = (SInt16)(mixedSamples[i] * micVol);
                }
            }
            
            // 🔧 Bug修复：保存原始人声数据（应用音量但未应用音效）
            // 这样预览时可以重新应用不同的音效
            NSData *vocalChunkData = [NSData dataWithBytes:mixedSamples length:sampleCount * sizeof(SInt16)];
            [engine.currentSegment.vocalData appendData:vocalChunkData];
            
            // 应用音效处理（在混合BGM之前，仅用于录音文件）
            if (engine.voiceEffectProcessor) {
                [engine.voiceEffectProcessor processAudioBuffer:mixedSamples sampleCount:sampleCount];
            }
            
            // 如果有BGM，混入BGM数据（仅用于录音文件）
            if (engine.bgmPCMData && engine.bgmPCMDataLength > 0) {
                [engine mixBGMIntoBuffer:mixedSamples sampleCount:sampleCount];
            }
            
            // ✅ 写入当前段落的混合音频缓冲区（带音效+BGM，用于兼容旧逻辑）
            NSData *mixedChunkData = [NSData dataWithBytes:mixedSamples length:sampleCount * sizeof(SInt16)];
            [engine.currentSegment.audioData appendData:mixedChunkData];
        } else {
            NSLog(@"⚠️ 混音缓冲区太小: 需要 %u, 可用 %u", sampleCount, engine->_mixBufferSize);
        }
    }
    
    // 4. 处理耳返输出（应用音效后输出人声，不含BGM）
    if (engine.enableEarReturn && ioData) {
        // 创建耳返缓冲区（应用音效）
        SInt16 *earReturnBuffer = (SInt16 *)malloc(sampleCount * sizeof(SInt16));
        if (earReturnBuffer) {
            // 复制麦克风数据
            memcpy(earReturnBuffer, inputBuffer, sampleCount * sizeof(SInt16));
            
            // 应用麦克风音量
            float micVol = engine.microphoneVolume;
            if (micVol != 1.0f) {
                for (UInt32 i = 0; i < sampleCount; i++) {
                    earReturnBuffer[i] = (SInt16)(earReturnBuffer[i] * micVol);
                }
            }
            
            // 🎵 关键修复：对耳返也应用音效处理
            if (engine.voiceEffectProcessor) {
                [engine.voiceEffectProcessor processAudioBuffer:earReturnBuffer sampleCount:sampleCount];
            }
            
            // 输出到耳返（应用耳返音量）
            float earVolume = engine.earReturnVolume;
            for (int i = 0; i < ioData->mNumberBuffers; i++) {
                SInt16 *samples = (SInt16 *)ioData->mBuffers[i].mData;
                UInt32 bufferSampleCount = ioData->mBuffers[i].mDataByteSize / sizeof(SInt16);
                UInt32 copyCount = MIN(sampleCount, bufferSampleCount);
                
                // 输出带音效的人声
                for (UInt32 j = 0; j < copyCount; j++) {
                    samples[j] = (SInt16)(earReturnBuffer[j] * earVolume);
                }
            }
            
            free(earReturnBuffer);
        }
    } else {
        // 如果耳返关闭，静音输出（但仍然录音）
        for (int i = 0; i < ioData->mNumberBuffers; i++) {
            memset(ioData->mBuffers[i].mData, 0, ioData->mBuffers[i].mDataByteSize);
        }
    }
    
    // 5. 计算音量电平（用于VU表）- 使用原始麦克风数据
    // 节流：每 5 次回调才更新一次（约 25-50ms 更新一次，足够流畅）
    engine->_vuUpdateCounter++;
    if (engine->_vuUpdateCounter >= 5) {
        engine->_vuUpdateCounter = 0;
        
        float sum = 0;
        float peak = 0;
        
        for (UInt32 i = 0; i < sampleCount; i++) {
            float sample = abs(inputBuffer[i]) / 32768.0f;
            sum += sample;
            if (sample > peak) {
                peak = sample;
            }
        }
        
        float avgLevel = sum / sampleCount;
        
        // 通知代理更新VU表（已经节流，减少主线程压力）
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([engine.delegate respondsToSelector:@selector(audioEngineDidUpdateMicrophoneLevel:)]) {
                [engine.delegate audioEngineDidUpdateMicrophoneLevel:avgLevel];
            }
            if ([engine.delegate respondsToSelector:@selector(audioEngineDidUpdatePeakLevel:)]) {
                [engine.delegate audioEngineDidUpdatePeakLevel:peak];
            }
        });
    }
    
    // 释放输入缓冲区（mixedSamples 是预分配的，不需要释放）
    free(inputBuffer);
    
    return noErr;
}

#pragma mark - BGM混音辅助方法

// 将BGM数据混入缓冲区 - 优化版本
- (void)mixBGMIntoBuffer:(SInt16 *)buffer sampleCount:(UInt32)sampleCount {
    if (!self.bgmPCMData || self.bgmPCMDataLength == 0) {
        return;
    }
    
    const SInt16 *bgmSamples = (const SInt16 *)self.bgmPCMData.bytes;
    NSUInteger currentPos = self.bgmReadPosition;  // 读取一次，避免多次原子操作
    NSUInteger bgmLength = self.bgmPCMDataLength;
    float volume = self.bgmVolume;
    
    // 🐛 详细调试日志（降低频率，避免阻塞）
    static int callCount = 0;
    
    if (callCount++ % 200 == 0) {  // 每 200 次打印一次（约 1 秒）
        // 获取系统采样率用于计算时长
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        double systemSampleRate = audioSession.sampleRate;
        
        NSTimeInterval currentTime = (NSTimeInterval)currentPos / systemSampleRate;
        NSTimeInterval totalTime = (NSTimeInterval)bgmLength / systemSampleRate;
        NSLog(@"🎵 混音详情: pos=%lu/%lu, 时间=%.2f/%.2f秒, samples=%u, 进度=%.1f%%", 
              (unsigned long)currentPos, 
              (unsigned long)bgmLength,
              currentTime,
              totalTime,
              sampleCount,
              (currentPos * 100.0 / bgmLength));
    }
    
    // 检查是否已经超出范围
    if (currentPos >= bgmLength) {
        NSLog(@"⚠️ BGM已到达末尾，停止混音");
        return;
    }
    
    // 批量处理，减少边界检查
    UInt32 processed = 0;
    
    while (processed < sampleCount) {
        // 检查是否到达BGM末尾
        if (currentPos >= bgmLength) {
            NSLog(@"⚠️ BGM到达末尾: pos=%lu, length=%lu", (unsigned long)currentPos, (unsigned long)bgmLength);
            if (self.shouldLoopBGM) {
                // 循环播放：重置到开头
                currentPos = 0;
                NSLog(@"🔄 BGM循环到开头");
            } else {
                // 不循环：停止混音，剩余部分填充静音
                NSLog(@"🛑 BGM结束，剩余 %u 样本填充静音", sampleCount - processed);
                // 剩余部分不再混音（保持原有人声）
                break;
            }
        }
        
        // 计算可以连续处理的样本数（到BGM结束或到请求结束）
        UInt32 remainingInBGM = (UInt32)(bgmLength - currentPos);
        UInt32 remainingInBuffer = sampleCount - processed;
        UInt32 batchSize = MIN(remainingInBGM, remainingInBuffer);
        
        // 批量混音（减少循环开销）
        for (UInt32 i = 0; i < batchSize; i++) {
            SInt16 bgmSample = bgmSamples[currentPos + i];
            SInt16 vocalSample = buffer[processed + i];
            
            // 🎛️ 智能混音：预测溢出并动态调整
            // 🔊 录音增益：BGM 额外增加 1.5 倍，让录音中的 BGM 更响亮
            float recordingGain = 1.5f;  // 可调节：1.0-2.0 之间
            int32_t bgmValue = (int32_t)(bgmSample * volume * recordingGain);
            int32_t mixed = (int32_t)vocalSample + bgmValue;
            
            // 软削波：如果接近溢出，按比例压缩
            if (mixed > 32767 || mixed < -32768) {
                // 计算压缩比例（保留 90% 动态范围，避免硬削波）
                float compressionRatio = 29490.0f / fabs(mixed);  // 29490 = 32767 * 0.9
                mixed = (int32_t)(mixed * compressionRatio);
            }
            
            buffer[processed + i] = (SInt16)mixed;
        }
        
        currentPos += batchSize;
        processed += batchSize;
    }
    
    // 原子更新读取位置（只更新一次）
    self.bgmReadPosition = currentPos;
}

#pragma mark - 分段录音控制

// 🆕 从当前播放位置开始录音
- (void)startRecording {
    NSTimeInterval currentTime = self.currentPlaybackTime;
    [self startRecordingFromTime:currentTime];
}

// 🆕 从指定时间开始录音
- (void)startRecordingFromTime:(NSTimeInterval)startTime {
    if (self.isRecording && !self.isRecordingPaused) {
        NSLog(@"⚠️ 已在录音中");
        return;
    }
    
    // 如果之前暂停了，先保存暂停前的段落
    if (self.isRecording && self.isRecordingPaused) {
        [self saveCurrentSegment];
    }
    
    // 创建新的录音段落
    RecordingSegment *newSegment = [[RecordingSegment alloc] init];
    newSegment.startTime = startTime;
    newSegment.isRecorded = YES;  // 标记为录制段落（有人声）
    
    // 🆕 保存当前录制参数
    newSegment.appliedEffect = self.voiceEffectProcessor.effectType;
    newSegment.appliedMicVolume = self.microphoneVolume;
    
    self.currentSegment = newSegment;
    self.currentSegmentStartTime = startTime;
    self.isRecordingPaused = NO;
    
    // 如果AUGraph未启动，启动它
    Boolean isRunning = false;
    AUGraphIsRunning(self.auGraph, &isRunning);
    if (!isRunning) {
        CheckError(AUGraphStart(self.auGraph), "AUGraphStart");
    }
    
    self.isRecording = YES;
    
    NSLog(@"🎤 开始录音（从 %.2f 秒开始）", startTime);
}

// 🆕 暂停录音（BGM继续播放，但不写入人声）
- (void)pauseRecording {
    if (!self.isRecording || self.isRecordingPaused) {
        return;
    }
    
    // 保存当前段落
    [self saveCurrentSegment];
    
    self.isRecordingPaused = YES;
    NSLog(@"⏸️ 录音已暂停（BGM继续播放）");
}

// 🆕 恢复录音
- (void)resumeRecording {
    if (!self.isRecording || !self.isRecordingPaused) {
        return;
    }
    
    // 从当前播放位置重新开始录音
    NSTimeInterval currentTime = self.currentPlaybackTime;
    
    // 创建新段落
    RecordingSegment *newSegment = [[RecordingSegment alloc] init];
    newSegment.startTime = currentTime;
    newSegment.isRecorded = YES;
    
    // 🔧 Bug修复：设置当前录制参数
    newSegment.appliedEffect = self.voiceEffectProcessor.effectType;
    newSegment.appliedMicVolume = self.microphoneVolume;
    
    self.currentSegment = newSegment;
    self.currentSegmentStartTime = currentTime;
    self.isRecordingPaused = NO;
    
    NSLog(@"▶️ 录音已恢复（从 %.2f 秒开始）", currentTime);
}

// 🆕 停止当前段落的录音
- (void)stopRecording {
    if (!self.isRecording) {
        return;
    }
    
    NSLog(@"🛑 停止当前段落录音");
    
    // 保存当前段落
    [self saveCurrentSegment];
    
    // 停止录音状态（但不停止播放）
    self.isRecording = NO;
    self.isRecordingPaused = NO;
    self.currentSegment = nil;
    
    NSLog(@"✅ 当前段落已保存，共 %lu 个段落", (unsigned long)self.recordingSegments.count);
}

// 🆕 完成所有录音，合成最终文件
- (void)finishRecording {
    if (self.isRecording) {
        [self stopRecording];
    }
    
    if (self.recordingSegmentsInternal.count == 0) {
        NSLog(@"⚠️ 没有录音段落");
        return;
    }
    
    NSLog(@"🎬 开始合成最终录音文件...");
    
    // 1. 停止BGM播放
    if (self.isPlaying) {
        [self stop];
        NSLog(@"🛑 BGM播放已停止");
    }
    
    // 2. 停止AUGraph
    CheckError(AUGraphStop(self.auGraph), "AUGraphStop");
    usleep(100 * 1000);  // 100ms 延迟
    
    // 3. 合成所有段落
    [self synthesizeFinalRecording];
    
    NSLog(@"✅ 录音完成: %@", self.recordingFilePath);
}

// 保存当前段落
- (void)saveCurrentSegment {
    if (!self.currentSegment) {
        return;
    }
    
    // 计算段落时长
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    double systemSampleRate = audioSession.sampleRate;
    NSUInteger sampleCount = self.currentSegment.audioData.length / sizeof(SInt16);
    self.currentSegment.duration = (NSTimeInterval)sampleCount / systemSampleRate;
    
    // 添加到段落数组
    [self.recordingSegmentsInternal addObject:self.currentSegment];
    
    NSLog(@"💾 段落已保存: %.2f~%.2fs (%.2fMB, %@)",
          self.currentSegment.startTime,
          self.currentSegment.startTime + self.currentSegment.duration,
          self.currentSegment.audioData.length / (1024.0 * 1024.0),
          self.currentSegment.isRecorded ? @"录制" : @"BGM");
    
    // 通知代理
    [self notifySegmentsUpdate];
    
    self.currentSegment = nil;
}

#pragma mark - 段落管理

// 🆕 跳转到指定时间（跳过的部分填充纯BGM）
- (void)jumpToTime:(NSTimeInterval)targetTime {
    NSTimeInterval currentTime = self.currentPlaybackTime;
    
    if (targetTime <= currentTime) {
        NSLog(@"⚠️ 目标时间 %.2f 小于等于当前时间 %.2f，请使用rewindToTime", targetTime, currentTime);
        return;
    }
    
    // 如果正在录音，先暂停当前段落
    if (self.isRecording && !self.isRecordingPaused) {
        [self saveCurrentSegment];
        self.isRecordingPaused = YES;
    }
    
    // 跳转播放位置
    if (self.audioPlayer) {
        self.audioPlayer.currentTime = targetTime;
    }
    
    // 更新BGM读取位置
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    double systemSampleRate = audioSession.sampleRate;
    self.bgmReadPosition = (NSUInteger)(targetTime * systemSampleRate);
    
    NSLog(@"⏭️ 跳转到 %.2f 秒（跳过 %.2f 秒）", targetTime, targetTime - currentTime);
    
    // 如果正在录音模式，恢复录音
    if (self.isRecording && self.isRecordingPaused) {
        [self resumeRecording];
    }
}

// 🆕 回退到指定时间（删除之后的所有段落）
- (void)rewindToTime:(NSTimeInterval)targetTime {
    NSLog(@"⏪ 回退到 %.2f 秒", targetTime);
    
    // 如果正在录音，先停止当前段落
    if (self.isRecording && self.currentSegment) {
        self.currentSegment = nil;  // 丢弃当前段落（不保存）
    }
    
    // 删除目标时间之后的所有段落
    NSMutableArray *segmentsToKeep = [NSMutableArray array];
    for (RecordingSegment *segment in self.recordingSegmentsInternal) {
        if (segment.startTime < targetTime) {
            // 如果段落跨越目标时间，需要截断
            if (segment.startTime + segment.duration > targetTime) {
                NSTimeInterval newDuration = targetTime - segment.startTime;
                AVAudioSession *audioSession = [AVAudioSession sharedInstance];
                double systemSampleRate = audioSession.sampleRate;
                NSUInteger newSampleCount = (NSUInteger)(newDuration * systemSampleRate);
                NSUInteger newByteLength = newSampleCount * sizeof(SInt16);
                
                if (newByteLength < segment.audioData.length) {
                    [segment.audioData setLength:newByteLength];
                    segment.duration = newDuration;
                    NSLog(@"✂️ 截断段落: %.2f~%.2fs", segment.startTime, targetTime);
                }
            }
            [segmentsToKeep addObject:segment];
        } else {
            NSLog(@"🗑️ 删除段落: %@", segment);
        }
    }
    
    self.recordingSegmentsInternal = segmentsToKeep;
    
    // 跳转播放位置
    if (self.audioPlayer) {
        self.audioPlayer.currentTime = targetTime;
    }
    
    // 更新BGM读取位置
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    double systemSampleRate = audioSession.sampleRate;
    self.bgmReadPosition = (NSUInteger)(targetTime * systemSampleRate);
    
    // 通知代理
    [self notifySegmentsUpdate];
    
    NSLog(@"✅ 回退完成，剩余 %lu 个段落", (unsigned long)self.recordingSegments.count);
}

// 🆕 删除指定段落
- (void)deleteSegmentAtIndex:(NSInteger)index {
    if (index < 0 || index >= self.recordingSegmentsInternal.count) {
        NSLog(@"⚠️ 段落索引 %ld 超出范围", (long)index);
        return;
    }
    
    RecordingSegment *segment = self.recordingSegmentsInternal[index];
    NSLog(@"🗑️ 删除段落 %ld: %@", (long)index, segment);
    
    [self.recordingSegmentsInternal removeObjectAtIndex:index];
    
    // 通知代理
    [self notifySegmentsUpdate];
}

// 🆕 清空所有段落
- (void)clearAllSegments {
    NSLog(@"🗑️ 清空所有段落（共 %lu 个）", (unsigned long)self.recordingSegmentsInternal.count);
    [self.recordingSegmentsInternal removeAllObjects];
    self.currentSegment = nil;
    
    // 通知代理
    [self notifySegmentsUpdate];
}

// 🆕 获取已录制的总时长
- (NSTimeInterval)getTotalRecordedDuration {
    NSTimeInterval total = 0.0;
    for (RecordingSegment *segment in self.recordingSegmentsInternal) {
        if (segment.isRecorded) {
            total += segment.duration;
        }
    }
    return total;
}

// 通知代理段落已更新
- (void)notifySegmentsUpdate {
    if ([self.delegate respondsToSelector:@selector(audioEngineDidUpdateRecordingSegments:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate audioEngineDidUpdateRecordingSegments:[self.recordingSegments copy]];
        });
    }
}

- (NSString *)getRecordingFilePath {
    return self.recordingFilePath;
}

#pragma mark - 音频合成

#pragma mark - 🆕 预览和试听

// 🆕 预览合成（不保存文件，返回音频数据）
- (NSData *)previewSynthesizedAudio {
    // 🔧 检查缓存
    if (self.previewAudioData) {
        NSLog(@"✅ 使用缓存的预览数据（参数未改变）");
        return self.previewAudioData;
    }
    
    // 🔧 使用当前实际参数重新生成
    // BGM音量从audioPlayer读取（用户可能已调整）
    float currentBGMVolume = self.audioPlayer ? self.audioPlayer.volume : self.bgmVolume;
    
    NSLog(@"📊 当前预览参数:");
    NSLog(@"   BGM音量: %.0f%% (audioPlayer.volume)", currentBGMVolume * 100);
    NSLog(@"   麦克风音量: %.0f%%", self.microphoneVolume * 100);
    NSLog(@"   音效: %@", [VoiceEffectProcessor nameForEffectType:self.voiceEffectProcessor.effectType]);
    
    return [self previewSynthesizedAudioWithBGMVolume:currentBGMVolume 
                                            micVolume:self.microphoneVolume 
                                               effect:self.voiceEffectProcessor.effectType];
}

// 🆕 使用指定参数预览（核心方法）
- (NSData *)previewSynthesizedAudioWithBGMVolume:(float)bgmVolume 
                                       micVolume:(float)micVolume 
                                          effect:(VoiceEffectType)effectType {
    if (self.recordingSegmentsInternal.count == 0) {
        NSLog(@"⚠️ 没有录音段落可预览");
        return nil;
    }
    
    NSLog(@"🎬 开始生成预览音频（%lu 个段落）...", (unsigned long)self.recordingSegmentsInternal.count);
    NSLog(@"   参数: BGM=%.0f%%, 麦克风=%.0f%%, 音效=%@", 
          bgmVolume * 100, micVolume * 100, 
          [VoiceEffectProcessor nameForEffectType:effectType]);
    
    // 动态合成（使用新参数）
    NSData *synthesizedData = [self synthesizeAudioDataWithBGMVolume:bgmVolume 
                                                           micVolume:micVolume 
                                                              effect:effectType];
    
    // 缓存预览数据
    self.previewAudioData = synthesizedData;
    
    NSLog(@"✅ 预览音频生成完成: %.2fMB", synthesizedData.length / (1024.0 * 1024.0));
    
    return synthesizedData;
}

// 🆕 清除预览缓存
- (void)invalidatePreviewCache {
    self.previewAudioData = nil;
    NSLog(@"🗑️ 预览缓存已清除");
}

// 🆕 播放预览音频
- (void)playPreview:(void (^)(NSError *error))completion {
    NSLog(@"🎧 开始播放预览...");
    
    // 停止当前预览
    [self stopPreview];
    
    // 暂停BGM播放
    if (self.isPlaying) {
        [self pause];
        NSLog(@"⏸️ BGM已暂停");
    }
    
    // 停止AUGraph（避免冲突）
    Boolean isRunning = false;
    AUGraphIsRunning(self.auGraph, &isRunning);
    if (isRunning) {
        CheckError(AUGraphStop(self.auGraph), "AUGraphStop for preview");
        NSLog(@"🛑 AUGraph已停止");
    }
    
    // 生成预览音频
    NSData *audioData = [self previewSynthesizedAudio];
    if (!audioData) {
        NSError *error = [NSError errorWithDomain:@"KaraokeAudioEngine" 
                                             code:-1 
                                         userInfo:@{NSLocalizedDescriptionKey: @"无法生成预览音频"}];
        if (completion) completion(error);
        return;
    }
    
    // 保存预览完成回调
    self.previewCompletion = completion;
    
    // 写入临时文件（AVAudioPlayer需要文件）
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"preview_temp.pcm"];
    [audioData writeToFile:tempPath atomically:YES];
    
    // 创建播放器（需要先转换为兼容格式）
    NSError *error = nil;
    
    // 获取系统采样率
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    double sampleRate = audioSession.sampleRate;
    
    // 将PCM数据包装为CAF格式（AVAudioPlayer可以播放）
    NSString *cafPath = [self convertPCMToCAF:audioData sampleRate:sampleRate];
    if (!cafPath) {
        error = [NSError errorWithDomain:@"KaraokeAudioEngine" 
                                    code:-2 
                                userInfo:@{NSLocalizedDescriptionKey: @"音频格式转换失败"}];
        if (completion) completion(error);
        return;
    }
    
    NSURL *url = [NSURL fileURLWithPath:cafPath];
    self.previewPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];
    
    if (error) {
        NSLog(@"❌ 创建预览播放器失败: %@", error);
        if (completion) completion(error);
        return;
    }
    
    self.previewPlayer.delegate = self;
    [self.previewPlayer prepareToPlay];
    
    BOOL success = [self.previewPlayer play];
    if (success) {
        NSLog(@"✅ 预览播放开始（时长: %.2f秒）", self.previewPlayer.duration);
    } else {
        error = [NSError errorWithDomain:@"KaraokeAudioEngine" 
                                    code:-3 
                                userInfo:@{NSLocalizedDescriptionKey: @"播放器启动失败"}];
        if (completion) completion(error);
    }
}

// 🆕 停止预览播放
- (void)stopPreview {
    if (self.previewPlayer && self.previewPlayer.isPlaying) {
        [self.previewPlayer stop];
        NSLog(@"🛑 预览播放已停止");
    }
    self.previewPlayer = nil;
    self.previewCompletion = nil;
}

// 🆕 是否正在播放预览
- (BOOL)isPlayingPreview {
    return self.previewPlayer && self.previewPlayer.isPlaying;
}

// 🆕 实时更新预览参数（播放中生效）
- (void)updatePreviewParametersIfPlaying {
    if (![self isPlayingPreview]) {
        NSLog(@"⚠️ 当前未播放预览，跳过参数更新");
        return;
    }
    
    NSLog(@"🔄 检测到播放中参数改变，准备实时更新...");
    
    // 1. 记住当前播放位置
    NSTimeInterval currentTime = self.previewPlayer.currentTime;
    NSLog(@"📍 当前播放位置: %.2f秒", currentTime);
    
    // 2. 清除旧缓存
    [self invalidatePreviewCache];
    
    // 3. 重新生成音频（使用新参数）
    NSLog(@"🎬 使用新参数重新生成音频...");
    NSData *newAudioData = [self previewSynthesizedAudio];
    if (!newAudioData) {
        NSLog(@"❌ 重新生成失败");
        return;
    }
    
    // 4. 转换为CAF格式
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    double sampleRate = audioSession.sampleRate;
    NSString *newCafPath = [self convertPCMToCAF:newAudioData sampleRate:sampleRate];
    if (!newCafPath) {
        NSLog(@"❌ 格式转换失败");
        return;
    }
    
    // 5. 停止旧播放器
    [self.previewPlayer stop];
    
    // 6. 创建新播放器
    NSError *error = nil;
    NSURL *cafURL = [NSURL fileURLWithPath:newCafPath];
    AVAudioPlayer *newPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:cafURL error:&error];
    if (error || !newPlayer) {
        NSLog(@"❌ 创建新播放器失败: %@", error);
        return;
    }
    
    newPlayer.delegate = self;
    [newPlayer prepareToPlay];
    
    // 7. 跳转到之前的播放位置
    if (currentTime < newPlayer.duration) {
        newPlayer.currentTime = currentTime;
        NSLog(@"📍 恢复播放位置: %.2f秒", currentTime);
    } else {
        NSLog(@"⚠️ 原播放位置超出新音频长度，从头播放");
        newPlayer.currentTime = 0;
    }
    
    // 8. 替换播放器并继续播放
    self.previewPlayer = newPlayer;
    [self.previewPlayer play];
    
    NSLog(@"✅ 参数实时更新完成，继续播放");
}

// 🆕 获取预览播放当前时间
- (NSTimeInterval)currentPreviewTime {
    if (self.previewPlayer) {
        return self.previewPlayer.currentTime;
    }
    return 0;
}

// 🆕 获取预览音频总时长
- (NSTimeInterval)previewDuration {
    if (self.previewPlayer) {
        return self.previewPlayer.duration;
    }
    return 0;
}

// 🆕 保存预览到文件
- (void)savePreviewToFile:(void (^)(NSString *filePath, NSError *error))completion {
    NSLog(@"💾 保存预览到文件...");
    
    NSData *audioData = self.previewAudioData;
    if (!audioData) {
        audioData = [self previewSynthesizedAudio];
    }
    
    if (!audioData) {
        NSError *error = [NSError errorWithDomain:@"KaraokeAudioEngine" 
                                             code:-1 
                                         userInfo:@{NSLocalizedDescriptionKey: @"无法生成音频数据"}];
        if (completion) completion(nil, error);
        return;
    }
    
    // 生成文件路径
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *fileName = [NSString stringWithFormat:@"karaoke_final_%ld.pcm", (long)[[NSDate date] timeIntervalSince1970]];
    NSString *filePath = [documentsDirectory stringByAppendingPathComponent:fileName];
    
    // 保存文件
    BOOL success = [audioData writeToFile:filePath atomically:YES];
    
    if (success) {
        self.recordingFilePath = filePath;
        NSLog(@"✅ 文件保存成功: %@", filePath);
        if (completion) completion(filePath, nil);
    } else {
        NSError *error = [NSError errorWithDomain:@"KaraokeAudioEngine" 
                                             code:-2 
                                         userInfo:@{NSLocalizedDescriptionKey: @"文件写入失败"}];
        NSLog(@"❌ 文件保存失败");
        if (completion) completion(nil, error);
    }
}

// 🆕 合成音频数据（带参数，支持动态调整）
- (NSData *)synthesizeAudioDataWithBGMVolume:(float)bgmVolume 
                                   micVolume:(float)micVolume 
                                      effect:(VoiceEffectType)effectType {
    if (self.recordingSegmentsInternal.count == 0) {
        NSLog(@"⚠️ 没有录音段落可合成");
        return nil;
    }
    
    NSLog(@"🎬 开始合成 %lu 个录音段落...", (unsigned long)self.recordingSegmentsInternal.count);
    
    // 1. 按时间排序段落
    NSArray *sortedSegments = [self.recordingSegmentsInternal sortedArrayUsingComparator:^NSComparisonResult(RecordingSegment *seg1, RecordingSegment *seg2) {
        if (seg1.startTime < seg2.startTime) return NSOrderedAscending;
        if (seg1.startTime > seg2.startTime) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    
    // 2. 创建最终输出缓冲区
    NSMutableData *finalAudio = [NSMutableData data];
    
    // 3. 获取系统采样率
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    double systemSampleRate = audioSession.sampleRate;
    
    // 4. 创建音效处理器（如果需要重新应用音效）
    VoiceEffectProcessor *previewEffectProcessor = nil;
    if (effectType != VoiceEffectTypeNone) {
        previewEffectProcessor = [[VoiceEffectProcessor alloc] initWithSampleRate:systemSampleRate];
        [previewEffectProcessor setPresetEffect:effectType];
        NSLog(@"🎵 预览将应用音效: %@", [VoiceEffectProcessor nameForEffectType:effectType]);
    }
    
    // 5. 逐段处理
    NSTimeInterval currentTime = 0.0;
    NSTimeInterval lastSegmentEndTime = 0.0;
    
    for (RecordingSegment *segment in sortedSegments) {
        
        // 填充段落间的BGM空白
        if (segment.startTime > currentTime) {
            NSTimeInterval gapDuration = segment.startTime - currentTime;
            NSLog(@"🎵 填充纯BGM: %.2f~%.2fs (%.2f秒)", currentTime, segment.startTime, gapDuration);
            
            NSData *bgmGap = [self extractBGMFromTime:currentTime 
                                            duration:gapDuration 
                                          sampleRate:systemSampleRate 
                                              volume:bgmVolume];
            if (bgmGap) {
                [finalAudio appendData:bgmGap];
            }
        }
        
        // 处理录音段落
        if (segment.isRecorded && segment.vocalData.length > 0) {
            NSLog(@"🎤 处理录制段落: %.2f~%.2fs", segment.startTime, segment.startTime + segment.duration);
            
            // 🆕 动态合成：人声 + BGM（使用新参数）
            NSData *mixedSegment = [self remixSegment:segment 
                                          bgmVolume:bgmVolume 
                                          micVolume:micVolume 
                                    effectProcessor:previewEffectProcessor 
                                         sampleRate:systemSampleRate];
            
            if (mixedSegment) {
                [finalAudio appendData:mixedSegment];
            }
        } else {
            // 纯BGM段落
            NSLog(@"🎵 添加纯BGM段落: %.2f~%.2fs", segment.startTime, segment.startTime + segment.duration);
            NSData *bgmSegment = [self extractBGMFromTime:segment.startTime 
                                                duration:segment.duration 
                                              sampleRate:systemSampleRate 
                                                  volume:bgmVolume];
            if (bgmSegment) {
                [finalAudio appendData:bgmSegment];
            }
        }
        
        currentTime = segment.startTime + segment.duration;
        lastSegmentEndTime = currentTime;
    }
    
    NSLog(@"📊 合成统计:");
    NSLog(@"   最后段落结束时间: %.2f秒", lastSegmentEndTime);
    NSLog(@"   BGM总时长: %.2f秒", self.audioPlayer.duration);
    NSLog(@"   合成策略: 只保留已录制部分（%.2f秒）", lastSegmentEndTime);
    
    NSTimeInterval totalDuration = finalAudio.length / sizeof(SInt16) / systemSampleRate;
    NSLog(@"✅ 音频数据合成完成:");
    NSLog(@"   总大小: %.2fMB", finalAudio.length / (1024.0 * 1024.0));
    NSLog(@"   总时长: %.2f秒", totalDuration);
    NSLog(@"   采样率: %.0fHz", systemSampleRate);
    
    return [finalAudio copy];
}

// 🆕 将PCM转换为CAF格式（AVAudioPlayer可播放）
- (NSString *)convertPCMToCAF:(NSData *)pcmData sampleRate:(double)sampleRate {
    NSString *cafPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"preview.caf"];
    
    // 设置音频格式
    AudioStreamBasicDescription asbd = {0};
    asbd.mSampleRate = sampleRate;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    asbd.mBitsPerChannel = 16;
    asbd.mChannelsPerFrame = 1;
    asbd.mBytesPerFrame = 2;
    asbd.mFramesPerPacket = 1;
    asbd.mBytesPerPacket = 2;
    
    // 创建音频文件
    CFURLRef fileURL = (__bridge CFURLRef)[NSURL fileURLWithPath:cafPath];
    AudioFileID audioFile;
    OSStatus status = AudioFileCreateWithURL(fileURL,
                                            kAudioFileCAFType,
                                            &asbd,
                                            kAudioFileFlags_EraseFile,
                                            &audioFile);
    
    if (status != noErr) {
        NSLog(@"❌ 创建CAF文件失败: %d", (int)status);
        return nil;
    }
    
    // 写入PCM数据
    UInt32 bytesToWrite = (UInt32)pcmData.length;
    status = AudioFileWriteBytes(audioFile,
                                false,
                                0,
                                &bytesToWrite,
                                pcmData.bytes);
    
    AudioFileClose(audioFile);
    
    if (status != noErr) {
        NSLog(@"❌ 写入CAF数据失败: %d", (int)status);
        return nil;
    }
    
    NSLog(@"✅ PCM转CAF成功: %@", cafPath);
    return cafPath;
}

// 向后兼容：使用当前参数合成
- (NSData *)synthesizeAudioData {
    return [self synthesizeAudioDataWithBGMVolume:self.bgmVolume 
                                        micVolume:self.microphoneVolume 
                                           effect:self.voiceEffectProcessor.effectType];
}

// 🆕 合成最终录音文件（将所有段落拼接，并填充BGM到跳过的部分）
- (void)synthesizeFinalRecording {
    NSLog(@"💾 开始保存最终文件...");
    
    // 使用共享的合成逻辑
    NSData *finalAudio = [self synthesizeAudioData];
    
    if (!finalAudio) {
        NSLog(@"❌ 合成失败");
        return;
    }
    
    // 保存到文件
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *fileName = [NSString stringWithFormat:@"karaoke_final_%ld.pcm", (long)[[NSDate date] timeIntervalSince1970]];
    self.recordingFilePath = [documentsDirectory stringByAppendingPathComponent:fileName];
    
    BOOL success = [finalAudio writeToFile:self.recordingFilePath atomically:YES];
    
    if (success) {
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        double systemSampleRate = audioSession.sampleRate;
        NSTimeInterval totalDuration = finalAudio.length / sizeof(SInt16) / systemSampleRate;
        NSLog(@"✅ 最终文件保存成功:");
        NSLog(@"   文件路径: %@", self.recordingFilePath);
        NSLog(@"   文件大小: %.2fMB", finalAudio.length / (1024.0 * 1024.0));
        NSLog(@"   文件时长: %.2f秒", totalDuration);
    } else {
        NSLog(@"❌ 文件保存失败: %@", self.recordingFilePath);
    }
}

// 🆕 重新混合段落（使用新参数）
- (NSData *)remixSegment:(RecordingSegment *)segment 
               bgmVolume:(float)bgmVolume 
               micVolume:(float)micVolume 
         effectProcessor:(VoiceEffectProcessor *)effectProcessor 
              sampleRate:(double)sampleRate {
    
    if (!segment.vocalData || segment.vocalData.length == 0) {
        NSLog(@"⚠️ 段落没有人声数据");
        return nil;
    }
    
    // 1. 获取人声数据
    const SInt16 *vocalSamples = (const SInt16 *)segment.vocalData.bytes;
    NSUInteger vocalSampleCount = segment.vocalData.length / sizeof(SInt16);
    
    // 2. 创建输出缓冲区
    NSMutableData *outputData = [NSMutableData dataWithLength:segment.vocalData.length];
    SInt16 *outputSamples = (SInt16 *)outputData.mutableBytes;
    
    // 3. 复制并调整人声音量
    for (NSUInteger i = 0; i < vocalSampleCount; i++) {
        int32_t sample = (int32_t)(vocalSamples[i] * micVolume);
        
        // 防止溢出
        if (sample > 32767) sample = 32767;
        if (sample < -32768) sample = -32768;
        
        outputSamples[i] = (SInt16)sample;
    }
    
    // 4. 🔧 Bug修复：应用音效（vocalData是原始数据，未应用音效）
    if (effectProcessor) {
        if (effectProcessor.effectType != segment.appliedEffect) {
            NSLog(@"   🎵 预览将应用音效: %@（录制时: %@）", 
                  [VoiceEffectProcessor nameForEffectType:effectProcessor.effectType],
                  [VoiceEffectProcessor nameForEffectType:segment.appliedEffect]);
        } else {
            NSLog(@"   🎵 预览将应用音效: %@（与录制时相同）", 
                  [VoiceEffectProcessor nameForEffectType:effectProcessor.effectType]);
        }
        [effectProcessor processAudioBuffer:outputSamples sampleCount:(UInt32)vocalSampleCount];
    } else {
        NSLog(@"   ⚠️ 无音效处理器");
    }
    
    // 5. 混合BGM
    NSData *bgmData = [self extractBGMFromTime:segment.startTime 
                                      duration:segment.duration 
                                    sampleRate:sampleRate 
                                        volume:bgmVolume];
    
    if (bgmData && bgmData.length == outputData.length) {
        const SInt16 *bgmSamples = (const SInt16 *)bgmData.bytes;
        
        for (NSUInteger i = 0; i < vocalSampleCount; i++) {
            int32_t vocalSample = outputSamples[i];
            int32_t bgmSample = bgmSamples[i];
            int32_t mixed = vocalSample + bgmSample;
            
            // 软削波
            if (mixed > 32767 || mixed < -32768) {
                float compressionRatio = 29490.0f / fabs(mixed);
                mixed = (int32_t)(mixed * compressionRatio);
            }
            
            outputSamples[i] = (SInt16)mixed;
        }
    }
    
    return outputData;
}

// 🆕 从BGM中提取指定时间段的数据（带音量参数）
- (NSData *)extractBGMFromTime:(NSTimeInterval)startTime 
                      duration:(NSTimeInterval)duration 
                    sampleRate:(double)sampleRate 
                        volume:(float)volume {
    if (!self.bgmPCMData || self.bgmPCMDataLength == 0) {
        NSLog(@"⚠️ BGM数据为空");
        return nil;
    }
    
    // 计算样本范围
    NSUInteger startSample = (NSUInteger)(startTime * sampleRate);
    NSUInteger sampleCount = (NSUInteger)(duration * sampleRate);
    
    // 边界检查
    if (startSample >= self.bgmPCMDataLength) {
        NSLog(@"⚠️ BGM起始位置超出范围");
        return nil;
    }
    
    // 调整样本数量
    if (startSample + sampleCount > self.bgmPCMDataLength) {
        sampleCount = self.bgmPCMDataLength - startSample;
    }
    
    // 提取并应用音量
    const SInt16 *bgmSamples = (const SInt16 *)self.bgmPCMData.bytes;
    NSMutableData *extractedData = [NSMutableData dataWithLength:sampleCount * sizeof(SInt16)];
    SInt16 *outputSamples = (SInt16 *)extractedData.mutableBytes;
    
    for (NSUInteger i = 0; i < sampleCount; i++) {
        int32_t sample = (int32_t)(bgmSamples[startSample + i] * volume);
        
        // 防止溢出
        if (sample > 32767) sample = 32767;
        if (sample < -32768) sample = -32768;
        
        outputSamples[i] = (SInt16)sample;
    }
    
    return extractedData;
}

// 🆕 从BGM中提取指定时间段的数据（向后兼容，使用当前BGM音量）
- (NSData *)extractBGMFromTime:(NSTimeInterval)startTime duration:(NSTimeInterval)duration sampleRate:(double)sampleRate {
    return [self extractBGMFromTime:startTime duration:duration sampleRate:sampleRate volume:self.bgmVolume];
}


#pragma mark - 音频播放

- (void)loadAudioFile:(NSString *)filePath {
    NSError *error;
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    
    // 1. 加载AVAudioPlayer（用于显示进度和控制）
    self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:fileURL error:&error];
    if (error) {
        NSLog(@"❌ 加载音频文件失败: %@", error.localizedDescription);
        return;
    }
    self.audioPlayer.delegate = self;  // 设置代理以监听播放完成
    [self.audioPlayer prepareToPlay];
    
    // 🔧 应用当前的 BGM 音量设置
    self.audioPlayer.volume = self.bgmVolume;
    
    // 🔧 启用变速播放（虽然我们用rate=1.0，但需要启用才能设置）
    self.audioPlayer.enableRate = YES;
    self.audioPlayer.rate = 1.0;
    
    NSLog(@"🎵 AVAudioPlayer 配置:");
    NSLog(@"   音量: %.0f%%", self.bgmVolume * 100);
    NSLog(@"   时长: %.2f秒", self.audioPlayer.duration);
    NSLog(@"   声道数: %lu", (unsigned long)self.audioPlayer.numberOfChannels);
    NSLog(@"   播放速率: %.2f", self.audioPlayer.rate);
    
    // 2. 将整个BGM文件转换为PCM格式并加载到内存
    NSLog(@"🔄 开始转换BGM文件为PCM...");
    NSData *pcmData = [self convertAudioFileToPCM:filePath];
    
    if (pcmData) {
        // 原子赋值，不需要锁
        self.bgmPCMData = pcmData;
        NSUInteger originalLength = pcmData.length / sizeof(int16_t);
        
        // 获取系统采样率用于计算时长
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        double systemSampleRate = audioSession.sampleRate;
        
        NSLog(@"✅ BGM文件转换成功");
        NSLog(@"   文件大小: %.2f MB", self.bgmPCMData.length / (1024.0 * 1024.0));
        NSLog(@"   样本数: %lu", (unsigned long)originalLength);
        NSLog(@"   转换后时长: %.2f秒", originalLength / systemSampleRate);
        NSLog(@"   AVAudioPlayer 时长: %.2f秒", self.audioPlayer.duration);
        
        // 🆕 直接使用转换后的精确长度（AVAudioFile已经提供了正确的帧数）
        // 不再需要根据AVAudioPlayer校准，因为AVAudioFile的长度是精确的
        self.bgmPCMDataLength = originalLength;
        self.bgmReadPosition = 0;
        
        NSLog(@"📊 最终 BGM 参数:");
        NSLog(@"   样本数: %lu", (unsigned long)self.bgmPCMDataLength);
        NSLog(@"   系统采样率: %.0f Hz", systemSampleRate);
        NSLog(@"   精确时长: %.2f秒", self.bgmPCMDataLength / systemSampleRate);
    } else {
        NSLog(@"❌ BGM文件转换失败");
    }
    
    NSLog(@"✅ 音频文件加载成功: %@", filePath);
}

// 将音频文件转换为PCM格式 (系统采样率, 单声道, 16bit)
// 🔧 优化：使用系统实际采样率，避免速度不匹配
- (NSData *)convertAudioFileToPCM:(NSString *)audioFilePath {
    NSURL *audioURL = [NSURL fileURLWithPath:audioFilePath];
    
    // 打开音频文件
    NSError *error;
    AVAudioFile *audioFile = [[AVAudioFile alloc] initForReading:audioURL error:&error];
    if (error) {
        NSLog(@"❌ 无法打开音频文件: %@", error.localizedDescription);
        return nil;
    }
    
    NSLog(@"📊 音频文件信息:");
    NSLog(@"   格式: %@", audioFile.processingFormat);
    NSLog(@"   采样率: %.0f Hz", audioFile.processingFormat.sampleRate);
    NSLog(@"   声道数: %u", audioFile.processingFormat.channelCount);
    NSLog(@"   帧数: %lld", audioFile.length);
    NSLog(@"   精确时长: %.2f秒", (double)audioFile.length / audioFile.processingFormat.sampleRate);
    
    // 🔧 关键修复：使用系统实际采样率而不是固定44100 Hz
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    double systemSampleRate = audioSession.sampleRate;
    
    NSLog(@"🎵 系统实际采样率: %.0f Hz", systemSampleRate);
    
    // 设置PCM格式 (系统采样率, 单声道, 16bit)
    AVAudioFormat *pcmFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16
                                                                sampleRate:systemSampleRate
                                                                  channels:1
                                                               interleaved:YES];
    
    // 准备输出数据
    NSMutableData *pcmData = [NSMutableData data];
    AVAudioFrameCount frameCapacity = 4096;
    
    // 如果格式不匹配，需要转换
    if (![audioFile.processingFormat isEqual:pcmFormat]) {
        // 创建转换器
        AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:audioFile.processingFormat
                                                                       toFormat:pcmFormat];
        if (!converter) {
            NSLog(@"❌ 无法创建音频转换器");
            return nil;
        }
        
        NSLog(@"🔄 开始格式转换 (%.0f Hz, %uch -> %.0f Hz, 1ch)...", 
              audioFile.processingFormat.sampleRate, 
              audioFile.processingFormat.channelCount,
              systemSampleRate);
        
        // 🔧 计算预期的输出帧数（考虑采样率转换）
        double sampleRateRatio = systemSampleRate / audioFile.processingFormat.sampleRate;
        AVAudioFrameCount expectedOutputFrames = (AVAudioFrameCount)(audioFile.length * sampleRateRatio);
        NSLog(@"   预期输出帧数: %u (转换比率: %.4f)", expectedOutputFrames, sampleRateRatio);
        
        // 读取并转换
        AVAudioFrameCount totalOutputFrames = 0;
        
        while (audioFile.framePosition < audioFile.length) {
            AVAudioPCMBuffer *inputBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:audioFile.processingFormat
                                                                           frameCapacity:frameCapacity];
            
            // 读取音频数据
            [audioFile readIntoBuffer:inputBuffer error:&error];
            if (error || inputBuffer.frameLength == 0) {
                break;
            }
            
            // 🔧 计算输出缓冲区大小（考虑采样率转换，预留更多空间）
            AVAudioFrameCount outputCapacity = (AVAudioFrameCount)(inputBuffer.frameLength * sampleRateRatio * 2.0);
            if (outputCapacity < frameCapacity) {
                outputCapacity = frameCapacity;
            }
            
            // 🔧 关键修复：对于每个输入buffer，可能需要多次转换才能完全消耗
            AVAudioFrameCount inputFramesProcessed = 0;
            
            while (inputFramesProcessed < inputBuffer.frameLength) {
                // 转换为PCM
                AVAudioPCMBuffer *outputBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:pcmFormat
                                                                                frameCapacity:outputCapacity];
                
                // 使用本地变量捕获当前的inputBuffer
                __block AVAudioPCMBuffer *currentInputBuffer = inputBuffer;
                __block BOOL inputProvided = NO;
                
                AVAudioConverterInputBlock inputBlock = ^AVAudioBuffer *(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus *outStatus) {
                    if (!inputProvided && currentInputBuffer.frameLength > 0) {
                        inputProvided = YES;
                        *outStatus = AVAudioConverterInputStatus_HaveData;
                        return currentInputBuffer;
                    } else {
                        *outStatus = AVAudioConverterInputStatus_NoDataNow;
                        return nil;
                    }
                };
                
                AVAudioConverterOutputStatus status = [converter convertToBuffer:outputBuffer
                                                                            error:&error
                                                           withInputFromBlock:inputBlock];
                
                // 🔧 关键修复：无论状态如何，只要有输出数据就保存
                if (outputBuffer.frameLength > 0) {
                    const int16_t *samples = (const int16_t *)outputBuffer.audioBufferList->mBuffers[0].mData;
                    NSUInteger length = outputBuffer.frameLength * sizeof(int16_t);
                    if (samples && length > 0) {
                        [pcmData appendBytes:samples length:length];
                        totalOutputFrames += outputBuffer.frameLength;
                    } else {
                        NSLog(@"⚠️ 输出buffer数据指针为空，状态: %ld", (long)status);
                    }
                }
                
                // 处理不同的转换状态
                if (status == AVAudioConverterOutputStatus_HaveData) {
                    // 还有数据，继续转换这个buffer
                    continue;
                } else if (status == AVAudioConverterOutputStatus_InputRanDry) {
                    // 输入数据已完全消耗，进入下一批
                    inputFramesProcessed = inputBuffer.frameLength;
                    break;
                } else if (status == AVAudioConverterOutputStatus_Error) {
                    NSLog(@"❌ 转换错误: %@", error);
                    inputFramesProcessed = inputBuffer.frameLength;
                    break;
                } else {
                    NSLog(@"⚠️ 未预期的转换状态: %ld", (long)status);
                    inputFramesProcessed = inputBuffer.frameLength;
                    break;
                }
            }
        }
        
        NSLog(@"✅ 转换完成: %u 帧 (预期: %u 帧)", totalOutputFrames, expectedOutputFrames);
    } else {
        // 格式匹配，直接读取
        while (audioFile.framePosition < audioFile.length) {
            AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:pcmFormat
                                                                      frameCapacity:frameCapacity];
            
            [audioFile readIntoBuffer:buffer error:&error];
            if (error || buffer.frameLength == 0) {
                break;
            }
            
            // 追加PCM数据
            const int16_t *samples = (const int16_t *)buffer.audioBufferList->mBuffers[0].mData;
            NSUInteger length = buffer.frameLength * sizeof(int16_t);
            [pcmData appendBytes:samples length:length];
        }
    }
    
    return pcmData;
}

- (void)play {
    [self playFromTime:0.0];
}

// 🆕 从指定时间开始播放
- (void)playFromTime:(NSTimeInterval)startTime {
    if (!self.audioPlayer) {
        NSLog(@"❌ 没有加载音频文件");
        return;
    }
    
    // 获取系统采样率
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    double systemSampleRate = audioSession.sampleRate;
    
    // 设置BGM读取位置
    NSUInteger targetPosition = (NSUInteger)(startTime * systemSampleRate);
    if (targetPosition >= self.bgmPCMDataLength) {
        NSLog(@"⚠️ 起始时间 %.2f 超出BGM长度，重置为0", startTime);
        targetPosition = 0;
        startTime = 0;
    }
    self.bgmReadPosition = targetPosition;
    
    // 设置AVAudioPlayer播放位置
    self.audioPlayer.currentTime = startTime;
    
    // 启用变速播放
    self.audioPlayer.enableRate = YES;
    self.audioPlayer.volume = self.bgmVolume;
    self.audioPlayer.rate = 1.0;  // 正常速度
    
    [self.audioPlayer play];
    self.isPlaying = YES;
    
    NSLog(@"🎵 从 %.2f 秒开始播放 BGM", startTime);
    NSLog(@"   音量: %.0f%%", self.bgmVolume * 100);
    NSLog(@"   BGM读取位置: %lu/%lu", (unsigned long)targetPosition, (unsigned long)self.bgmPCMDataLength);
}

- (void)pause {
    [self.audioPlayer pause];
    self.isPlaying = NO;
    NSLog(@"⏸️ 音频暂停");
}

- (void)stop {
    [self.audioPlayer stop];
    self.audioPlayer.currentTime = 0;
    self.isPlaying = NO;
    NSLog(@"⏹️ 音频停止");
}

- (void)reset {
    NSLog(@"🔄 开始重置 KaraokeAudioEngine...");
    
    // 1. 停止录音（如果正在录音）
    if (self.isRecording) {
        self.currentSegment = nil;  // 丢弃当前段落
        self.isRecording = NO;
        self.isRecordingPaused = NO;
    }
    
    // 2. 停止播放
    if (self.isPlaying) {
        [self stop];
    }
    
    // 3. 重置 BGM 播放器到开头
    if (self.audioPlayer) {
        self.audioPlayer.currentTime = 0;
        NSLog(@"   ✅ BGM播放器已重置到开头");
    }
    
    // 4. 重置 BGM 读取位置（原子操作）
    self.bgmReadPosition = 0;
    NSLog(@"   ✅ BGM读取位置已重置");
    
    // 5. 🆕 清空所有录音段落
    [self.recordingSegmentsInternal removeAllObjects];
    self.currentSegment = nil;
    NSLog(@"   ✅ 录音段落已清空");
    
    // 6. 重置录音文件路径（准备新录音）
    self.recordingFilePath = nil;
    NSLog(@"   ✅ 录音文件路径已清空");
    
    // 7. 通知代理
    [self notifySegmentsUpdate];
    
    NSLog(@"✅ KaraokeAudioEngine 重置完成，可以开始新的录音");
}

#pragma mark - 耳返控制

- (void)setEarReturnEnabled:(BOOL)enabled {
    _enableEarReturn = enabled;
    NSLog(@"🎧 耳返%@", enabled ? @"启用" : @"禁用");
}

- (void)setEarReturnVolume:(float)volume {
    _earReturnVolume = MAX(0.0, MIN(1.0, volume));
    NSLog(@"🎧 耳返音量: %.0f%%", _earReturnVolume * 100);
}

- (void)setMicrophoneVolume:(float)volume {
    _microphoneVolume = MAX(0.0, MIN(1.0, volume));
    NSLog(@"🎤 麦克风音量: %.0f%%", _microphoneVolume * 100);
}

#pragma mark - 音效控制

- (void)setVoiceEffect:(VoiceEffectType)effectType {
    if (self.voiceEffectProcessor) {
        [self.voiceEffectProcessor setPresetEffect:effectType];
    }
}

#pragma mark - 播放进度

// 根据 BGM 读取位置计算当前播放时间
- (NSTimeInterval)currentPlaybackTime {
    if (self.bgmPCMDataLength == 0) {
        return 0.0;
    }
    
    // 🔧 使用系统实际采样率计算时间
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    double systemSampleRate = audioSession.sampleRate;
    
    NSUInteger currentPos = self.bgmReadPosition;
    return (NSTimeInterval)currentPos / systemSampleRate;
}

#pragma mark - AVAudioPlayerDelegate

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    NSLog(@"🎵 BGM播放完成 (成功: %@)", flag ? @"是" : @"否");
    
    // BGM播放完成，自动停止录音（如果正在录音）
    if (self.isRecording) {
        NSLog(@"🎵 BGM播放完成，自动停止录音");
        [self stopRecording];
        
        // 通知代理
        if ([self.delegate respondsToSelector:@selector(audioEngineDidFinishPlaying)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate audioEngineDidFinishPlaying];
            });
        }
    }
    
    self.isPlaying = NO;
}

#pragma mark - 清理

- (void)dealloc {
    [self stopRecording];
    [self stop];
    
    // 清理BGM资源（不需要锁）
    self.bgmPCMData = nil;
    self.bgmAudioFile = nil;
    
    // 🆕 清理录音段落
    [self.recordingSegmentsInternal removeAllObjects];
    self.currentSegment = nil;
    
    // 释放预分配的混音缓冲区
    if (self.mixBuffer) {
        free(self.mixBuffer);
        self.mixBuffer = NULL;
    }
    
    if (self.auGraph) {
        AUGraphStop(self.auGraph);
        AUGraphUninitialize(self.auGraph);
        AUGraphClose(self.auGraph);
        DisposeAUGraph(self.auGraph);
    }
    
    NSLog(@"🗑️ KaraokeAudioEngine dealloc");
}

@end
