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

@interface KaraokeAudioEngine ()

// AudioUnit相关
@property (nonatomic, assign) AUGraph auGraph;
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

// 录音相关
@property (nonatomic, assign) FILE *recordFile;
@property (nonatomic, copy) NSString *recordingFilePath;
@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, assign) BOOL isPlaying;

// 混音缓冲区（预分配，避免实时 malloc/free）
@property (nonatomic, assign) SInt16 *mixBuffer;
@property (nonatomic, assign) UInt32 mixBufferSize;

// VU表更新节流（避免过于频繁的主线程调度）
@property (nonatomic, assign) int vuUpdateCounter;

// 耳返控制（重新声明为readwrite）
@property (nonatomic, assign, readwrite) BOOL enableEarReturn;
@property (nonatomic, assign, readwrite) float earReturnVolume;
@property (nonatomic, assign, readwrite) float microphoneVolume;

@end

@implementation KaraokeAudioEngine

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
        
        NSLog(@"🔧 Step 2: setupAudioUnit");
        [self setupAudioUnit];
        
        NSLog(@"✅ KaraokeAudioEngine初始化完成（AudioUnit实现，性能优化）");
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
    
    // 3. 如果正在录音，需要将麦克风和BGM混合后写入文件
    if (engine.isRecording && engine->_recordFile) {
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
            
            // 如果有BGM，混入BGM数据（仅用于录音文件）
            if (engine.bgmPCMData && engine.bgmPCMDataLength > 0) {
                [engine mixBGMIntoBuffer:mixedSamples sampleCount:sampleCount];
            }
            
            // 写入录音文件（包含人声+BGM）
            fwrite(mixedSamples, sizeof(SInt16), sampleCount, engine->_recordFile);
        } else {
            NSLog(@"⚠️ 混音缓冲区太小: 需要 %u, 可用 %u", sampleCount, engine->_mixBufferSize);
        }
    }
    
    // 4. 处理耳返输出（只输出人声，不含BGM）
    if (engine.enableEarReturn && ioData) {
        // 耳返只返回人声，BGM 由 AVAudioPlayer 独立播放
        float volume = engine.earReturnVolume * engine.microphoneVolume;
        
        for (int i = 0; i < ioData->mNumberBuffers; i++) {
            SInt16 *samples = (SInt16 *)ioData->mBuffers[i].mData;
            UInt32 bufferSampleCount = ioData->mBuffers[i].mDataByteSize / sizeof(SInt16);
            UInt32 copyCount = MIN(sampleCount, bufferSampleCount);
            
            // 只输出人声（来自麦克风）
            for (UInt32 j = 0; j < copyCount; j++) {
                samples[j] = (SInt16)(inputBuffer[j] * volume);
            }
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

#pragma mark - 录音控制

- (void)startRecording {
    if (self.isRecording) {
        NSLog(@"⚠️ 已在录音中");
        return;
    }
    
    // 创建录音文件
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *fileName = [NSString stringWithFormat:@"karaoke_recording_%ld.pcm", (long)[[NSDate date] timeIntervalSince1970]];
    self.recordingFilePath = [documentsDirectory stringByAppendingPathComponent:fileName];
    
    self.recordFile = fopen([self.recordingFilePath UTF8String], "wb");
    if (!self.recordFile) {
        NSLog(@"❌ 无法创建录音文件");
        return;
    }
    
    // 启动AUGraph
    CheckError(AUGraphStart(self.auGraph), "AUGraphStart");
    
    self.isRecording = YES;
    NSLog(@"🎤 开始录音: %@", self.recordingFilePath);
}

- (void)stopRecording {
    if (!self.isRecording) {
        return;
    }
    
    NSLog(@"🛑 开始停止录音...");
    
    // 1. 先停止AUGraph，停止产生新的音频回调
    CheckError(AUGraphStop(self.auGraph), "AUGraphStop");
    NSLog(@"✅ AUGraph已停止");
    
    // 2. 短暂延迟，让最后的回调完成（约50-100ms）
    usleep(100 * 1000);  // 100ms
    
    // 3. 设置录音标志为NO
    self.isRecording = NO;
    
    // 4. 安全关闭录音文件
    if (self.recordFile) {
        fflush(self.recordFile);  // 确保所有缓冲数据都写入磁盘
        fclose(self.recordFile);
        self.recordFile = NULL;
        NSLog(@"✅ 录音文件已关闭并刷新到磁盘");
    }
    
    NSLog(@"🛑 录音停止: %@", self.recordingFilePath);
}

- (NSString *)getRecordingFilePath {
    return self.recordingFilePath;
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
    if (!self.audioPlayer) {
        NSLog(@"❌ 没有加载音频文件");
        return;
    }
    
    // 重置BGM读取位置到文件开头（原子操作，不需要锁）
    self.bgmReadPosition = 0;
    
    // ✅ 新架构：BGM 独立播放，不通过混音
    // - AVAudioPlayer 正常播放 BGM（用户可以听到）
    // - 耳返只返回人声（不含 BGM）
    // - 录音时实时混合人声+BGM
    
    // 🔧 关键修复：调整AVAudioPlayer的播放速率以匹配系统采样率
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    double systemSampleRate = audioSession.sampleRate;
    
    // 启用变速播放
    self.audioPlayer.enableRate = YES;
    
    // 计算速率：系统采样率 / 原始采样率
    // 例如：系统24000 / 原始48000 = 0.5 (半速)
    // 但AVAudioPlayer.rate是相对于正常播放的速率
    // 我们需要让它以正常速度播放，所以rate = 1.0
    // 问题是：AVAudioPlayer会自动处理采样率转换
    
    // 实际上，AVAudioPlayer应该自动适配系统采样率
    // 如果听起来加速了，可能是因为文件本身的问题
    
    // 设置合适的音量（用户可以通过 bgmVolumeSlider 调节）
    self.audioPlayer.volume = self.bgmVolume;
    self.audioPlayer.rate = 1.0;  // 正常速度
    
    [self.audioPlayer play];
    self.isPlaying = YES;
    
    NSLog(@"🎵 开始播放 BGM");
    NSLog(@"   音量: %.0f%%", self.bgmVolume * 100);
    NSLog(@"   系统采样率: %.0f Hz", systemSampleRate);
    NSLog(@"   播放速率: %.2f", self.audioPlayer.rate);
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
