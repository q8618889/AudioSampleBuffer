//
//  KaraokeAudioEngine.m
//  AudioSampleBuffer
//
//  Created on 2025/10/14.
//  参考：https://blog.csdn.net/weixin_43030741/article/details/103477017
//  使用AudioUnit + AUGraph实现录音和耳返功能
//

#import "KaraokeAudioEngine.h"
#import "DSP/SoundTouch/SoundTouchBridge.h"

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
@property (nonatomic, assign) double actualSampleRate;  // 🔧 实际采样率（从AudioUnit获取）

// 🆕 BGM播放引擎（AVAudioEngine）
@property (nonatomic, strong) AVAudioEngine *bgmEngine;
@property (nonatomic, strong) AVAudioPlayerNode *bgmPlayerNode;
@property (nonatomic, strong) AVAudioUnitTimePitch *bgmTimePitchNode;
@property (nonatomic, strong) AVAudioFile *bgmAudioFile;
@property (nonatomic, assign) NSTimeInterval bgmDuration;  // BGM总时长

// BGM音频文件读取（用于录音混合）
@property (nonatomic, strong) NSData *bgmPCMData;  // 存储完整的BGM PCM数据
@property (nonatomic, assign) NSUInteger bgmPCMDataLength;  // PCM数据长度（样本数）
@property (atomic, assign) NSUInteger bgmReadPosition;  // 当前读取位置（样本索引）- 使用 atomic
@property (nonatomic, assign) BOOL shouldLoopBGM;
@property (nonatomic, assign) double bgmPCMSampleRate;  // 🔧 BGM PCM数据的实际采样率

// 🆕 播放进度追踪
@property (nonatomic, strong) NSTimer *playbackTimer;  // 播放进度定时器
@property (nonatomic, assign) NSTimeInterval lastPlaybackTime;  // 上次记录的播放时间
@property (nonatomic, assign) NSUInteger playbackSessionID;  // 播放会话ID，用于忽略旧的completionHandler

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

// 🔧 回退/跳转标志
@property (nonatomic, assign) BOOL isRewindingOrJumping;  // 标记正在回退/跳转操作

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
        _bgmPitchShift = 0.0;  // 默认原调
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
        
        NSLog(@"🔧 Step 3: setupBGMEngine");
        [self setupBGMEngine];
        
        NSLog(@"✅ KaraokeAudioEngine初始化完成（分段录音模式，支持跳转和回退）");
    }
    return self;
}

#pragma mark - 🎵 BGM引擎设置

- (void)setupBGMEngine {
    NSLog(@"🔧 初始化 BGM 播放引擎...");
    
    // 🔧 预先配置音频会话（兼容 AVAudioEngine + AudioUnit）
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSError *sessionError = nil;
    
    if (![audioSession setCategory:AVAudioSessionCategoryPlayAndRecord 
                       withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionAllowBluetooth
                             error:&sessionError]) {
        NSLog(@"⚠️ 音频会话配置失败: %@", sessionError);
    }
    
    // 1. 创建 AVAudioEngine
    _bgmEngine = [[AVAudioEngine alloc] init];
    _bgmPlayerNode = [[AVAudioPlayerNode alloc] init];
    _bgmTimePitchNode = [[AVAudioUnitTimePitch alloc] init];
    
    // 2. 连接节点
    [_bgmEngine attachNode:_bgmPlayerNode];
    [_bgmEngine attachNode:_bgmTimePitchNode];
    
    AVAudioMixerNode *mainMixer = _bgmEngine.mainMixerNode;
    
    // 音频链路：player → timePitch → mainMixer → 输出
    // 使用 nil format 让系统自动协商格式
    [_bgmEngine connect:_bgmPlayerNode to:_bgmTimePitchNode format:nil];
    [_bgmEngine connect:_bgmTimePitchNode to:mainMixer format:nil];
    
    // 3. 设置默认参数
    _bgmTimePitchNode.pitch = 0.0f;  // 原调（单位：cents）
    _bgmTimePitchNode.rate = 1.0f;   // 原速
    mainMixer.outputVolume = _bgmVolume;
    
    // 4. 启动引擎
    NSError *error = nil;
    if (![_bgmEngine startAndReturnError:&error]) {
        NSLog(@"❌ BGM引擎启动失败: %@", error);
        return;
    }
    
    // 5. 获取实际音频格式
    AVAudioFormat *format = [mainMixer outputFormatForBus:0];
    
    NSLog(@"✅ BGM引擎已启动");
    NSLog(@"   音频链路: PlayerNode → TimePitch → MainMixer → 输出");
    NSLog(@"   格式: %.0f Hz, %u 声道", format.sampleRate, (unsigned int)format.channelCount);
    NSLog(@"   音高: %.0f cents, 速率: %.2fx", _bgmTimePitchNode.pitch, _bgmTimePitchNode.rate);
    NSLog(@"   音量: %.0f%%", mainMixer.outputVolume * 100);
}

#pragma mark - AudioSession初始化

- (void)initAudioSession {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSError *error;
    
    NSLog(@"🔧 开始配置卡拉OK AudioSession...");
    
    // 🔧 关键修复：避免频繁的AudioSession重新配置，减少冲突
    // 检查当前状态，只在必要时重新配置
    
    // 1. 检查当前配置是否已经符合要求
    BOOL needsReconfiguration = NO;
    
    if (![audioSession.category isEqualToString:AVAudioSessionCategoryPlayAndRecord]) {
        needsReconfiguration = YES;
        NSLog(@"📋 需要重新配置：category不匹配");
    }
    
    if (fabs(audioSession.sampleRate - 44100.0) > 1.0) {
        needsReconfiguration = YES;
        NSLog(@"📋 需要重新配置：采样率不匹配 (当前: %.0f Hz)", audioSession.sampleRate);
    }
    
    if (!needsReconfiguration) {
        NSLog(@"✅ AudioSession配置已符合要求，跳过重新配置");
        return;
    }
    
    // 2. 先停用 AudioSession（如果已激活）
    [audioSession setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error];
    if (error) {
        NSLog(@"⚠️ 停用AudioSession失败: %@", error.localizedDescription);
        error = nil;
    } else {
        NSLog(@"✅ AudioSession已停用，准备重新配置");
    }
    
    // 3. 设置采样率（必须在 category 之前）
    [audioSession setPreferredSampleRate:44100.0 error:&error];
    if (error) {
        NSLog(@"⚠️ 设置采样率失败: %@", error.localizedDescription);
        error = nil;
    } else {
        NSLog(@"✅ 设置首选采样率: 44100 Hz");
    }
    
    // 4. 设置为播放和录音模式
    // 🎯 关键修复：添加MixWithOthers选项，避免与其他音频应用冲突
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                  withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker | 
                              AVAudioSessionCategoryOptionAllowBluetooth |
                              AVAudioSessionCategoryOptionMixWithOthers
                        error:&error];
    
    if (error) {
        NSLog(@"❌ 设置AudioSession category失败: %@", error.localizedDescription);
        error = nil;
    } else {
        NSLog(@"✅ 设置为PlayAndRecord模式（支持混音）");
    }
    
    // 5. 再次强制设置采样率（某些设备在 setCategory 后会重置）
    [audioSession setPreferredSampleRate:44100.0 error:&error];
    if (error) {
        NSLog(@"⚠️ 重新设置采样率失败: %@", error.localizedDescription);
        error = nil;
    }
    
    // 6. 设置 IO 缓冲区时长（增加缓冲区减少卡顿）
    [audioSession setPreferredIOBufferDuration:0.01 error:&error];  // 从0.005改为0.01
    if (error) {
        NSLog(@"⚠️ 设置buffer duration失败: %@", error.localizedDescription);
        error = nil;
    }
    
    // 7. 🎯 关键修复：延迟激活 AudioSession，确保配置完全生效
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSError *activationError = nil;
        [audioSession setActive:YES error:&activationError];
        if (activationError) {
            NSLog(@"❌ 激活AudioSession失败: %@", activationError.localizedDescription);
        } else {
            // 验证实际采样率
            double actualSampleRate = audioSession.sampleRate;
            NSLog(@"✅ AudioSession配置成功并已激活");
            NSLog(@"   模式: PlayAndRecord (支持混音)");
            NSLog(@"   首选采样率: 44100 Hz");
            NSLog(@"   实际采样率: %.0f Hz", actualSampleRate);
            NSLog(@"   输出路由: %@", audioSession.currentRoute.outputs.firstObject.portType);
            
            if (fabs(actualSampleRate - 44100.0) > 1.0) {
                NSLog(@"⚠️ 警告：实际采样率与预期不一致！");
                NSLog(@"   这会导致 BGM 速度错误 (比例: %.2fx)", actualSampleRate / 44100.0);
                NSLog(@"   建议：将所有音频组件改为 %.0f Hz", actualSampleRate);
            }
        }
    });
    
    NSLog(@"✅ AudioSession初始化完成");
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
    
    // 🔧 保存实际采样率（从AudioUnit获取）
    AudioStreamBasicDescription actualFormat;
    UInt32 size = sizeof(actualFormat);
    AudioUnitGetProperty(_remoteIOUnit,
                        kAudioUnitProperty_StreamFormat,
                        kAudioUnitScope_Output,
                        1,  // 输入bus
                        &actualFormat,
                        &size);
    self.actualSampleRate = actualFormat.mSampleRate;
    NSLog(@"   🔍 实际采样率已保存: %.0f Hz", self.actualSampleRate);
    
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
    
    // 🔧 修复：使用预分配的缓冲区，避免实时malloc/free
    static SInt16 *staticInputBuffer = NULL;
    static UInt32 staticBufferSize = 0;
    
    // 检查是否需要扩展静态缓冲区
    UInt32 requiredSize = inNumberFrames * sizeof(SInt16);
    if (staticBufferSize < requiredSize) {
        if (staticInputBuffer) {
            free(staticInputBuffer);
        }
        staticInputBuffer = (SInt16 *)malloc(requiredSize);
        staticBufferSize = requiredSize;
        if (!staticInputBuffer) {
            NSLog(@"❌ 无法分配静态输入缓冲区");
            return noErr;
        }
    }
    
    // 创建独立的输入缓冲区，避免输入输出循环
    AudioBufferList inputBufferList;
    inputBufferList.mNumberBuffers = 1;
    inputBufferList.mBuffers[0].mNumberChannels = 1;
    inputBufferList.mBuffers[0].mDataByteSize = requiredSize;
    inputBufferList.mBuffers[0].mData = staticInputBuffer;
    
    // 1. 从麦克风输入获取数据到独立缓冲区
    OSStatus status = AudioUnitRender(engine->_remoteIOUnit,
                                     ioActionFlags,
                                     inTimeStamp,
                                     kInputBus,  // 从输入总线获取麦克风数据
                                     inNumberFrames,
                                     &inputBufferList);
    
    if (status != noErr) {
        NSLog(@"❌ RenderCallback AudioUnitRender error: %d", (int)status);
        return status;
    }
    
    // 2. 获取麦克风音频数据
    UInt32 sampleCount = inputBufferList.mBuffers[0].mDataByteSize / sizeof(SInt16);
    
    // 3. 🆕 如果正在录音且未暂停，写入当前段落的内存缓冲区
    if (engine.isRecording && !engine.isRecordingPaused && engine.currentSegment) {
        // 使用预分配的混音缓冲区（避免 malloc/free）
        SInt16 *mixedSamples = engine->_mixBuffer;
        
        // 🐛 调试日志：每100次回调打印一次（避免日志过多）
        static int recordingCallbackCount = 0;
        static double lastReportedDuration = 0;
        recordingCallbackCount++;
        if (recordingCallbackCount % 100 == 0) {
            // 🔧 关键：检查实际的采样率（从AudioUnit格式）
            AudioStreamBasicDescription actualFormat;
            UInt32 size = sizeof(actualFormat);
            AudioUnitGetProperty(engine->_remoteIOUnit,
                               kAudioUnitProperty_StreamFormat,
                               kAudioUnitScope_Output,
                               1,  // 输入bus
                               &actualFormat,
                               &size);
            double actualSampleRate = actualFormat.mSampleRate;
            double calculatedDuration = (double)(engine.currentSegment.audioData.length / sizeof(SInt16)) / actualSampleRate;
            double timeDelta = calculatedDuration - lastReportedDuration;
            lastReportedDuration = calculatedDuration;
            
            NSLog(@"📊 录音回调 #%d: sampleCount=%u, vocalData=%lu, audioData=%lu", 
                  recordingCallbackCount, 
                  sampleCount,
                  (unsigned long)engine.currentSegment.vocalData.length,
                  (unsigned long)engine.currentSegment.audioData.length);
            NSLog(@"   🔍 采样率: AudioUnit=%.0fHz, AudioSession=%.0fHz", 
                  actualSampleRate, 
                  [AVAudioSession sharedInstance].sampleRate);
            NSLog(@"   ⏱️ 时长: %.2f秒 (增量: %.2f秒)", calculatedDuration, timeDelta);
        }
        
        // 检查缓冲区大小是否足够
        if (sampleCount <= engine->_mixBufferSize && mixedSamples) {
            // 复制麦克风数据并应用音量（使用 memcpy + 就地修改，更快）
            memcpy(mixedSamples, staticInputBuffer, sampleCount * sizeof(SInt16));
            
            // 应用麦克风音量
            float micVol = engine.microphoneVolume;
            if (micVol != 1.0f) {  // 优化：只在非 100% 时才计算
                for (UInt32 i = 0; i < sampleCount; i++) {
                    mixedSamples[i] = (SInt16)(mixedSamples[i] * micVol);
                }
            }
            
            // 🔧 保存原始人声数据（应用音量但未应用音效）
            NSData *vocalChunkData = [NSData dataWithBytes:mixedSamples length:sampleCount * sizeof(SInt16)];
            [engine.currentSegment.vocalData appendData:vocalChunkData];
            
            // 应用音效处理（在混合BGM之前）
            if (engine.voiceEffectProcessor) {
                [engine.voiceEffectProcessor processAudioBuffer:mixedSamples sampleCount:sampleCount];
            }
            
            // ✅ 关键修复：audioData 只保存人声+音效（不含BGM）
            // BGM 会在预览/合成时动态混入，这样可以调整BGM音量
            NSData *processedVocalData = [NSData dataWithBytes:mixedSamples length:sampleCount * sizeof(SInt16)];
            [engine.currentSegment.audioData appendData:processedVocalData];
            
            // 🔧 注意：不再在这里混入BGM，BGM会在输出时实时混入（见下面的输出混音）
        } else {
            NSLog(@"⚠️ 混音缓冲区太小: 需要 %u, 可用 %u", sampleCount, engine->_mixBufferSize);
        }
    } else {
        // 🐛 调试日志：如果条件不满足，打印原因
        static int skipCount = 0;
        skipCount++;
        if (skipCount % 500 == 0) {  // 降低频率
            NSLog(@"⚠️ 跳过录音写入 #%d: isRecording=%d, isPaused=%d, hasSegment=%d",
                  skipCount,
                  engine.isRecording,
                  engine.isRecordingPaused,
                  engine.currentSegment != nil);
        }
    }
    
    // 4. 处理耳返输出（应用音效后输出人声，不含BGM）
    if (engine.enableEarReturn && ioData) {
        // 🔧 修复：使用预分配的耳返缓冲区，避免实时malloc/free
        static SInt16 *staticEarReturnBuffer = NULL;
        static UInt32 staticEarReturnBufferSize = 0;
        
        UInt32 requiredEarReturnSize = sampleCount * sizeof(SInt16);
        if (staticEarReturnBufferSize < requiredEarReturnSize) {
            if (staticEarReturnBuffer) {
                free(staticEarReturnBuffer);
            }
            staticEarReturnBuffer = (SInt16 *)malloc(requiredEarReturnSize);
            staticEarReturnBufferSize = requiredEarReturnSize;
        }
        
        if (staticEarReturnBuffer) {
            // 复制麦克风数据
            memcpy(staticEarReturnBuffer, staticInputBuffer, sampleCount * sizeof(SInt16));
            
            // 应用麦克风音量
            float micVol = engine.microphoneVolume;
            if (micVol != 1.0f) {
                for (UInt32 i = 0; i < sampleCount; i++) {
                    staticEarReturnBuffer[i] = (SInt16)(staticEarReturnBuffer[i] * micVol);
                }
            }
            
            // 🎵 关键修复：对耳返也应用音效处理
            if (engine.voiceEffectProcessor) {
                [engine.voiceEffectProcessor processAudioBuffer:staticEarReturnBuffer sampleCount:sampleCount];
            }
            
            // 输出到耳返（应用耳返音量）
            float earVolume = engine.earReturnVolume;
            for (int i = 0; i < ioData->mNumberBuffers; i++) {
                SInt16 *samples = (SInt16 *)ioData->mBuffers[i].mData;
                UInt32 bufferSampleCount = ioData->mBuffers[i].mDataByteSize / sizeof(SInt16);
                UInt32 copyCount = MIN(sampleCount, bufferSampleCount);
                
                // 输出带音效的人声
                for (UInt32 j = 0; j < copyCount; j++) {
                    samples[j] = (SInt16)(staticEarReturnBuffer[j] * earVolume);
                }
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
            float sample = abs(staticInputBuffer[i]) / 32768.0f;
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
    
    // 🔧 修复：不再需要释放静态缓冲区
    // staticInputBuffer 是静态分配的，不需要释放
    
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
    
    NSLog(@"🎤 准备开始录音（从 %.2f 秒开始）", startTime);
    NSLog(@"   当前状态: isRecording=%d, isRecordingPaused=%d", self.isRecording, self.isRecordingPaused);
    NSLog(@"   BGM状态: isPlaying=%d, currentTime=%.2f", self.isPlaying, self.currentPlaybackTime);
    
    // 如果之前暂停了，先保存暂停前的段落
    if (self.isRecording && self.isRecordingPaused) {
        [self saveCurrentSegment];
    }
    
    // 🔧 确保音频会话正确配置（支持 AVAudioEngine + AudioUnit 混合使用）
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSError *sessionError = nil;
    
    // 使用 PlayAndRecord 类别，允许同时播放和录音
    if (![audioSession setCategory:AVAudioSessionCategoryPlayAndRecord 
                       withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionAllowBluetooth
                             error:&sessionError]) {
        NSLog(@"⚠️ 音频会话配置失败: %@", sessionError);
    }
    
    // 激活音频会话
    if (![audioSession setActive:YES error:&sessionError]) {
        NSLog(@"⚠️ 音频会话激活失败: %@", sessionError);
    } else {
        NSLog(@"✅ 音频会话已激活: 类别=%@, 采样率=%.0fHz", audioSession.category, audioSession.sampleRate);
    }
    
    // 🎯 关键修复：确保AUGraph在创建录音段落之前启动
    Boolean isRunning = false;
    AUGraphIsRunning(self.auGraph, &isRunning);
    NSLog(@"   AUGraph状态: isRunning=%d", isRunning);
    
    if (!isRunning) {
        NSLog(@"   启动AUGraph...");
        OSStatus status = AUGraphStart(self.auGraph);
        CheckError(status, "AUGraphStart");
        
        if (status == noErr) {
            // 短暂延迟，确保AUGraph完全启动
            usleep(50 * 1000);  // 50ms
            NSLog(@"   ✅ AUGraph已启动");
        } else {
            NSLog(@"   ❌ AUGraph启动失败！");
        }
        
        // 再次确认状态
        AUGraphIsRunning(self.auGraph, &isRunning);
        NSLog(@"   AUGraph最终状态: isRunning=%d", isRunning);
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
    self.isRecording = YES;
    
    NSLog(@"✅ 录音已启动");
    NSLog(@"   currentSegment: %p", self.currentSegment);
    NSLog(@"   vocalData初始大小: %lu bytes", (unsigned long)self.currentSegment.vocalData.length);
    NSLog(@"   audioData初始大小: %lu bytes", (unsigned long)self.currentSegment.audioData.length);
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
    
    // 🔧 关键修复：先停止录音标志，立即阻止录音回调继续写入数据
    self.isRecording = NO;
    self.isRecordingPaused = NO;
    
    // 然后再保存当前段落（此时录音回调已停止写入）
    [self saveCurrentSegment];
    
    // 清理当前段落引用
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
        NSLog(@"⚠️ saveCurrentSegment: currentSegment为nil，跳过保存");
        return;
    }
    
    // 🐛 详细调试：检查数据大小和调用栈
    // 🔧 关键修复：使用实际采样率（从AudioUnit），而不是AudioSession的采样率
    double correctSampleRate = self.actualSampleRate;
    NSTimeInterval vocalDuration = (self.currentSegment.vocalData.length / sizeof(SInt16)) / correctSampleRate;
    NSTimeInterval audioDuration = (self.currentSegment.audioData.length / sizeof(SInt16)) / correctSampleRate;
    
    NSLog(@"💾 准备保存段落 (调用栈检查):");
    NSLog(@"   采样率: %.0f Hz (从AudioUnit)", correctSampleRate);
    NSLog(@"   vocalData: %lu bytes (%.2f秒)", (unsigned long)self.currentSegment.vocalData.length, vocalDuration);
    NSLog(@"   audioData: %lu bytes (%.2f秒)", (unsigned long)self.currentSegment.audioData.length, audioDuration);
    NSLog(@"   startTime: %.2f秒", self.currentSegment.startTime);
    NSLog(@"   已保存段落数: %lu", (unsigned long)self.recordingSegmentsInternal.count);
    
    // 🎯 关键修复：检查是否有数据，空段落不保存
    if (self.currentSegment.audioData.length == 0) {
        NSLog(@"⚠️ 段落无数据，丢弃此段落");
        self.currentSegment = nil;
        return;
    }
    
    // 计算段落时长（使用实际采样率）
    NSUInteger sampleCount = self.currentSegment.audioData.length / sizeof(SInt16);
    self.currentSegment.duration = (NSTimeInterval)sampleCount / correctSampleRate;
    
    // 添加到段落数组
    [self.recordingSegmentsInternal addObject:self.currentSegment];
    
    NSLog(@"✅ 段落已保存: %.2f~%.2fs (%.2fMB, %@)",
          self.currentSegment.startTime,
          self.currentSegment.startTime + self.currentSegment.duration,
          self.currentSegment.audioData.length / (1024.0 * 1024.0),
          self.currentSegment.isRecorded ? @"录制" : @"BGM");
    NSLog(@"   总段落数: %lu", (unsigned long)self.recordingSegmentsInternal.count);
    
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
    
    // 🔧 设置跳转标志
    self.isRewindingOrJumping = YES;
    
    // 如果正在录音，先保存当前段落
    if (self.isRecording && !self.isRecordingPaused) {
        [self saveCurrentSegment];
        self.isRecordingPaused = YES;
    }
    
    // 🆕 创建空白段落（纯BGM）填充跳过的时间
    NSTimeInterval gapDuration = targetTime - currentTime;
    if (gapDuration > 0.1) {  // 至少0.1秒才创建空白段落
        RecordingSegment *gapSegment = [[RecordingSegment alloc] init];
        gapSegment.startTime = currentTime;
        gapSegment.duration = gapDuration;
        gapSegment.isRecorded = NO;  // 标记为纯BGM段落
        gapSegment.audioData = [NSMutableData data];  // 空数据
        gapSegment.vocalData = [NSMutableData data];  // 空数据
        
        [self.recordingSegmentsInternal addObject:gapSegment];
        NSLog(@"📝 创建空白段落: %.2f~%.2fs (纯BGM)", currentTime, targetTime);
    }
    
    // 🔧 Bug修复：记住当前播放状态
    BOOL wasPlaying = self.isPlaying;
    
    // 停止当前播放并重新调度
    if (self.bgmPlayerNode) {
        [self.bgmPlayerNode stop];
    }
    
    // 🔧 修复：更新BGM读取位置（使用BGM PCM数据的实际采样率）
    double bgmPCMSampleRate = self.bgmPCMSampleRate > 0 ? self.bgmPCMSampleRate : self.actualSampleRate;
    self.bgmReadPosition = (NSUInteger)(targetTime * bgmPCMSampleRate);
    
    NSLog(@"⏭️ 跳转到 %.2f 秒（跳过 %.2f 秒）", targetTime, targetTime - currentTime);
    NSLog(@"   BGM读取位置: %lu/%lu (%.0f Hz)", 
          (unsigned long)self.bgmReadPosition, 
          (unsigned long)self.bgmPCMDataLength,
          bgmPCMSampleRate);
    
    // 🔧 Bug修复：如果之前在播放，确保跳转后继续播放
    if (wasPlaying) {
        NSLog(@"▶️ 跳转后继续播放");
        [self playFromTime:targetTime];
    }
    
    // 如果正在录音模式，恢复录音
    if (self.isRecording && self.isRecordingPaused) {
        [self resumeRecording];
    }
    
    // 通知代理段落更新
    [self notifySegmentsUpdate];
    
    // 🔧 延迟清除跳转标志，确保playFromTime完成
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.isRewindingOrJumping = NO;
        NSLog(@"✅ 跳转操作完成，标志已清除");
    });
}

// 🆕 回退到指定时间（删除之后的所有段落）
- (void)rewindToTime:(NSTimeInterval)targetTime {
    NSLog(@"⏪ 回退到 %.2f 秒", targetTime);
    
    // 🔧 设置回退标志
    self.isRewindingOrJumping = YES;
    
    // 如果正在录音，先停止当前段落
    if (self.isRecording && self.currentSegment) {
        self.currentSegment = nil;  // 丢弃当前段落（不保存）
    }
    
    // 删除目标时间之后的所有段落
    NSMutableArray *segmentsToKeep = [NSMutableArray array];
    
    // 🔧 修复：使用录音的实际采样率来计算段落截断
    double recordingSampleRate = self.actualSampleRate > 0 ? self.actualSampleRate : 48000.0;
    
    for (RecordingSegment *segment in self.recordingSegmentsInternal) {
        if (segment.startTime < targetTime) {
            // 如果段落跨越目标时间，需要截断
            if (segment.startTime + segment.duration > targetTime) {
                NSTimeInterval newDuration = targetTime - segment.startTime;
                NSUInteger newSampleCount = (NSUInteger)(newDuration * recordingSampleRate);
                NSUInteger newByteLength = newSampleCount * sizeof(SInt16);
                
                // 截断audioData和vocalData
                if (newByteLength < segment.audioData.length) {
                    [segment.audioData setLength:newByteLength];
                }
                if (segment.vocalData && newByteLength < segment.vocalData.length) {
                    [segment.vocalData setLength:newByteLength];
                }
                
                segment.duration = newDuration;
                NSLog(@"✂️ 截断段落: %.2f~%.2fs (原%.2fs)", segment.startTime, targetTime, segment.startTime + segment.duration);
            }
            [segmentsToKeep addObject:segment];
        } else {
            NSLog(@"🗑️ 删除段落: %.2f~%.2fs", segment.startTime, segment.startTime + segment.duration);
        }
    }
    
    self.recordingSegmentsInternal = segmentsToKeep;
    
    // 🔧 Bug修复：记住当前播放状态
    BOOL wasPlaying = self.isPlaying;
    BOOL wasRecording = self.isRecording;
    
    // 停止当前播放
    if (self.bgmPlayerNode) {
        [self.bgmPlayerNode stop];
    }
    
    // 🔧 修复：更新BGM读取位置（使用BGM PCM数据的实际采样率）
    double bgmPCMSampleRate = self.bgmPCMSampleRate > 0 ? self.bgmPCMSampleRate : self.actualSampleRate;
    self.bgmReadPosition = (NSUInteger)(targetTime * bgmPCMSampleRate);
    
    NSLog(@"   BGM读取位置: %lu/%lu (%.0f Hz)", 
          (unsigned long)self.bgmReadPosition, 
          (unsigned long)self.bgmPCMDataLength,
          bgmPCMSampleRate);
    
    // 🔧 Bug修复：如果之前在播放/录音，回退后继续播放/录音
    if (wasPlaying || wasRecording) {
        NSLog(@"▶️ 回退后继续播放（wasPlaying=%d, wasRecording=%d）", wasPlaying, wasRecording);
        [self playFromTime:targetTime];
        
        if (wasRecording) {
            [self startRecordingFromTime:targetTime];
        }
    }
    
    // 通知代理
    [self notifySegmentsUpdate];
    
    // 🔧 延迟清除回退标志，确保playFromTime完成
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.isRewindingOrJumping = NO;
        NSLog(@"✅ 回退操作完成，标志已清除");
    });
    
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

// 🆕 获取已录制的总时长（合成后的总时长，包括BGM填充）
- (NSTimeInterval)getTotalRecordedDuration {
    if (self.recordingSegmentsInternal.count == 0) {
        return 0.0;
    }
    
    // 🔧 修复：返回从0秒到最后一个段落结束的总时长
    // 这样跳转场景下会正确显示：例如录0~9秒，跳转到30秒继续录制，显示30+秒
    NSTimeInterval lastEndTime = 0.0;
    for (RecordingSegment *segment in self.recordingSegmentsInternal) {
        NSTimeInterval segmentEndTime = segment.startTime + segment.duration;
        if (segmentEndTime > lastEndTime) {
            lastEndTime = segmentEndTime;
        }
    }
    
    return lastEndTime;
}

// 🆕 获取实际录音时长（只计算有人声的段落）
- (NSTimeInterval)getActualVocalDuration {
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
    NSLog(@"📊 当前预览参数:");
    NSLog(@"   BGM音量: %.0f%%", self.bgmVolume * 100);
    NSLog(@"   BGM音高: %.1f 半音", self.bgmPitchShift);
    NSLog(@"   麦克风音量: %.0f%%", self.microphoneVolume * 100);
    NSLog(@"   音效: %@", [VoiceEffectProcessor nameForEffectType:self.voiceEffectProcessor.effectType]);
    
    return [self previewSynthesizedAudioWithBGMVolume:self.bgmVolume 
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
    
        // 🔧 停止BGM播放（预览时不需要播放原BGM）
        BOOL wasBGMPlaying = self.isPlaying;
        if (wasBGMPlaying) {
            [self pause];
            NSLog(@"⏸️ BGM已暂停以播放预览");
        }
        
        // 🔧 停止AUGraph（预览时不需要录音）
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
    
    // 🔧 关键修复：在文件名中嵌入采样率信息（使用实际采样率）
    double correctSampleRate = self.actualSampleRate > 0 ? self.actualSampleRate : 48000.0;
    NSString *fileName = [NSString stringWithFormat:@"karaoke_final_%ld_%.0fHz.pcm", 
                          (long)[[NSDate date] timeIntervalSince1970], 
                          correctSampleRate];
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
    NSLog(@"   BGM音量: %.0f%%, 麦克风音量: %.0f%%, 音效: %@, BGM音高: %.1f半音", 
          bgmVolume * 100, micVolume * 100, 
          [VoiceEffectProcessor nameForEffectType:effectType],
          self.bgmPitchShift);
    
    // 🔧 关键修复：使用录音时的实际采样率，而不是AudioSession采样率
    // 录音使用 AudioUnit 的 48000 Hz，合成也必须使用 48000 Hz
    double systemSampleRate = self.actualSampleRate;
    NSLog(@"   🔍 合成采样率: %.0f Hz (从AudioUnit)", systemSampleRate);
    
    // 2. 🆕 如果需要音高调整，使用SoundTouch批处理整个BGM
    NSData *processedBGM = self.bgmPCMData;
    
    if (fabs(self.bgmPitchShift) > 0.01f) {
        NSLog(@"🎵 使用SoundTouch批处理BGM音高 (%.1f半音)...", self.bgmPitchShift);
        processedBGM = [self applyPitchShiftToBGM:self.bgmPCMData 
                                       pitchShift:self.bgmPitchShift 
                                       sampleRate:systemSampleRate];
        
        if (!processedBGM || processedBGM.length == 0) {
            NSLog(@"⚠️ 音高处理失败，使用原始BGM");
            processedBGM = self.bgmPCMData;
        }
    }
    
    // 3. 临时保存处理后的BGM（用于extractBGMFromTime）
    NSData *originalBGM = self.bgmPCMData;
    NSUInteger originalLength = self.bgmPCMDataLength;
    
    self.bgmPCMData = processedBGM;
    self.bgmPCMDataLength = processedBGM.length / sizeof(SInt16);
    
    // 4. 按时间排序段落
    NSArray *sortedSegments = [self.recordingSegmentsInternal sortedArrayUsingComparator:^NSComparisonResult(RecordingSegment *seg1, RecordingSegment *seg2) {
        if (seg1.startTime < seg2.startTime) return NSOrderedAscending;
        if (seg1.startTime > seg2.startTime) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    
    // 5. 创建最终输出缓冲区
    NSMutableData *finalAudio = [NSMutableData data];
    
    // 6. 创建音效处理器（如果需要重新应用音效）
    VoiceEffectProcessor *previewEffectProcessor = nil;
    if (effectType != VoiceEffectTypeNone) {
        previewEffectProcessor = [[VoiceEffectProcessor alloc] initWithSampleRate:systemSampleRate];
        [previewEffectProcessor setPresetEffect:effectType];
        NSLog(@"🎵 预览将应用音效: %@", [VoiceEffectProcessor nameForEffectType:effectType]);
    }
    
    // 5. 逐段处理
    // 🔧 修复：始终从0秒开始合成，这样跳转场景才能正确填充前面的BGM
    // 例如：录制0~9秒，跳转到30秒继续录制，合成时应该是 0~9秒录音 + 9~30秒BGM + 30秒后录音
    NSTimeInterval currentTime = 0.0;
    NSTimeInterval lastSegmentEndTime = 0.0;
    
    // 如果第一个段落不是从0秒开始，需要先填充前面的BGM
    if (sortedSegments.count > 0) {
        RecordingSegment *firstSegment = sortedSegments.firstObject;
        if (firstSegment.startTime > 0.1) {
            NSLog(@"🎵 填充开头BGM: 0.00~%.2fs", firstSegment.startTime);
            NSData *leadingBGM = [self extractBGMFromTime:0.0 
                                                duration:firstSegment.startTime 
                                              sampleRate:systemSampleRate 
                                                  volume:bgmVolume];
            if (leadingBGM) {
                [finalAudio appendData:leadingBGM];
            }
            currentTime = firstSegment.startTime;
        }
    }
    
    NSLog(@"🎬 合成起始时间: 0.00秒，当前处理位置: %.2f秒", currentTime);
    NSLog(@"📊 段落详细信息:");
    for (int i = 0; i < sortedSegments.count; i++) {
        RecordingSegment *seg = sortedSegments[i];
        NSLog(@"   段落 %d: %.2f~%.2fs (%.2fs), vocalData=%lu bytes, audioData=%lu bytes, isRecorded=%d",
              i, seg.startTime, seg.startTime + seg.duration, seg.duration,
              (unsigned long)seg.vocalData.length, (unsigned long)seg.audioData.length, seg.isRecorded);
    }
    
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
    NSLog(@"   BGM总时长: %.2f秒", self.bgmDuration);
    NSLog(@"   合成策略: 只保留已录制部分（%.2f秒）", lastSegmentEndTime);
    
    NSTimeInterval totalDuration = finalAudio.length / sizeof(SInt16) / systemSampleRate;
    NSLog(@"✅ 音频数据合成完成:");
    NSLog(@"   总大小: %.2fMB", finalAudio.length / (1024.0 * 1024.0));
    NSLog(@"   总时长: %.2f秒", totalDuration);
    NSLog(@"   采样率: %.0fHz", systemSampleRate);
    
    // 7. 🆕 恢复原始BGM数据
    self.bgmPCMData = originalBGM;
    self.bgmPCMDataLength = originalLength;
    
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

#pragma mark - 🎵 BGM音高处理（使用SoundTouch批处理）

- (NSData *)applyPitchShiftToBGM:(NSData *)bgmData 
                      pitchShift:(float)semitones 
                      sampleRate:(double)sampleRate {
    if (fabs(semitones) < 0.01f || !bgmData || bgmData.length == 0) {
        // 音高偏移太小或没有数据，直接返回原数据
        return bgmData;
    }
    
    NSLog(@"🎵 开始使用SoundTouch批处理BGM音高 (%.1f半音)...", semitones);
    
    // 创建SoundTouch实例
    SoundTouchHandle *st = soundtouch_create();
    if (!st) {
        NSLog(@"❌ 无法创建SoundTouch实例");
        return bgmData;
    }
    
    soundtouch_setSampleRate(st, (unsigned int)sampleRate);
    soundtouch_setChannels(st, 1);  // 单声道
    soundtouch_setPitch(st, semitones);  // 设置音高偏移（半音）
    
    // 优化设置：提高音质
    soundtouch_setSetting(st, SETTING_USE_QUICKSEEK, 0);  // 禁用快速搜索，提高音质
    soundtouch_setSetting(st, SETTING_USE_AA_FILTER, 1);  // 启用抗混叠滤波器
    
    // 转换 SInt16 → float
    NSUInteger sampleCount = bgmData.length / sizeof(SInt16);
    const SInt16 *int16Samples = (const SInt16 *)bgmData.bytes;
    float *floatSamples = (float *)malloc(sampleCount * sizeof(float));
    
    if (!floatSamples) {
        NSLog(@"❌ 无法分配浮点数缓冲区");
        soundtouch_destroy(st);
        return bgmData;
    }
    
    for (NSUInteger i = 0; i < sampleCount; i++) {
        floatSamples[i] = int16Samples[i] / 32768.0f;
    }
    
    // 输入所有样本到SoundTouch
    NSLog(@"   输入 %lu 个样本到SoundTouch...", (unsigned long)sampleCount);
    soundtouch_putSamples(st, floatSamples, (unsigned int)sampleCount);
    soundtouch_flush(st);  // 刷新，获取所有处理后的样本
    
    // 接收处理后的样本
    NSMutableData *outputData = [NSMutableData data];
    float *outputBuffer = (float *)malloc(8192 * sizeof(float));
    
    if (!outputBuffer) {
        NSLog(@"❌ 无法分配输出缓冲区");
        free(floatSamples);
        soundtouch_destroy(st);
        return bgmData;
    }
    
    unsigned int receivedSamples;
    NSUInteger totalReceivedSamples = 0;
    
    while ((receivedSamples = soundtouch_receiveSamples(st, outputBuffer, 8192)) > 0) {
        // 转换 float → SInt16
        for (unsigned int i = 0; i < receivedSamples; i++) {
            float sample = fmaxf(-1.0f, fminf(1.0f, outputBuffer[i]));
            SInt16 int16Sample = (SInt16)(sample * 32767.0f);
            [outputData appendBytes:&int16Sample length:sizeof(SInt16)];
        }
        totalReceivedSamples += receivedSamples;
    }
    
    // 清理
    free(floatSamples);
    free(outputBuffer);
    soundtouch_destroy(st);
    
    NSLog(@"✅ SoundTouch批处理完成:");
    NSLog(@"   输入样本: %lu", (unsigned long)sampleCount);
    NSLog(@"   输出样本: %lu", (unsigned long)totalReceivedSamples);
    NSLog(@"   样本比率: %.2f%%", (totalReceivedSamples * 100.0 / sampleCount));
    NSLog(@"   输出大小: %.2f MB", outputData.length / (1024.0 * 1024.0));
    
    return outputData;
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
    
    // 🔧 关键修复：在文件名中嵌入采样率信息（使用实际采样率）
    double correctSampleRate = self.actualSampleRate > 0 ? self.actualSampleRate : 48000.0;
    NSString *fileName = [NSString stringWithFormat:@"karaoke_final_%ld_%.0fHz.pcm", 
                          (long)[[NSDate date] timeIntervalSince1970], 
                          correctSampleRate];
    self.recordingFilePath = [documentsDirectory stringByAppendingPathComponent:fileName];
    
    BOOL success = [finalAudio writeToFile:self.recordingFilePath atomically:YES];
    
    if (success) {
        // 使用实际采样率计算时长
        NSTimeInterval totalDuration = finalAudio.length / sizeof(SInt16) / correctSampleRate;
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
    
    // 🔧 关键修复：使用 audioData（已包含音效）而不是 vocalData
    // audioData 在录制时已经应用了音效，不需要重新处理
    if (!segment.audioData || segment.audioData.length == 0) {
        NSLog(@"⚠️ 段落没有音频数据");
        return nil;
    }
    
    // 1. 获取已处理的音频数据（包含人声+音效，但不含BGM）
    const SInt16 *audioSamples = (const SInt16 *)segment.audioData.bytes;
    NSUInteger sampleCount = segment.audioData.length / sizeof(SInt16);
    
    NSLog(@"   🔍 remixSegment 输入:");
    NSLog(@"      audioData: %lu bytes (%lu samples)", 
          (unsigned long)segment.audioData.length, (unsigned long)sampleCount);
    NSLog(@"      预期时长: %.2f秒（根据 duration）", segment.duration);
    NSLog(@"      实际时长: %.2f秒（根据 audioData）", (double)sampleCount / sampleRate);
    
    // 2. 创建输出缓冲区
    NSMutableData *outputData = [NSMutableData dataWithLength:segment.audioData.length];
    SInt16 *outputSamples = (SInt16 *)outputData.mutableBytes;
    
    // 3. 复制并调整音量（不重新应用音效）
    for (NSUInteger i = 0; i < sampleCount; i++) {
        int32_t sample = (int32_t)(audioSamples[i] * micVolume);
        
        // 防止溢出
        if (sample > 32767) sample = 32767;
        if (sample < -32768) sample = -32768;
        
        outputSamples[i] = (SInt16)sample;
    }
    
    // 4. 🔧 不再重新应用音效（audioData 已包含音效）
    // 重新应用音效会导致音频长度改变（10秒变20秒）
    NSLog(@"   ✅ 使用录制时的音效（%@），时长: %.2f秒", 
          [VoiceEffectProcessor nameForEffectType:segment.appliedEffect],
          (double)sampleCount / sampleRate);
    
    // 5. 混合BGM
    NSData *bgmData = [self extractBGMFromTime:segment.startTime 
                                      duration:segment.duration 
                                    sampleRate:sampleRate 
                                        volume:bgmVolume];
    
    NSLog(@"   🔍 BGM 混入:");
    NSLog(@"      bgmData: %lu bytes (%s)", 
          (unsigned long)(bgmData ? bgmData.length : 0),
          bgmData ? "成功" : "失败");
    NSLog(@"      outputData: %lu bytes", (unsigned long)outputData.length);
    NSLog(@"      长度匹配: %s", (bgmData && bgmData.length == outputData.length) ? "是" : "否");
    
    if (bgmData && bgmData.length == outputData.length) {
        const SInt16 *bgmSamples = (const SInt16 *)bgmData.bytes;
        
        for (NSUInteger i = 0; i < sampleCount; i++) {
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
    
    NSLog(@"   🔍 remixSegment 输出:");
    NSLog(@"      outputData: %lu bytes (%lu samples, %.2f秒)", 
          (unsigned long)outputData.length,
          (unsigned long)(outputData.length / sizeof(SInt16)),
          (double)(outputData.length / sizeof(SInt16)) / sampleRate);
    
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
    
    // 🔧 关键修复：使用BGM PCM数据的实际采样率来计算样本位置
    // 而不是使用传入的录音采样率（它们可能不同）
    double bgmActualSampleRate = self.bgmPCMSampleRate > 0 ? self.bgmPCMSampleRate : sampleRate;
    
    NSLog(@"   🔍 BGM提取参数:");
    NSLog(@"      时间范围: %.2f ~ %.2f秒 (时长: %.2f秒)", startTime, startTime + duration, duration);
    NSLog(@"      BGM采样率: %.0f Hz", bgmActualSampleRate);
    NSLog(@"      录音采样率: %.0f Hz", sampleRate);
    
    // 计算样本范围（使用BGM的实际采样率）
    NSUInteger startSample = (NSUInteger)(startTime * bgmActualSampleRate);
    NSUInteger bgmSampleCount = (NSUInteger)(duration * bgmActualSampleRate);
    
    // 边界检查
    if (startSample >= self.bgmPCMDataLength) {
        NSLog(@"⚠️ BGM起始位置超出范围: startSample=%lu, bgmLength=%lu", 
              (unsigned long)startSample, (unsigned long)self.bgmPCMDataLength);
        return nil;
    }
    
    // 调整样本数量
    if (startSample + bgmSampleCount > self.bgmPCMDataLength) {
        bgmSampleCount = self.bgmPCMDataLength - startSample;
        NSLog(@"   ⚠️ BGM样本数量被截断: %lu samples", (unsigned long)bgmSampleCount);
    }
    
    const SInt16 *bgmSamples = (const SInt16 *)self.bgmPCMData.bytes;
    
    // 🔧 关键修复：如果BGM采样率和录音采样率不同，需要重采样
    if (fabs(bgmActualSampleRate - sampleRate) > 1.0) {
        // 需要重采样
        NSLog(@"   🔄 需要重采样: %.0f Hz -> %.0f Hz", bgmActualSampleRate, sampleRate);
        
        // 计算输出样本数（录音采样率）
        NSUInteger outputSampleCount = (NSUInteger)(duration * sampleRate);
        NSMutableData *extractedData = [NSMutableData dataWithLength:outputSampleCount * sizeof(SInt16)];
        SInt16 *outputSamples = (SInt16 *)extractedData.mutableBytes;
        
        // 线性插值重采样
        double ratio = bgmActualSampleRate / sampleRate;
        for (NSUInteger i = 0; i < outputSampleCount; i++) {
            double srcPos = i * ratio;
            NSUInteger srcIndex = (NSUInteger)srcPos;
            double frac = srcPos - srcIndex;
            
            if (startSample + srcIndex + 1 < self.bgmPCMDataLength) {
                // 线性插值
                SInt16 sample1 = bgmSamples[startSample + srcIndex];
                SInt16 sample2 = bgmSamples[startSample + srcIndex + 1];
                int32_t interpolated = (int32_t)(sample1 * (1.0 - frac) + sample2 * frac);
                
                // 应用音量
                interpolated = (int32_t)(interpolated * volume);
                
                // 防止溢出
                if (interpolated > 32767) interpolated = 32767;
                if (interpolated < -32768) interpolated = -32768;
                
                outputSamples[i] = (SInt16)interpolated;
            } else {
                outputSamples[i] = 0;
            }
        }
        
        NSLog(@"   ✅ 重采样完成: %lu samples (BGM) -> %lu samples (录音)", 
              (unsigned long)bgmSampleCount, (unsigned long)outputSampleCount);
        return extractedData;
    } else {
        // 采样率相同，直接提取并应用音量
        NSLog(@"   ✅ 采样率匹配，直接提取 %lu samples", (unsigned long)bgmSampleCount);
        
        NSMutableData *extractedData = [NSMutableData dataWithLength:bgmSampleCount * sizeof(SInt16)];
        SInt16 *outputSamples = (SInt16 *)extractedData.mutableBytes;
        
        for (NSUInteger i = 0; i < bgmSampleCount; i++) {
            int32_t sample = (int32_t)(bgmSamples[startSample + i] * volume);
            
            // 防止溢出
            if (sample > 32767) sample = 32767;
            if (sample < -32768) sample = -32768;
            
            outputSamples[i] = (SInt16)sample;
        }
        
        return extractedData;
    }
}

// 🆕 从BGM中提取指定时间段的数据（向后兼容，使用当前BGM音量）
- (NSData *)extractBGMFromTime:(NSTimeInterval)startTime duration:(NSTimeInterval)duration sampleRate:(double)sampleRate {
    return [self extractBGMFromTime:startTime duration:duration sampleRate:sampleRate volume:self.bgmVolume];
}


#pragma mark - 音频播放

- (void)loadAudioFile:(NSString *)filePath {
    NSError *error;
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    
    NSLog(@"🎵 开始加载BGM文件: %@", filePath);
    
    // 1. 🆕 加载音频文件到 AVAudioFile（用于AVAudioEngine播放）
    self.bgmAudioFile = [[AVAudioFile alloc] initForReading:fileURL error:&error];
    if (error || !self.bgmAudioFile) {
        NSLog(@"❌ 加载音频文件失败: %@", error.localizedDescription);
        return;
    }
    
    // 保存BGM时长
    self.bgmDuration = (NSTimeInterval)self.bgmAudioFile.length / self.bgmAudioFile.processingFormat.sampleRate;
    
    NSLog(@"✅ BGM文件信息:");
    NSLog(@"   格式: %.0f Hz, %u 声道", 
          self.bgmAudioFile.processingFormat.sampleRate, 
          (unsigned int)self.bgmAudioFile.processingFormat.channelCount);
    NSLog(@"   帧数: %lld", self.bgmAudioFile.length);
    NSLog(@"   时长: %.2f 秒", self.bgmDuration);
    
    // 2. 将整个BGM文件转换为PCM格式并加载到内存（用于录音混合）
    NSLog(@"🔄 开始转换BGM文件为PCM（用于录音混合）...");
    NSData *pcmData = [self convertAudioFileToPCM:filePath];
    
    if (pcmData) {
        // 原子赋值，不需要锁
        self.bgmPCMData = pcmData;
        NSUInteger originalLength = pcmData.length / sizeof(int16_t);
        
        // 🔧 使用实际采样率计算时长（与录音一致）
        double correctSampleRate = self.actualSampleRate > 0 ? self.actualSampleRate : 48000.0;
        
        NSLog(@"✅ BGM PCM数据转换成功:");
        NSLog(@"   文件大小: %.2f MB", self.bgmPCMData.length / (1024.0 * 1024.0));
        NSLog(@"   样本数: %lu", (unsigned long)originalLength);
        NSLog(@"   采样率: %.0f Hz (与录音一致)", correctSampleRate);
        NSLog(@"   精确时长: %.2f秒", originalLength / correctSampleRate);
        
        self.bgmPCMDataLength = originalLength;
        self.bgmPCMSampleRate = correctSampleRate;  // 🔧 保存BGM PCM数据的采样率
        self.bgmReadPosition = 0;
    } else {
        NSLog(@"❌ BGM文件转换失败");
    }
    
    NSLog(@"✅ 音频文件加载完成，可以开始播放");
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
    
    // 🔧 关键修复：使用录音的实际采样率（从AudioUnit），确保BGM和录音采样率一致
    // 录音使用 AudioUnit 的 48000 Hz，所以 BGM 也必须转换为 48000 Hz
    double bgmSampleRate = self.actualSampleRate > 0 ? self.actualSampleRate : 48000.0;
    
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    double audioSessionSampleRate = audioSession.sampleRate;
    
    NSLog(@"🎵 BGM 转换采样率: %.0f Hz (录音采样率)", bgmSampleRate);
    NSLog(@"   AudioSession 采样率: %.0f Hz (仅供参考)", audioSessionSampleRate);
    
    // 设置PCM格式 (录音采样率, 单声道, 16bit)
    AVAudioFormat *pcmFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16
                                                                sampleRate:bgmSampleRate
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
              bgmSampleRate);
        
        // 🔧 计算预期的输出帧数（考虑采样率转换）
        double sampleRateRatio = bgmSampleRate / audioFile.processingFormat.sampleRate;
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

// 🆕 从指定时间开始播放（使用 AVAudioEngine）
- (void)playFromTime:(NSTimeInterval)startTime {
    if (!self.bgmAudioFile) {
        NSLog(@"❌ 没有加载音频文件");
        return;
    }
    
    // 🔧 确保 BGM 引擎正在运行
    if (!self.bgmEngine.isRunning) {
        NSError *error = nil;
        if (![self.bgmEngine startAndReturnError:&error]) {
            NSLog(@"❌ BGM引擎启动失败: %@", error);
            return;
        }
        NSLog(@"✅ BGM引擎已重新启动");
    }
    
    // 停止当前播放
    [self.bgmPlayerNode stop];
    
    // 🔧 递增会话ID，使旧的completionHandler失效
    self.playbackSessionID++;
    NSUInteger currentSessionID = self.playbackSessionID;
    
    // 获取系统采样率
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    double systemSampleRate = audioSession.sampleRate;
    
    // 计算起始帧位置
    AVAudioFramePosition startFrame = (AVAudioFramePosition)(startTime * self.bgmAudioFile.processingFormat.sampleRate);
    AVAudioFrameCount frameCount = (AVAudioFrameCount)(self.bgmAudioFile.length - startFrame);
    
    if (startFrame >= self.bgmAudioFile.length) {
        NSLog(@"⚠️ 起始时间 %.2f 超出BGM长度，重置为0", startTime);
        startFrame = 0;
        frameCount = (AVAudioFrameCount)self.bgmAudioFile.length;
        startTime = 0;
    }
    
    // 🔧 关键修复：使用BGM PCM数据的实际采样率来计算读取位置
    // 而不是使用AudioSession的采样率（它们可能不同）
    double bgmPCMSampleRate = self.bgmPCMSampleRate > 0 ? self.bgmPCMSampleRate : self.actualSampleRate;
    NSUInteger targetPosition = (NSUInteger)(startTime * bgmPCMSampleRate);
    self.bgmReadPosition = targetPosition;
    
    NSLog(@"🎵 从 %.2f 秒开始播放 BGM", startTime);
    NSLog(@"   音量: %.0f%%", self.bgmVolume * 100);
    NSLog(@"   音高: %.1f 半音", self.bgmPitchShift);
    NSLog(@"   BGM读取位置: %lu/%lu (%.0f Hz)", 
          (unsigned long)targetPosition, 
          (unsigned long)self.bgmPCMDataLength,
          bgmPCMSampleRate);
    
    // 调度音频段落播放
    __weak typeof(self) weakSelf = self;
    [self.bgmPlayerNode scheduleSegment:self.bgmAudioFile 
                          startingFrame:startFrame 
                             frameCount:frameCount 
                                 atTime:nil 
                      completionHandler:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        // 🔧 检查会话ID，忽略旧的completionHandler
        if (currentSessionID != strongSelf.playbackSessionID) {
            NSLog(@"🔇 忽略旧的播放完成回调（会话ID: %lu != %lu）", (unsigned long)currentSessionID, (unsigned long)strongSelf.playbackSessionID);
            return;
        }
        
        NSLog(@"🎵 BGM播放完成（会话ID: %lu）", (unsigned long)currentSessionID);
        strongSelf.isPlaying = NO;
        
        // 停止播放进度定时器
        [strongSelf stopPlaybackTimer];
        
        // 🔧 修复：如果正在录音或刚刚回退/跳转，不触发播放完成回调
        // 这样回退后继续录音时，BGM播放到末尾不会自动结束录音会话
        if (strongSelf.isRecording || strongSelf.isRewindingOrJumping) {
            NSLog(@"⚠️ 正在录音或回退中，忽略BGM播放完成回调（isRecording=%d, isRewindingOrJumping=%d）", 
                  strongSelf.isRecording, strongSelf.isRewindingOrJumping);
            return;
        }
        
        // 通知代理
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([strongSelf.delegate respondsToSelector:@selector(audioEngineDidFinishPlaying)]) {
                [strongSelf.delegate audioEngineDidFinishPlaying];
            }
        });
    }];
    
    // 开始播放
    [self.bgmPlayerNode play];
    self.isPlaying = YES;
    self.lastPlaybackTime = startTime;
    
    // 启动播放进度定时器（用于歌词同步）
    [self startPlaybackTimer];
    
    NSLog(@"🎵 从 %.2f 秒开始播放 BGM", startTime);
    NSLog(@"   音量: %.0f%%", self.bgmVolume * 100);
    NSLog(@"   音高: %.1f 半音", self.bgmPitchShift);
    NSLog(@"   BGM读取位置: %lu/%lu", (unsigned long)targetPosition, (unsigned long)self.bgmPCMDataLength);
}

- (void)pause {
    [self.bgmPlayerNode pause];
    self.isPlaying = NO;
    [self stopPlaybackTimer];
    NSLog(@"⏸️ BGM暂停");
}

- (void)stop {
    [self.bgmPlayerNode stop];
    self.isPlaying = NO;
    self.bgmReadPosition = 0;
    self.lastPlaybackTime = 0;
    [self stopPlaybackTimer];
    NSLog(@"⏹️ BGM停止");
}

#pragma mark - 🎵 播放进度追踪

- (void)startPlaybackTimer {
    [self stopPlaybackTimer];
    
    // 创建定时器，每0.1秒更新一次播放位置
    self.playbackTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                          target:self
                                                        selector:@selector(updatePlaybackProgress)
                                                        userInfo:nil
                                                         repeats:YES];
    
    NSLog(@"⏱️ 播放进度定时器已启动");
}

- (void)stopPlaybackTimer {
    if (self.playbackTimer) {
        [self.playbackTimer invalidate];
        self.playbackTimer = nil;
        NSLog(@"⏱️ 播放进度定时器已停止");
    }
}

- (void)updatePlaybackProgress {
    if (!self.isPlaying || !self.bgmPlayerNode.isPlaying) {
        return;
    }
    
    // 从AVAudioPlayerNode获取当前播放位置
    AVAudioTime *nodeTime = self.bgmPlayerNode.lastRenderTime;
    AVAudioTime *playerTime = [self.bgmPlayerNode playerTimeForNodeTime:nodeTime];
    
    if (playerTime) {
        // 计算当前播放时间
        NSTimeInterval currentTime = self.lastPlaybackTime + (NSTimeInterval)playerTime.sampleTime / playerTime.sampleRate;
        
        // 🔧 关键修复：使用BGM PCM数据的实际采样率来更新读取位置
        double bgmPCMSampleRate = self.bgmPCMSampleRate > 0 ? self.bgmPCMSampleRate : self.actualSampleRate;
        if (bgmPCMSampleRate > 0) {
            self.bgmReadPosition = (NSUInteger)(currentTime * bgmPCMSampleRate);
        }
        
        // 通知代理更新播放时间（用于歌词同步等）
        if ([self.delegate respondsToSelector:@selector(audioEngineDidUpdatePlaybackTime:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // 这里可以添加新的delegate方法来通知播放时间
                // 暂时先不添加，保持接口兼容
            });
        }
    }
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
    
    // 3. 🆕 重置 BGM 播放节点到开头
    self.lastPlaybackTime = 0;
    NSLog(@"   ✅ BGM播放位置已重置");
    
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
    
    // 7. 🆕 清空预览缓存
    [self invalidatePreviewCache];
    NSLog(@"   ✅ 预览缓存已清空");
    
    // 8. 通知代理
    [self notifySegmentsUpdate];
    
    NSLog(@"✅ KaraokeAudioEngine 重置完成，可以开始新的录音");
}

#pragma mark - BGM控制

- (void)setBgmVolume:(float)volume {
    _bgmVolume = fmaxf(0.0f, fminf(1.0f, volume));
    
    // 应用到BGM引擎
    if (self.bgmEngine && self.bgmEngine.mainMixerNode) {
        self.bgmEngine.mainMixerNode.outputVolume = _bgmVolume;
    }
    
    NSLog(@"🎵 BGM音量: %.0f%%", _bgmVolume * 100);
}

- (void)setBgmPitchShift:(float)pitchShift {
    // 限制范围 -12 ~ +12 半音
    _bgmPitchShift = fmaxf(-12.0f, fminf(12.0f, pitchShift));
    
    // 应用到BGM音高节点 (AVAudioUnitTimePitch 使用 cents, 1半音 = 100 cents)
    if (self.bgmTimePitchNode) {
        self.bgmTimePitchNode.pitch = _bgmPitchShift * 100.0f;
    }
    
    NSLog(@"🎵 BGM音高调整: %.1f 半音 (%.0f cents)", _bgmPitchShift, _bgmPitchShift * 100.0f);
    
    // 清除预览缓存（因为音高参数变了）
    [self invalidatePreviewCache];
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

// 🎵 获取BGM总时长
- (NSTimeInterval)duration {
    return self.bgmDuration;
}

// 根据 BGM 读取位置计算当前播放时间
- (NSTimeInterval)currentPlaybackTime {
    // 🆕 从 AVAudioPlayerNode 获取播放位置
    if (self.bgmPlayerNode && self.bgmPlayerNode.isPlaying) {
        AVAudioTime *nodeTime = self.bgmPlayerNode.lastRenderTime;
        AVAudioTime *playerTime = [self.bgmPlayerNode playerTimeForNodeTime:nodeTime];
        
        if (playerTime) {
            // 计算相对于起始时间的播放时间
            NSTimeInterval currentTime = self.lastPlaybackTime + (NSTimeInterval)playerTime.sampleTime / playerTime.sampleRate;
            // 🔧 修复：确保时间不为负数
            return MAX(0.0, currentTime);
        }
    }
    
    // 如果没有播放，使用上次记录的时间
    if (self.lastPlaybackTime > 0) {
        return self.lastPlaybackTime;
    }
    
    // 回退到使用bgmReadPosition计算（用于录音时的同步）
    if (self.bgmPCMDataLength == 0) {
        return 0.0;
    }
    
    // 🔧 关键修复：使用BGM PCM数据的实际采样率来计算播放时间
    double bgmPCMSampleRate = self.bgmPCMSampleRate > 0 ? self.bgmPCMSampleRate : self.actualSampleRate;
    if (bgmPCMSampleRate <= 0) {
        bgmPCMSampleRate = 48000.0;  // 默认值
    }
    
    NSUInteger currentPos = self.bgmReadPosition;
    NSTimeInterval calculatedTime = (NSTimeInterval)currentPos / bgmPCMSampleRate;
    
    // 🔧 修复：确保计算出的时间不为负数，并且不超过歌曲总长度
    calculatedTime = MAX(0.0, calculatedTime);
    if (self.bgmDuration > 0) {
        calculatedTime = MIN(calculatedTime, self.bgmDuration);
    }
    
    return calculatedTime;
}

// 注意：AVAudioPlayerDelegate已移除，改用AVAudioPlayerNode的completionHandler

#pragma mark - 清理

- (void)dealloc {
    [self stopRecording];
    [self stop];
    
    // 🆕 停止播放进度定时器
    [self stopPlaybackTimer];
    
    // 🆕 清理BGM引擎
    if (self.bgmEngine) {
        [self.bgmEngine stop];
        self.bgmEngine = nil;
    }
    self.bgmPlayerNode = nil;
    self.bgmTimePitchNode = nil;
    
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
