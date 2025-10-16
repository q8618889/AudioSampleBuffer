

#import "AudioSpectrumPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import "RealtimeAnalyzer.h"
#import "LyricsManager.h"
#import "LRCParser.h"

@interface AudioSpectrumPlayer ()
{
    AVAudioFramePosition lastStartFramePosition;
    dispatch_source_t _sometimer;
    dispatch_queue_t _queue;
}
@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) AVAudioPlayerNode *player;
@property (nonatomic, strong) AVAudioUnitTimePitch *timePitchNode;  // 🎵 音高/速率调整节点
@property (nonatomic, strong) RealtimeAnalyzer *analyzer;
@property (nonatomic, assign) int bufferSize;
@property (nonatomic, strong) AVAudioFile *file;
@property (nonatomic, assign) NSTimeInterval currentTime;
@property (nonatomic, assign) BOOL timeBegining;
@property (nonatomic, strong) NSString *currentFilePath;  // 当前播放文件路径
@property (nonatomic, strong, readwrite) LRCParser *lyricsParser;  // 歌词解析器

@end

@implementation AudioSpectrumPlayer

@synthesize duration = _duration;

- (instancetype)init {
    if (self = [super init]) {
        [self configInit];
        [self setupPlayer];
    }
    return self;
}

- (void)configInit {
    self.bufferSize = 2048;
    self.analyzer = [[RealtimeAnalyzer alloc] initWithFFTSize:self.bufferSize];
    self.enableLyrics = YES;  // 默认启用歌词
    
    // 🎵 初始化音高/速率参数
    _pitchShift = 0.0f;      // 默认原调
    _playbackRate = 1.0f;    // 默认原速
}

- (void)setupPlayer {
    // 🔧 关键修复：配置音频会话
    NSError *sessionError = nil;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    // 设置音频会话类别为播放
    [audioSession setCategory:AVAudioSessionCategoryPlayback 
                  withOptions:AVAudioSessionCategoryOptionMixWithOthers 
                        error:&sessionError];
    if (sessionError) {
        NSLog(@"⚠️ 音频会话配置失败: %@", sessionError);
        sessionError = nil;
    }
    
    // 激活音频会话
    [audioSession setActive:YES error:&sessionError];
    if (sessionError) {
        NSLog(@"⚠️ 音频会话激活失败: %@", sessionError);
        sessionError = nil;
    } else {
        NSLog(@"✅ 音频会话已激活: 类别=%@, 采样率=%.0fHz", audioSession.category, audioSession.sampleRate);
    }
    
    [self.engine attachNode:self.player];
    [self.engine attachNode:self.timePitchNode];
    
    AVAudioMixerNode *mixerNode = self.engine.mainMixerNode;
    
    // ⚠️ 关键修复：不要在连接前获取格式，连接时使用 nil 让系统自动协商格式
    // 🎵 音频链路：player → timePitch → mixer
    [self.engine connect:self.player to:self.timePitchNode format:nil];
    [self.engine connect:self.timePitchNode to:mixerNode format:nil];
    
    NSError *error = nil;
    if (![self.engine startAndReturnError:&error]) {
        NSLog(@"❌ AudioEngine 启动失败: %@", error);
        return;
    }
    
    // 在引擎启动后获取实际格式
    AVAudioFormat *format = [mixerNode outputFormatForBus:0];
    
    //在添加tap之前先移除上一个  不然有可能报"Terminating app due to uncaught exception 'com.apple.coreaudio.avfaudio',"之类的错误
    [mixerNode removeTapOnBus:0];
    [mixerNode installTapOnBus:0 bufferSize:self.bufferSize format:format block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
        if (!self.player.isPlaying) return ;
        buffer.frameLength = self.bufferSize;
        NSArray *spectrums = [self.analyzer analyse:buffer withAmplitudeLevel:5];
        if ([self.delegate respondsToSelector:@selector(playerDidGenerateSpectrum:)]) {
            [self.delegate playerDidGenerateSpectrum:spectrums];
        }
    }];

    NSLog(@"✅ AudioSpectrumPlayer 音频链路已建立: player → timePitch → mixer");
    NSLog(@"   格式: %.0f Hz, %u 声道", format.sampleRate, (unsigned int)format.channelCount);
}
- (NSTimeInterval)audioDurationFromURL:(NSString *)url {
    AVURLAsset *audioAsset = nil;
    NSDictionary *dic = @{AVURLAssetPreferPreciseDurationAndTimingKey:@(YES)};
    if ([url hasPrefix:@"http://"]) {
        audioAsset = [AVURLAsset URLAssetWithURL:[NSURL URLWithString:url] options:dic];
    }else {
        audioAsset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:url] options:dic];
    }
    CMTime audioDuration = audioAsset.duration;
    float audioDurationSeconds = CMTimeGetSeconds(audioDuration);
    return audioDurationSeconds;
}
//- (void)setCurrentTime:(NSTimeInterval)currentTime {
//    _currentTime = currentTime;
//    BOOL isPlaying = self.isPlaying;
//    [self.player stop]; // 先停下来
//    __weak typeof(self) weself = self;
//    AVAudioFramePosition startingFrame = currentTime * self.file.processingFormat.sampleRate;
//    // 要根据总时长和当前进度，找出起始的frame位置和剩余的frame数量
//    AVAudioFrameCount frameCount = (AVAudioFrameCount)(self.file.length - startingFrame);
//    if (frameCount > 1000) { // 当剩余数量小于0时会crash，随便设个数
//        lastStartFramePosition = startingFrame;
//        [self.player scheduleSegment:self.file startingFrame:startingFrame frameCount:frameCount atTime:nil completionHandler:^{
//            [weself didFinishPlay];
//        }]; // 这里只有这个scheduleSegement的方法播放快进后的“片段”
//    }
//    if (isPlaying) {
//        [self.player play]; // 恢复播放
//    }
//}
- (void)playWithFileName:(NSString *)fileName {
    // 立即清空旧歌词，避免短暂显示上一首歌的歌词
    self.lyricsParser = nil;
    if ([self.delegate respondsToSelector:@selector(playerDidLoadLyrics:)]) {
        [self.delegate playerDidLoadLyrics:nil];
    }
    
    // 🔧 修复：支持完整路径和文件名两种方式
    NSURL *fileUrl = nil;
    
    if ([fileName hasPrefix:@"/"]) {
        // 如果是完整路径（以 / 开头），直接使用
        fileUrl = [NSURL fileURLWithPath:fileName];
        NSLog(@"🎵 使用完整路径播放: %@", fileName);
    } else {
        // 如果是文件名，从 Bundle 中查找
        fileUrl = [[NSBundle mainBundle] URLForResource:fileName withExtension:nil];
        NSLog(@"🎵 从 Bundle 加载: %@", fileName);
    }
    
    if (!fileUrl) {
        NSLog(@"❌ 找不到音频文件: %@", fileName);
        return;
    }
    
    NSError *error = nil;
    self.file = [[AVAudioFile alloc] initForReading:fileUrl error:&error];
    if (error) {
        NSLog(@"❌ 创建 AVAudioFile 失败: %@", error);
        NSLog(@"   文件路径: %@", fileUrl.path);
        NSLog(@"   文件是否存在: %@", [[NSFileManager defaultManager] fileExistsAtPath:fileUrl.path] ? @"是" : @"否");
        return;
    }
    
    // 保存当前文件路径
    self.currentFilePath = fileUrl.path;
    
    [self.player stop];
    [self.player scheduleFile:self.file atTime:nil completionHandler:nil];
    if (self.engine.isRunning == YES)
    {
        [self.player play];
    }else{
        [self.engine startAndReturnError:nil];
        [self.player play];
        
    }
  
    
//    AVAudioTime *playerTime = [self.player playerTimeForNodeTime:self.player.lastRenderTime];
//    NSLog(@"%llu" ,playerTime.audioTimeStamp);
//    NSLog(@"%llu",playerTime.hostTime);
    
    AVAudioFrameCount frameCount = (AVAudioFrameCount)self.file.length;
    double sampleRate = self.file.processingFormat.sampleRate;
    self.duration = frameCount / sampleRate;
    
    
    
    
    AVAudioTime *playerTime = [self.player playerTimeForNodeTime:self.player.lastRenderTime];
    _currentTime = (lastStartFramePosition + playerTime.sampleTime) / playerTime.sampleRate;
    // 倒计时结束，关闭
    if (_sometimer != nil)
    {
        dispatch_source_cancel(self->_sometimer);
        self->_queue = nil;
        self->_sometimer = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            
            self->_timeBegining = NO;
        });
    }
 
    [self countDownBegin:(NSInteger)self.duration];
    
    // 加载歌词
    if (self.enableLyrics) {
        [self loadLyricsForCurrentTrack];
    }
}

//开始倒计时
- (void)countDownBegin:(NSInteger)sender{
    _timeBegining = YES;
    if (_queue ==nil)
    {
        _queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0);
        _sometimer= dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0, _queue);
        
    }
    __block NSTimeInterval totalDuration = (NSTimeInterval)sender;
    __block NSTimeInterval elapsedTime = 0;
    
    // 🔧 关键修复：改为每0.1秒更新一次，提高歌词同步精度（10倍于原来）
    dispatch_source_set_timer(_sometimer, dispatch_walltime(NULL,0), 0.1*NSEC_PER_SEC, 0);
    
    dispatch_source_set_event_handler(_sometimer, ^{
        if(elapsedTime < totalDuration) {// 继续播放
            dispatch_async(dispatch_get_main_queue(), ^{
                // 更新当前播放时间（更精确，0.1秒级别）
                self->_currentTime = elapsedTime;
                
                // 通知代理时间更新（用于歌词同步）
                if ([self.delegate respondsToSelector:@selector(playerDidUpdateTime:)]) {
                    [self.delegate playerDidUpdateTime:elapsedTime];
                }
            });
            
            // 以0.1秒为单位递增
            elapsedTime += 0.1;
        }else{
            // 倒计时结束，关闭
            dispatch_source_cancel(self->_sometimer);
            self->_queue = nil;
            self->_sometimer = nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_timeBegining = NO;
                [self.delegate didFinishPlay];
            });
        }
    });
    
    dispatch_resume(_sometimer);
    
}
- (void)stop {
    [self.player stop];
    
    // 停止时清除歌词
    self.lyricsParser = nil;
}

#pragma mark - Lyrics

- (void)loadLyricsForCurrentTrack {
    if (!self.currentFilePath) {
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    [[LyricsManager sharedManager] fetchLyricsForAudioFile:self.currentFilePath
                                                completion:^(LRCParser *parser, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        // ⚠️ 关键修复：确保代理回调在主线程执行
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSLog(@"加载歌词失败: %@", error);
                strongSelf.lyricsParser = nil;
                
                // 通知代理歌词加载失败（传入nil），以便界面显示"暂无lrc文件歌词"
                if ([strongSelf.delegate respondsToSelector:@selector(playerDidLoadLyrics:)]) {
                    [strongSelf.delegate playerDidLoadLyrics:nil];
                }
            } else {
                strongSelf.lyricsParser = parser;
                NSLog(@"歌词加载成功，共 %lu 行", (unsigned long)parser.lyrics.count);
                
                // 通知代理歌词加载完成
                if ([strongSelf.delegate respondsToSelector:@selector(playerDidLoadLyrics:)]) {
                    [strongSelf.delegate playerDidLoadLyrics:parser];
                }
            }
        });
    }];
}

- (AVAudioEngine *)engine {
    if (!_engine) {
        _engine = [[AVAudioEngine alloc] init];
    }
    return _engine;
}

- (AVAudioPlayerNode *)player {
    if (!_player) {
        _player = [[AVAudioPlayerNode alloc] init];
    }
    return _player;
}

- (AVAudioUnitTimePitch *)timePitchNode {
    if (!_timePitchNode) {
        _timePitchNode = [[AVAudioUnitTimePitch alloc] init];
        _timePitchNode.pitch = 0.0f;  // 默认原调（单位：cent，100 cent = 1 半音）
        _timePitchNode.rate = 1.0f;   // 默认原速
    }
    return _timePitchNode;
}

#pragma mark - 🎵 音高/速率控制

- (void)setPitchShift:(float)pitchShift {
    // 限制范围：-12 到 +12 半音
    _pitchShift = fmaxf(-12.0f, fminf(12.0f, pitchShift));
    
    // AVAudioUnitTimePitch 使用 cent 作为单位（1 半音 = 100 cents）
    self.timePitchNode.pitch = _pitchShift * 100.0f;
    
    NSLog(@"🎵 [背景音乐] 音高调整: %.1f 半音 (%.0f cents)", _pitchShift, _pitchShift * 100.0f);
}

- (void)setPlaybackRate:(float)playbackRate {
    // 限制范围：0.5 到 2.0
    _playbackRate = fmaxf(0.5f, fminf(2.0f, playbackRate));
    
    self.timePitchNode.rate = _playbackRate;
    
    NSLog(@"🎵 [背景音乐] 速率调整: %.2fx", _playbackRate);
}

@end
