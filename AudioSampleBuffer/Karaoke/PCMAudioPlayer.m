//
//  PCMAudioPlayer.m
//  AudioSampleBuffer
//
//  Created on 2025/10/14.
//

#import "PCMAudioPlayer.h"
#import <AVFoundation/AVFoundation.h>

#define kBufferCount 3
#define kBufferSize 8192

@interface PCMAudioPlayer () {
    AudioQueueRef _audioQueue;
    AudioQueueBufferRef _buffers[kBufferCount];
    AudioStreamBasicDescription _audioFormat;
    
    FILE *_pcmFile;
    SInt64 _totalFrames;
    SInt64 _currentFrame;
    BOOL _isPlaying;
}

@property (nonatomic, strong) NSString *filePath;
@property (nonatomic, assign) Float64 sampleRate;
@property (nonatomic, assign) UInt32 channels;
@property (nonatomic, assign) UInt32 bitsPerSample;
@property (nonatomic, strong) NSTimer *progressTimer;

@end

@implementation PCMAudioPlayer

- (instancetype)init {
    self = [super init];
    if (self) {
        _isPlaying = NO;
    }
    return self;
}

- (BOOL)loadPCMFile:(NSString *)filePath 
         sampleRate:(Float64)sampleRate 
           channels:(UInt32)channels 
       bitsPerSample:(UInt32)bitsPerSample {
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSLog(@"❌ PCM文件不存在: %@", filePath);
        return NO;
    }
    
    self.filePath = filePath;
    self.sampleRate = sampleRate;
    self.channels = channels;
    self.bitsPerSample = bitsPerSample;
    
    // 打开PCM文件
    _pcmFile = fopen([filePath UTF8String], "rb");
    if (!_pcmFile) {
        NSLog(@"❌ 无法打开PCM文件");
        return NO;
    }
    
    // 计算总帧数
    fseek(_pcmFile, 0, SEEK_END);
    long fileSize = ftell(_pcmFile);
    fseek(_pcmFile, 0, SEEK_SET);
    
    UInt32 bytesPerFrame = (bitsPerSample / 8) * channels;
    _totalFrames = fileSize / bytesPerFrame;
    _currentFrame = 0;
    
    NSLog(@"✅ PCM文件加载成功:");
    NSLog(@"   文件大小: %ld bytes", fileSize);
    NSLog(@"   采样率: %.0f Hz", sampleRate);
    NSLog(@"   声道数: %u", channels);
    NSLog(@"   位深度: %u bits", bitsPerSample);
    NSLog(@"   总帧数: %lld", _totalFrames);
    NSLog(@"   时长: %.2f 秒", [self duration]);
    
    // 设置音频格式
    _audioFormat.mSampleRate = sampleRate;
    _audioFormat.mFormatID = kAudioFormatLinearPCM;
    _audioFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    _audioFormat.mBytesPerPacket = bytesPerFrame;
    _audioFormat.mFramesPerPacket = 1;
    _audioFormat.mBytesPerFrame = bytesPerFrame;
    _audioFormat.mChannelsPerFrame = channels;
    _audioFormat.mBitsPerChannel = bitsPerSample;
    _audioFormat.mReserved = 0;
    
    // 创建AudioQueue
    OSStatus status = AudioQueueNewOutput(&_audioFormat,
                                         PCMPlaybackCallback,
                                         (__bridge void *)self,
                                         NULL,
                                         kCFRunLoopCommonModes,
                                         0,
                                         &_audioQueue);
    
    if (status != noErr) {
        NSLog(@"❌ 创建AudioQueue失败: %d", (int)status);
        fclose(_pcmFile);
        _pcmFile = NULL;
        return NO;
    }
    
    // 分配缓冲区
    for (int i = 0; i < kBufferCount; i++) {
        AudioQueueAllocateBuffer(_audioQueue, kBufferSize, &_buffers[i]);
    }
    
    return YES;
}

// AudioQueue回调函数
static void PCMPlaybackCallback(void *inUserData,
                                AudioQueueRef inAQ,
                                AudioQueueBufferRef inBuffer) {
    PCMAudioPlayer *player = (__bridge PCMAudioPlayer *)inUserData;
    
    // 只有在播放状态才填充缓冲区
    if (player.isPlaying) {
        [player fillBuffer:inBuffer];
    }
}

- (void)fillBuffer:(AudioQueueBufferRef)buffer {
    if (!_pcmFile) {
        NSLog(@"❌ PCM文件未打开");
        return;
    }
    
    // 读取PCM数据
    size_t bytesRead = fread(buffer->mAudioData, 1, kBufferSize, _pcmFile);
    
    NSLog(@"📖 读取 %zu bytes 到缓冲区", bytesRead);
    
    if (bytesRead > 0) {
        buffer->mAudioDataByteSize = (UInt32)bytesRead;
        AudioQueueEnqueueBuffer(_audioQueue, buffer, 0, NULL);
        
        // 更新当前帧位置
        UInt32 bytesPerFrame = (self.bitsPerSample / 8) * self.channels;
        _currentFrame += bytesRead / bytesPerFrame;
    } else {
        // 播放完成
        NSLog(@"📖 读取完成，文件结束");
        [self handlePlaybackFinished];
    }
}

- (void)play {
    if (_isPlaying) {
        NSLog(@"⚠️ 已在播放中");
        return;
    }
    
    if (!_audioQueue) {
        NSLog(@"❌ AudioQueue未初始化");
        return;
    }
    
    NSLog(@"🎵 准备播放 - 当前帧: %lld, 总帧: %lld", _currentFrame, _totalFrames);
    
    // 如果是从头开始播放或播放完了，重置文件指针
    if (_currentFrame == 0 || feof(_pcmFile)) {
        NSLog(@"🔄 重置文件指针到开头");
        fseek(_pcmFile, 0, SEEK_SET);
        _currentFrame = 0;
        clearerr(_pcmFile); // 清除EOF标志
    }
    
    // 先设置为播放状态（重要：在填充缓冲区之前）
    _isPlaying = YES;
    
    // 填充初始缓冲区
    NSLog(@"📦 填充初始缓冲区...");
    for (int i = 0; i < kBufferCount; i++) {
        NSLog(@"📦 填充缓冲区 %d/%d", i+1, kBufferCount);
        [self fillBuffer:_buffers[i]];
    }
    
    // 启动AudioQueue
    OSStatus status = AudioQueueStart(_audioQueue, NULL);
    if (status != noErr) {
        NSLog(@"❌ AudioQueue启动失败: %d", (int)status);
        _isPlaying = NO;
        return;
    }
    
    NSLog(@"✅ AudioQueue启动成功");
    
    // 启动进度更新定时器
    [self startProgressTimer];
    
    NSLog(@"▶️ 开始播放PCM");
}

- (void)pause {
    if (!_isPlaying) {
        return;
    }
    
    _isPlaying = NO;
    AudioQueuePause(_audioQueue);
    [self stopProgressTimer];
    
    NSLog(@"⏸️ 暂停播放");
}

- (void)stop {
    if (!_audioQueue) {
        return;
    }
    
    _isPlaying = NO;
    AudioQueueStop(_audioQueue, YES);
    
    // 重置文件指针
    if (_pcmFile) {
        fseek(_pcmFile, 0, SEEK_SET);
        _currentFrame = 0;
    }
    
    [self stopProgressTimer];
    
    NSLog(@"⏹️ 停止播放");
}

- (void)seekToTime:(NSTimeInterval)time {
    if (!_pcmFile) {
        return;
    }
    
    // 计算目标帧
    SInt64 targetFrame = (SInt64)(time * self.sampleRate);
    targetFrame = MIN(targetFrame, _totalFrames);
    targetFrame = MAX(0, targetFrame);
    
    // 计算字节偏移
    UInt32 bytesPerFrame = (self.bitsPerSample / 8) * self.channels;
    long offset = targetFrame * bytesPerFrame;
    
    // 跳转到目标位置
    fseek(_pcmFile, offset, SEEK_SET);
    _currentFrame = targetFrame;
    
    NSLog(@"⏩ 跳转到 %.2f 秒", time);
}

- (void)handlePlaybackFinished {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self stop];
        
        if ([self.delegate respondsToSelector:@selector(audioPlayerDidFinishPlaying)]) {
            [self.delegate audioPlayerDidFinishPlaying];
        }
        
        NSLog(@"✅ 播放完成");
    });
}

#pragma mark - 进度更新

- (void)startProgressTimer {
    [self stopProgressTimer];
    
    self.progressTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                          target:self
                                                        selector:@selector(updateProgress)
                                                        userInfo:nil
                                                         repeats:YES];
}

- (void)stopProgressTimer {
    if (self.progressTimer) {
        [self.progressTimer invalidate];
        self.progressTimer = nil;
    }
}

- (void)updateProgress {
    if ([self.delegate respondsToSelector:@selector(audioPlayerDidUpdateProgress:currentTime:)]) {
        float progress = [self currentTime] / [self duration];
        [self.delegate audioPlayerDidUpdateProgress:progress currentTime:[self currentTime]];
    }
}

#pragma mark - 属性

- (BOOL)isPlaying {
    return _isPlaying;
}

- (NSTimeInterval)duration {
    if (_totalFrames == 0 || self.sampleRate == 0) {
        return 0;
    }
    return (NSTimeInterval)_totalFrames / self.sampleRate;
}

- (NSTimeInterval)currentTime {
    if (_currentFrame == 0 || self.sampleRate == 0) {
        return 0;
    }
    return (NSTimeInterval)_currentFrame / self.sampleRate;
}

#pragma mark - 清理

- (void)dealloc {
    [self stop];
    
    if (_audioQueue) {
        AudioQueueDispose(_audioQueue, YES);
        _audioQueue = NULL;
    }
    
    if (_pcmFile) {
        fclose(_pcmFile);
        _pcmFile = NULL;
    }
    
    NSLog(@"🗑️ PCMAudioPlayer dealloc");
}

@end

