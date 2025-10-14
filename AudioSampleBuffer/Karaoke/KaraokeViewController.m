//
//  KaraokeViewController.m
//  AudioSampleBuffer
//
//  Created on 2025/10/14.
//

#import "KaraokeViewController.h"
#import "AudioSpectrumPlayer.h"
#import "LyricsView.h"
#import "LRCParser.h"
#import "KaraokeAudioEngine.h"
#import "RecordingListViewController.h"
#import "RecordingPlaybackView.h"
#import "AudioMixer.h"
#import <AVFoundation/AVFoundation.h>

@interface KaraokeViewController () <AudioSpectrumPlayerDelegate, AVAudioRecorderDelegate, KaraokeAudioEngineDelegate>

// UI 组件
@property (nonatomic, strong) UILabel *songTitleLabel;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UIProgressView *rmsProgressView;
@property (nonatomic, strong) UIProgressView *peakProgressView;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UILabel *lyricsLabel;

// 耳返控制UI
@property (nonatomic, strong) UISwitch *earReturnSwitch;
@property (nonatomic, strong) UILabel *earReturnLabel;
@property (nonatomic, strong) UISlider *earReturnVolumeSlider;
@property (nonatomic, strong) UILabel *earReturnVolumeLabel;
@property (nonatomic, strong) UISlider *microphoneVolumeSlider;
@property (nonatomic, strong) UILabel *microphoneVolumeLabel;
@property (nonatomic, strong) UISlider *bgmVolumeSlider;  // 新增：BGM音量控制
@property (nonatomic, strong) UILabel *bgmVolumeLabel;

// 音频系统
@property (nonatomic, strong) AudioSpectrumPlayer *player;
@property (nonatomic, strong) AVAudioRecorder *audioRecorder;
@property (nonatomic, strong) AVAudioSession *audioSession;
@property (nonatomic, strong) KaraokeAudioEngine *karaokeAudioEngine;

// 录音相关
@property (nonatomic, strong) NSString *recordingFilePath;
@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, assign) BOOL isPlaying;

// 回放相关
@property (nonatomic, strong) AVAudioPlayer *playbackPlayer;
@property (nonatomic, strong) NSTimer *playbackUpdateTimer;
@property (nonatomic, strong) RecordingPlaybackView *recordingPlaybackView;

// 定时器
@property (nonatomic, strong) NSTimer *updateTimer;
@property (nonatomic, strong) CADisplayLink *displayLink;

// 歌词
@property (nonatomic, strong) LyricsView *lyricsView;
@property (nonatomic, strong) LRCParser *lyricsParser;

@end

@implementation KaraokeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSLog(@"🎬 KaraokeViewController viewDidLoad 开始");
    
    NSLog(@"📱 Step 1: setupUI");
    [self setupUI];
    
    NSLog(@"📱 Step 2: setupAudioSession");
    [self setupAudioSession];  // 这会异步请求权限
    
    NSLog(@"📱 Step 3: setupPlayer");
    [self setupPlayer];
    
    NSLog(@"📱 Step 4: loadCurrentSong");
    [self loadCurrentSong];
    
    NSLog(@"📱 Step 5: 发送通知");
    // 发送通知，停止外层音频播放
    [[NSNotificationCenter defaultCenter] postNotificationName:@"KaraokeModeDidStart" object:nil];
    NSLog(@"🎤 卡拉OK模式开始，通知主界面停止播放");
    
    NSLog(@"✅ KaraokeViewController viewDidLoad 完成");
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self startUpdateTimer];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopUpdateTimer];
    [self stopRecording];
    
    // 停止卡拉OK音频引擎
    if (self.karaokeAudioEngine) {
        [self.karaokeAudioEngine stop];
        [self.karaokeAudioEngine stopRecording];
    }
    
//    // 发送通知，恢复外层音频播放
//    [[NSNotificationCenter defaultCenter] postNotificationName:@"KaraokeModeDidEnd" object:nil];
//    NSLog(@"🎤 卡拉OK模式结束，通知主界面恢复播放");
}

- (void)dealloc {
    [self stopUpdateTimer];
    [self stopRecording];
    
    if (self.karaokeAudioEngine) {
        [self.karaokeAudioEngine stop];
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    NSLog(@"🗑️ KaraokeViewController dealloc");
}

#pragma mark - UI Setup

- (void)setupUI {
    self.view.backgroundColor = [UIColor blackColor];
    self.title = @"卡拉OK模式";
    
    // 添加返回按钮
    UIBarButtonItem *backButton = [[UIBarButtonItem alloc] initWithTitle:@"返回" 
                                                                   style:UIBarButtonItemStylePlain 
                                                                  target:self 
                                                                  action:@selector(backButtonTapped)];
    self.navigationItem.leftBarButtonItem = backButton;
    
    // 添加录音列表按钮
    UIBarButtonItem *listButton = [[UIBarButtonItem alloc] initWithTitle:@"📝 录音列表" 
                                                                   style:UIBarButtonItemStylePlain 
                                                                  target:self 
                                                                  action:@selector(showRecordingList)];
    self.navigationItem.rightBarButtonItem = listButton;
    
    // 歌曲标题
    self.songTitleLabel = [[UILabel alloc] init];
    self.songTitleLabel.text = self.currentSongName ?: @"未知歌曲";
    self.songTitleLabel.textColor = [UIColor whiteColor];
    self.songTitleLabel.font = [UIFont boldSystemFontOfSize:20];
    self.songTitleLabel.textAlignment = NSTextAlignmentCenter;
    self.songTitleLabel.frame = CGRectMake(20, 100, self.view.bounds.size.width - 40, 30);
    [self.view addSubview:self.songTitleLabel];
    
    // 进度条
    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.progressTintColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    self.progressView.trackTintColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    self.progressView.frame = CGRectMake(20, 150, self.view.bounds.size.width - 40, 20);
    [self.view addSubview:self.progressView];
    
    // 时间标签
    self.durationLabel = [[UILabel alloc] init];
    self.durationLabel.text = @"0:00 / 0:00";
    self.durationLabel.textColor = [UIColor whiteColor];
    self.durationLabel.font = [UIFont systemFontOfSize:14];
    self.durationLabel.textAlignment = NSTextAlignmentCenter;
    self.durationLabel.frame = CGRectMake(20, 180, self.view.bounds.size.width - 40, 20);
    [self.view addSubview:self.durationLabel];
    
    // VU Meter 标签
    UILabel *vuLabel = [[UILabel alloc] init];
    vuLabel.text = @"麦克风音量";
    vuLabel.textColor = [UIColor whiteColor];
    vuLabel.font = [UIFont systemFontOfSize:16];
    vuLabel.frame = CGRectMake(20, 220, 120, 20);
    [self.view addSubview:vuLabel];
    
    // RMS 进度条
    self.rmsProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.rmsProgressView.progressTintColor = [UIColor greenColor];
    self.rmsProgressView.trackTintColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    self.rmsProgressView.frame = CGRectMake(20, 250, self.view.bounds.size.width - 40, 10);
    [self.view addSubview:self.rmsProgressView];
    
    // Peak 进度条
    self.peakProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.peakProgressView.progressTintColor = [UIColor redColor];
    self.peakProgressView.trackTintColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    self.peakProgressView.frame = CGRectMake(20, 270, self.view.bounds.size.width - 40, 10);
    [self.view addSubview:self.peakProgressView];
    
    // 开始/完成按钮
    self.startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.startButton setTitle:@"开始录音" forState:UIControlStateNormal];
    [self.startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0];
    self.startButton.layer.cornerRadius = 25;
    self.startButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.startButton.frame = CGRectMake(50, 320, self.view.bounds.size.width - 100, 50);
    [self.startButton addTarget:self action:@selector(startButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.startButton];
    
    // 耳返控制界面（确保在最上层）
    [self setupEarReturnControls];
    
    // 歌词视图
    [self setupLyricsView];
}

- (void)setupLyricsView {
    CGFloat lyricsY = self.view.bounds.size.height - 150;
    self.lyricsView = [[LyricsView alloc] initWithFrame:CGRectMake(20, lyricsY, self.view.bounds.size.width - 40, 120)];
    self.lyricsView.backgroundColor = [UIColor clearColor];
    self.lyricsView.highlightColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    self.lyricsView.normalColor = [UIColor colorWithWhite:1.0 alpha:0.6];
    self.lyricsView.highlightFont = [UIFont boldSystemFontOfSize:18];
    self.lyricsView.lyricsFont = [UIFont systemFontOfSize:16];
    self.lyricsView.lineSpacing = 20;
    self.lyricsView.autoScroll = YES;
    [self.view addSubview:self.lyricsView];
}

- (void)setupEarReturnControls {
    CGFloat startY = 380;
    CGFloat spacing = 50;
    
    // 耳返开关
    self.earReturnLabel = [[UILabel alloc] init];
    self.earReturnLabel.text = @"🎧 耳返";
    self.earReturnLabel.textColor = [UIColor whiteColor];
    self.earReturnLabel.font = [UIFont systemFontOfSize:16];
    self.earReturnLabel.frame = CGRectMake(20, startY, 80, 30);
    [self.view addSubview:self.earReturnLabel];
    
    self.earReturnSwitch = [[UISwitch alloc] init];
    self.earReturnSwitch.on = YES; // 默认开启耳返
    self.earReturnSwitch.frame = CGRectMake(110, startY, 0, 0);
    [self.earReturnSwitch addTarget:self action:@selector(earReturnSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.earReturnSwitch];
    
    // 耳返音量滑块
    self.earReturnVolumeLabel = [[UILabel alloc] init];
    self.earReturnVolumeLabel.text = @"耳返音量";
    self.earReturnVolumeLabel.textColor = [UIColor whiteColor];
    self.earReturnVolumeLabel.font = [UIFont systemFontOfSize:14];
    self.earReturnVolumeLabel.frame = CGRectMake(20, startY + spacing, 80, 20);
    [self.view addSubview:self.earReturnVolumeLabel];
    
    self.earReturnVolumeSlider = [[UISlider alloc] init];
    self.earReturnVolumeSlider.minimumValue = 0.0;
    self.earReturnVolumeSlider.maximumValue = 1.0;
    self.earReturnVolumeSlider.value = 0.5; // 默认50%
    self.earReturnVolumeSlider.frame = CGRectMake(110, startY + spacing, self.view.bounds.size.width - 130, 20);
    self.earReturnVolumeSlider.userInteractionEnabled = YES; // 确保可交互
    [self.earReturnVolumeSlider addTarget:self action:@selector(earReturnVolumeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.earReturnVolumeSlider];
    
    // 麦克风音量滑块
    self.microphoneVolumeLabel = [[UILabel alloc] init];
    self.microphoneVolumeLabel.text = @"麦克风音量";
    self.microphoneVolumeLabel.textColor = [UIColor whiteColor];
    self.microphoneVolumeLabel.font = [UIFont systemFontOfSize:14];
    self.microphoneVolumeLabel.frame = CGRectMake(20, startY + spacing * 2, 80, 20);
    [self.view addSubview:self.microphoneVolumeLabel];
    
    self.microphoneVolumeSlider = [[UISlider alloc] init];
    self.microphoneVolumeSlider.minimumValue = 0.0;
    self.microphoneVolumeSlider.maximumValue = 1.0;
    self.microphoneVolumeSlider.value = 1.0; // 默认100%
    self.microphoneVolumeSlider.frame = CGRectMake(110, startY + spacing * 2, self.view.bounds.size.width - 130, 20);
    self.microphoneVolumeSlider.userInteractionEnabled = YES; // 确保可交互
    [self.microphoneVolumeSlider addTarget:self action:@selector(microphoneVolumeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.microphoneVolumeSlider];
    
    // BGM音量滑块
    self.bgmVolumeLabel = [[UILabel alloc] init];
    self.bgmVolumeLabel.text = @"🎵 BGM音量";
    self.bgmVolumeLabel.textColor = [UIColor whiteColor];
    self.bgmVolumeLabel.font = [UIFont systemFontOfSize:14];
    self.bgmVolumeLabel.frame = CGRectMake(20, startY + spacing * 3, 100, 20);
    [self.view addSubview:self.bgmVolumeLabel];
    
    self.bgmVolumeSlider = [[UISlider alloc] init];
    self.bgmVolumeSlider.minimumValue = 0.0;
    self.bgmVolumeSlider.maximumValue = 1.0;
    self.bgmVolumeSlider.value = 0.3; // 默认30% - 避免反馈
    self.bgmVolumeSlider.frame = CGRectMake(110, startY + spacing * 3, self.view.bounds.size.width - 130, 20);
    self.bgmVolumeSlider.userInteractionEnabled = YES; // 确保可交互
    [self.bgmVolumeSlider addTarget:self action:@selector(bgmVolumeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.bgmVolumeSlider];
    
    NSLog(@"✅ 耳返控制界面已创建，所有滑块已启用交互");
}

#pragma mark - Audio Setup

- (void)setupAudioSession {
    // 注意：音频会话由KaraokeAudioEngine管理，这里只做权限检查
    self.audioSession = [AVAudioSession sharedInstance];
    
    // 请求麦克风权限
    [self.audioSession requestRecordPermission:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (granted) {
                NSLog(@"✅ 麦克风权限已授权");
            } else {
                NSLog(@"❌ 麦克风权限被拒绝");
                [self showMicrophonePermissionAlert];
            }
        });
    }];
    
    NSLog(@"✅ 音频会话由KaraokeAudioEngine统一管理");
}


- (void)showMicrophonePermissionAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"需要麦克风权限" 
                                                                   message:@"卡拉OK功能需要访问麦克风来录制您的声音。请在设置中允许麦克风权限。" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:@"去设置" 
                                                             style:UIAlertActionStyleDefault 
                                                           handler:^(UIAlertAction * _Nonnull action) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] 
                                           options:@{} 
                                 completionHandler:nil];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" 
                                                           style:UIAlertActionStyleCancel 
                                                         handler:nil];
    
    [alert addAction:settingsAction];
    [alert addAction:cancelAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setupAudioRecorder {
    // 设置录音文件路径
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *fileName = [NSString stringWithFormat:@"karaoke_recording_%@.m4a", 
                         [[NSDate date] description]];
    self.recordingFilePath = [documentsDirectory stringByAppendingPathComponent:fileName];
    
    // 确保目录存在
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:documentsDirectory]) {
        [fileManager createDirectoryAtPath:documentsDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    // 录音设置 - 使用更兼容的设置
    NSDictionary *recordSettings = @{
        AVFormatIDKey: @(kAudioFormatMPEG4AAC),
        AVSampleRateKey: @44100.0,
        AVNumberOfChannelsKey: @1,  // 改为单声道，更稳定
        AVEncoderAudioQualityKey: @(AVAudioQualityMedium),  // 降低质量要求
        AVEncoderBitRateKey: @128000
    };
    
    NSError *error;
    self.audioRecorder = [[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:self.recordingFilePath]
                                                     settings:recordSettings
                                                        error:&error];
    
    if (error) {
        NSLog(@"❌ 创建录音器失败: %@", error.localizedDescription);
        NSLog(@"   错误详情: %@", error.userInfo);
    } else {
        NSLog(@"✅ 录音器创建成功: %@", self.recordingFilePath);
        self.audioRecorder.delegate = self;
        self.audioRecorder.meteringEnabled = YES;
        
        // 准备录音
        BOOL prepared = [self.audioRecorder prepareToRecord];
        if (prepared) {
            NSLog(@"✅ 录音器准备成功");
        } else {
            NSLog(@"❌ 录音器准备失败");
        }
    }
}

- (void)setupPlayer {
    // 创建卡拉OK音频引擎（用于BGM播放、耳返和录音）
    self.karaokeAudioEngine = [[KaraokeAudioEngine alloc] init];
    self.karaokeAudioEngine.delegate = self;
    
    // 🔧 同步 UI 滑块的初始值到音频引擎
    if (self.karaokeAudioEngine) {
        // 耳返开关
        BOOL earReturnEnabled = self.earReturnSwitch ? self.earReturnSwitch.isOn : YES;
        [self.karaokeAudioEngine setEarReturnEnabled:earReturnEnabled];
        
        // 耳返音量（从滑块读取，如果滑块还未创建则使用默认值）
        float earReturnVolume = self.earReturnVolumeSlider ? self.earReturnVolumeSlider.value : 0.5;
        [self.karaokeAudioEngine setEarReturnVolume:earReturnVolume];
        
        // 麦克风音量（从滑块读取，如果滑块还未创建则使用默认值）
        float microphoneVolume = self.microphoneVolumeSlider ? self.microphoneVolumeSlider.value : 1.0;
        [self.karaokeAudioEngine setMicrophoneVolume:microphoneVolume];
        
        // 🎵 BGM 音量（从滑块读取，如果滑块还未创建则使用默认值）
        float bgmVolume = self.bgmVolumeSlider ? self.bgmVolumeSlider.value : 0.3;
        if (self.karaokeAudioEngine.audioPlayer) {
            self.karaokeAudioEngine.audioPlayer.volume = bgmVolume;
        }
        
        NSLog(@"✅ 卡拉OK音频引擎初始音量已设置:");
        NSLog(@"   耳返: %@ (音量 %.0f%%)", earReturnEnabled ? @"开" : @"关", earReturnVolume * 100);
        NSLog(@"   麦克风音量: %.0f%%", microphoneVolume * 100);
        NSLog(@"   BGM音量: %.0f%%", bgmVolume * 100);
    }
}

- (void)loadCurrentSong {
    if (self.currentSongName) {
        // 加载到卡拉OK音频引擎（用于播放、耳返和录音）
        NSString *filePath = [[NSBundle mainBundle] pathForResource:self.currentSongName ofType:nil];
        if (filePath) {
            [self.karaokeAudioEngine loadAudioFile:filePath];
            
            // 🔧 加载完成后，同步 UI 的 BGM 音量到音频引擎
            if (self.bgmVolumeSlider && self.karaokeAudioEngine.audioPlayer) {
                float bgmVolume = self.bgmVolumeSlider.value;
                self.karaokeAudioEngine.audioPlayer.volume = bgmVolume;
                NSLog(@"🎵 已同步 UI BGM 音量到引擎: %.0f%%", bgmVolume * 100);
            }
            
            NSLog(@"✅ 音频文件已加载，等待用户点击开始录音按钮");
        } else {
            NSLog(@"❌ 未找到音频文件: %@", self.currentSongName);
        }
        
        // 加载歌词
        [self loadLyricsForSong:self.currentSongName];
    }
}

- (void)loadLyricsForSong:(NSString *)songName {
    // 尝试加载对应的歌词文件
    NSString *lyricsFileName = [[songName stringByDeletingPathExtension] stringByAppendingString:@".lrc"];
    NSString *lyricsPath = [[NSBundle mainBundle] pathForResource:lyricsFileName ofType:nil];
    
    if (lyricsPath) {
        self.lyricsParser = [[LRCParser alloc] init];
        if ([self.lyricsParser parseFromFile:lyricsPath]) {
            self.lyricsView.parser = self.lyricsParser;
            NSLog(@"✅ 卡拉OK歌词加载成功: %@", lyricsFileName);
        } else {
            NSLog(@"❌ 歌词解析失败: %@", lyricsFileName);
            self.lyricsView.parser = nil;
        }
    } else {
        NSLog(@"⚠️ 未找到歌词文件: %@", lyricsFileName);
        self.lyricsView.parser = nil;
    }
}

#pragma mark - Timer Management

- (void)startUpdateTimer {
    self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 
                                                        target:self 
                                                      selector:@selector(updateUI) 
                                                      userInfo:nil 
                                                       repeats:YES];
    
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateVUMeter)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopUpdateTimer {
    [self.updateTimer invalidate];
    self.updateTimer = nil;
    
    [self.displayLink invalidate];
    self.displayLink = nil;
}

#pragma mark - UI Updates

- (void)updateUI {
    if (self.karaokeAudioEngine && self.karaokeAudioEngine.audioPlayer) {
        // 更新进度条 - 使用基于 BGM 读取位置的时间
        NSTimeInterval currentTime = self.karaokeAudioEngine.currentPlaybackTime;
        NSTimeInterval duration = self.karaokeAudioEngine.audioPlayer.duration;
        float progress = duration > 0 ? (float)(currentTime / duration) : 0.0f;
        self.progressView.progress = progress;
        
        // 更新时间标签
        NSString *currentTimeStr = [self formatTime:currentTime];
        NSString *durationStr = [self formatTime:duration];
        self.durationLabel.text = [NSString stringWithFormat:@"%@ / %@", currentTimeStr, durationStr];
        
        // 更新歌词
        [self.lyricsView updateWithTime:currentTime];
    }
}

- (void)updateVUMeter {
    // VU表现在由KaraokeAudioEngine的回调实时更新
    // 这个方法保留用于其他可能的更新逻辑
    // 不再需要从AVAudioRecorder获取数据
}

- (NSString *)formatTime:(NSTimeInterval)time {
    int minutes = (int)time / 60;
    int seconds = (int)time % 60;
    return [NSString stringWithFormat:@"%d:%02d", minutes, seconds];
}

#pragma mark - Button Actions

- (void)startButtonTapped:(UIButton *)sender {
    if (self.isRecording) {
        // 停止录音和BGM播放
        [self stopRecording];
        
        // 停止BGM播放
        if (self.karaokeAudioEngine) {
            [self.karaokeAudioEngine stop];
            NSLog(@"🛑 BGM播放已停止");
        }
        
        [self.startButton setTitle:@"开始录音" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0];
        
        // 直接显示录音（已经包含BGM，不需要再混音）
        [self showRecordingPlaybackDialog];
    } else {
        // 开始录音和播放
        [self startKaraokeSession];
        [self.startButton setTitle:@"停止录音" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
    }
}

- (void)startKaraokeSession {
    // 使用新的音频引擎开始播放和录音
    if (self.karaokeAudioEngine) {
        [self.karaokeAudioEngine play];
        [self.karaokeAudioEngine startRecording];
        self.isRecording = YES;
        NSLog(@"🎤 卡拉OK会话开始 - 播放和录音同时进行");
    } else {
        // 回退到原来的录音方式
        [self startRecording];
    }
}

- (void)backButtonTapped {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)showRecordingList {
    NSLog(@"📝 打开录音列表");
    RecordingListViewController *listVC = [[RecordingListViewController alloc] init];
    [self.navigationController pushViewController:listVC animated:YES];
}

#pragma mark - Recording

- (void)startRecording {
    NSLog(@"🎤 尝试开始录音...");
    
    // 检查麦克风权限
    AVAudioSessionRecordPermission permission = [self.audioSession recordPermission];
    NSLog(@"   麦克风权限状态: %ld", (long)permission);
    
    // 权限状态值：0=未决定, 1=拒绝, 2=授权
    if (permission == AVAudioSessionRecordPermissionDenied) {
        NSLog(@"❌ 麦克风权限被拒绝");
        [self showMicrophonePermissionAlert];
        return;
    } else if (permission == AVAudioSessionRecordPermissionUndetermined) {
        NSLog(@"❌ 麦克风权限未决定，重新请求");
        [self.audioSession requestRecordPermission:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (granted) {
                    [self startRecording];
                } else {
                    [self showMicrophonePermissionAlert];
                }
            });
        }];
        return;
    } else if (permission != AVAudioSessionRecordPermissionGranted) {
        NSLog(@"❌ 麦克风权限状态异常: %ld", (long)permission);
        [self showMicrophonePermissionAlert];
        return;
    }
    
    // 检查录音器是否已创建
    if (!self.audioRecorder) {
        NSLog(@"❌ 录音器未创建");
        [self showRecordingErrorAlert:@"录音器未初始化，请重新进入页面"];
        return;
    }
    
    // 检查录音器是否准备就绪
    if (![self.audioRecorder prepareToRecord]) {
        NSLog(@"❌ 录音器准备失败");
        [self showRecordingErrorAlert:@"录音器准备失败，请检查设备状态"];
        return;
    }
    
    // 开始录音
    BOOL success = [self.audioRecorder record];
    if (success) {
        self.isRecording = YES;
        NSLog(@"✅ 录音开始成功: %@", self.recordingFilePath);
    } else {
        NSLog(@"❌ 录音启动失败");
        [self showRecordingErrorAlert:@"无法开始录音，请检查麦克风权限和设备状态"];
    }
}

- (void)showRecordingErrorAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"录音失败" 
                                                                   message:message 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" 
                                                       style:UIAlertActionStyleDefault 
                                                     handler:nil];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)stopRecording {
    if (self.isRecording) {
        if (self.karaokeAudioEngine) {
            [self.karaokeAudioEngine stop];
            [self.karaokeAudioEngine stopRecording];
            self.recordingFilePath = [self.karaokeAudioEngine getRecordingFilePath];
        } else {
            [self.audioRecorder stop];
        }
        self.isRecording = NO;
        NSLog(@"🛑 录音停止: %@", self.recordingFilePath);
    }
}

- (void)showRecordingPlaybackDialog {
    // 获取录音文件路径
    NSString *recordingPath = [self.karaokeAudioEngine getRecordingFilePath];
    if (!recordingPath || ![[NSFileManager defaultManager] fileExistsAtPath:recordingPath]) {
        [self showAlertWithTitle:@"错误" message:@"录音文件不存在"];
        return;
    }
    
    NSLog(@"📂 录音文件路径: %@", recordingPath);
    
    // 移除旧的回放视图（如果存在）
    if (self.recordingPlaybackView) {
        [self.recordingPlaybackView removeFromSuperview];
        self.recordingPlaybackView = nil;
    }
    
    // 创建RecordingPlaybackView
    CGFloat viewHeight = 300;
    CGFloat viewY = (self.view.bounds.size.height - viewHeight) / 2;
    
    self.recordingPlaybackView = [[RecordingPlaybackView alloc] initWithFrame:CGRectMake(20, viewY, 
                                                                                          self.view.bounds.size.width - 40, 
                                                                                          viewHeight)];
    self.recordingPlaybackView.filePath = recordingPath;
    
    // 设置回调
    __weak typeof(self) weakSelf = self;
    self.recordingPlaybackView.onClose = ^{
        [weakSelf.recordingPlaybackView removeFromSuperview];
        weakSelf.recordingPlaybackView = nil;
    };
    
    self.recordingPlaybackView.onDelete = ^(NSString *path) {
        [weakSelf.recordingPlaybackView removeFromSuperview];
        weakSelf.recordingPlaybackView = nil;
        [weakSelf showAlertWithTitle:@"删除成功" message:@"录音已删除"];
    };
    
    self.recordingPlaybackView.onExport = ^(NSString *path) {
        NSLog(@"📤 导出录音: %@", path);
    };
    
    [self.view addSubview:self.recordingPlaybackView];
    
    NSLog(@"✅ 录音回放视图已显示");
}

#pragma mark - 混音处理

- (void)mixRecordingWithBGM {
    // 获取录音文件路径
    NSString *vocalPath = [self.karaokeAudioEngine getRecordingFilePath];
    if (!vocalPath || ![[NSFileManager defaultManager] fileExistsAtPath:vocalPath]) {
        [self showAlertWithTitle:@"错误" message:@"录音文件不存在"];
        return;
    }
    
    // 获取BGM文件路径
    NSString *bgmPath = [[NSBundle mainBundle] pathForResource:self.currentSongName ofType:nil];
    if (!bgmPath) {
        NSLog(@"⚠️ 未找到BGM文件，只保存纯人声");
        [self showRecordingPlaybackDialog];
        return;
    }
    
    // 显示处理提示
    UIAlertController *processingAlert = [UIAlertController alertControllerWithTitle:@"🎵 正在处理"
                                                                             message:@"正在混合人声和背景音乐，请稍候..."
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:processingAlert animated:YES completion:nil];
    
    // 生成混音输出文件名
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *fileName = [NSString stringWithFormat:@"karaoke_mixed_%ld.pcm", (long)[[NSDate date] timeIntervalSince1970]];
    NSString *mixedPath = [documentsDirectory stringByAppendingPathComponent:fileName];
    
    NSLog(@"🎵 开始混音:");
    NSLog(@"   人声: %@", vocalPath);
    NSLog(@"   BGM: %@", bgmPath);
    NSLog(@"   输出: %@", mixedPath);
    
    // 执行混音
    [AudioMixer mixVocalFile:vocalPath
                 withBGMFile:bgmPath
                outputToFile:mixedPath
                 vocalVolume:1.0  // 人声100%
                   bgmVolume:0.3  // BGM 30% (与播放时一致)
                  completion:^(BOOL success, NSError * _Nullable error) {
        // 关闭处理提示
        [processingAlert dismissViewControllerAnimated:YES completion:^{
            if (success) {
                NSLog(@"✅ 混音成功: %@", mixedPath);
                
                // 可选：删除原始人声文件（只保留混音文件）
                // [[NSFileManager defaultManager] removeItemAtPath:vocalPath error:nil];
                
                // 显示混音后的文件
                [self showPlaybackViewForFile:mixedPath];
            } else {
                NSLog(@"❌ 混音失败: %@", error.localizedDescription);
                [self showAlertWithTitle:@"混音失败"
                                 message:[NSString stringWithFormat:@"%@\n将显示纯人声录音", error.localizedDescription]];
                
                // 失败时显示原始人声录音
                [self showRecordingPlaybackDialog];
            }
        }];
    }];
}

- (void)showPlaybackViewForFile:(NSString *)filePath {
    // 移除旧的回放视图（如果存在）
    if (self.recordingPlaybackView) {
        [self.recordingPlaybackView removeFromSuperview];
        self.recordingPlaybackView = nil;
    }
    
    // 创建RecordingPlaybackView
    CGFloat viewHeight = 300;
    CGFloat viewY = (self.view.bounds.size.height - viewHeight) / 2;
    
    self.recordingPlaybackView = [[RecordingPlaybackView alloc] initWithFrame:CGRectMake(20, viewY,
                                                                                          self.view.bounds.size.width - 40,
                                                                                          viewHeight)];
    self.recordingPlaybackView.filePath = filePath;
    
    // 设置回调
    __weak typeof(self) weakSelf = self;
    self.recordingPlaybackView.onClose = ^{
        [weakSelf.recordingPlaybackView removeFromSuperview];
        weakSelf.recordingPlaybackView = nil;
    };
    
    self.recordingPlaybackView.onDelete = ^(NSString *path) {
        [weakSelf.recordingPlaybackView removeFromSuperview];
        weakSelf.recordingPlaybackView = nil;
        [weakSelf showAlertWithTitle:@"删除成功" message:@"录音已删除"];
    };
    
    self.recordingPlaybackView.onExport = ^(NSString *path) {
        NSLog(@"📤 导出录音: %@", path);
    };
    
    [self.view addSubview:self.recordingPlaybackView];
    
    NSLog(@"✅ 录音回放视图已显示");
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title 
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showRecordingCompleteAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"录音完成" 
                                                                   message:[NSString stringWithFormat:@"录音文件已保存到:\n%@", self.recordingFilePath]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" 
                                                       style:UIAlertActionStyleDefault 
                                                     handler:nil];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - AudioSpectrumPlayerDelegate

- (void)playerDidGenerateSpectrum:(NSArray *)spectrums {
    // 性能优化：录音时不显示频谱特效，避免性能占用
    // dispatch_async(dispatch_get_main_queue(), ^{
    //     [self.spectrumView updateSpectra:spectrums withStype:ADSpectraStyleRound];
    // });
}

- (void)didFinishPlay {
    // 歌曲播放完成
    [self stopRecording];
    [self.startButton setTitle:@"开始录音" forState:UIControlStateNormal];
    self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"歌曲播放完成" 
                                                                   message:@"录音已自动停止" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" 
                                                       style:UIAlertActionStyleDefault 
                                                     handler:nil];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - AVAudioRecorderDelegate

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag {
    if (flag) {
        NSLog(@"✅ 录音成功完成");
    } else {
        NSLog(@"❌ 录音失败");
    }
}

- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder error:(NSError *)error {
    NSLog(@"❌ 录音编码错误: %@", error.localizedDescription);
}

#pragma mark - 耳返控制事件

- (void)earReturnSwitchChanged:(UISwitch *)sender {
    NSLog(@"🎧 耳返开关改变: %@", sender.on ? @"开启" : @"关闭");
    if (self.karaokeAudioEngine) {
        @try {
            [self.karaokeAudioEngine setEarReturnEnabled:sender.on];
        } @catch (NSException *exception) {
            NSLog(@"❌ 设置耳返开关异常: %@", exception.reason);
        }
    } else {
        NSLog(@"⚠️ 卡拉OK音频引擎未初始化");
    }
}

- (void)earReturnVolumeChanged:(UISlider *)sender {
    NSLog(@"🎧 耳返音量滑块改变: %.0f%%", sender.value * 100);
    if (self.karaokeAudioEngine) {
        @try {
            [self.karaokeAudioEngine setEarReturnVolume:sender.value];
        } @catch (NSException *exception) {
            NSLog(@"❌ 设置耳返音量异常: %@", exception.reason);
        }
    } else {
        NSLog(@"⚠️ 卡拉OK音频引擎未初始化");
    }
}

- (void)microphoneVolumeChanged:(UISlider *)sender {
    NSLog(@"🎤 麦克风音量滑块改变: %.0f%%", sender.value * 100);
    if (self.karaokeAudioEngine) {
        @try {
            [self.karaokeAudioEngine setMicrophoneVolume:sender.value];
        } @catch (NSException *exception) {
            NSLog(@"❌ 设置麦克风音量异常: %@", exception.reason);
        }
    } else {
        NSLog(@"⚠️ 卡拉OK音频引擎未初始化");
    }
}

- (void)bgmVolumeChanged:(UISlider *)sender {
    NSLog(@"🎵 BGM音量滑块改变: %.0f%%", sender.value * 100);
    if (self.karaokeAudioEngine && self.karaokeAudioEngine.audioPlayer) {
        self.karaokeAudioEngine.audioPlayer.volume = sender.value;
        NSLog(@"✅ BGM音量已设置为: %.0f%%", sender.value * 100);
    }
}

#pragma mark - KaraokeAudioEngineDelegate

- (void)audioEngineDidUpdateMicrophoneLevel:(float)level {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.rmsProgressView.progress = level;
    });
}

- (void)audioEngineDidUpdatePeakLevel:(float)peak {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.peakProgressView.progress = peak;
    });
}

- (void)audioEngineDidFinishPlaying {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"🎵 收到BGM播放完成通知，自动结束录音会话");
        
        if (self.isRecording) {
            self.isRecording = NO;
            
            // 更新UI
            [self.startButton setTitle:@"开始录音" forState:UIControlStateNormal];
            self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0];
            
            // 显示录音回放界面
            [self showRecordingPlaybackDialog];
        }
    });
}

- (void)audioEngineDidEncounterError:(NSError *)error {
    NSLog(@"❌ 卡拉OK音频引擎错误: %@", error.localizedDescription);
}

@end
