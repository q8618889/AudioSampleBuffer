

#import "AudioSpectrumPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import "RealtimeAnalyzer.h"

@interface AudioSpectrumPlayer ()
{
    AVAudioFramePosition lastStartFramePosition;
    dispatch_source_t _sometimer;
    dispatch_queue_t _queue;
}
@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) AVAudioPlayerNode *player;
@property (nonatomic, strong) RealtimeAnalyzer *analyzer;
@property (nonatomic, assign) int bufferSize;
@property (nonatomic,strong) AVAudioFile *file;
@property(nonatomic,assign)NSTimeInterval currentTime;
@property(nonatomic,assign)BOOL timeBegining;

@end

@implementation AudioSpectrumPlayer

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
}

- (void)setupPlayer {
    [self.engine attachNode:self.player];
    AVAudioMixerNode *mixerNode = self.engine.mainMixerNode;
    [self.engine connect:self.player to:mixerNode format:[mixerNode outputFormatForBus:0]];
    [self.engine startAndReturnError:nil];
    //在添加tap之前先移除上一个  不然有可能报"Terminating ap  p due to uncaught exception 'com.apple.coreaudio.avfaudio',"之类的错误
    [mixerNode removeTapOnBus:0];
    [mixerNode installTapOnBus:0 bufferSize:self.bufferSize format:[mixerNode outputFormatForBus:0] block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
        if (!self.player.isPlaying) return ;
        buffer.frameLength = self.bufferSize;
        NSArray *spectrums = [self.analyzer analyse:buffer withAmplitudeLevel:5];
        if ([self.delegate respondsToSelector:@selector(playerDidGenerateSpectrum:)]) {
            [self.delegate playerDidGenerateSpectrum:spectrums];
        }
    }];


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
    NSURL *fileUrl = [[NSBundle mainBundle] URLForResource:fileName withExtension:nil];
    NSError *error = nil;
    self.file = [[AVAudioFile alloc] initForReading:fileUrl error:&error];
    if (error) {
        NSLog(@"create AVAudioFile error: %@", error);
        return;
    }
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
}

//开始倒计时
- (void)countDownBegin:(NSInteger)sender{
    _timeBegining = YES;
    if (_queue ==nil)
    {
        _queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0);
        _sometimer= dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0, _queue);
        
    }
    __block int time = (int)sender;
    dispatch_source_set_timer(_sometimer, dispatch_walltime(NULL,0),1.0*NSEC_PER_SEC,0);// 每秒执行一次
    dispatch_source_set_event_handler(_sometimer, ^{
        int interval = (int)time;
        if(interval >0) {// 更新倒计时
      
           
            int minutes = (time%3600)/60;
            int seconds = time % 60;
            NSString *strTime;
           strTime= [NSString stringWithFormat:@"%.2d:%.2d",minutes,seconds];
            dispatch_async(dispatch_get_main_queue(), ^{
                 
            });
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
                           time--;
                    
    });
    
    dispatch_resume(_sometimer);
    
}
- (void)stop {
    [self.player stop];
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

@end
