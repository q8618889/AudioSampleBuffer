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
#import <AudioToolbox/AudioToolbox.h>

// 错误检查宏
static void CheckError(OSStatus error, const char *operation) {
    if (error == noErr) return;
    NSLog(@"❌ Error: %s (%d)", operation, (int)error);
}

@interface KaraokeViewController () <AudioSpectrumPlayerDelegate, AVAudioRecorderDelegate, KaraokeAudioEngineDelegate, LyricsViewDelegate>

// UI 组件
@property (nonatomic, strong) UILabel *songTitleLabel;
@property (nonatomic, strong) UISlider *progressSlider;  // 🆕 可拖动的进度条
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UIProgressView *rmsProgressView;
@property (nonatomic, strong) UIProgressView *peakProgressView;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UILabel *lyricsLabel;

// 🆕 分段录音控制UI
@property (nonatomic, strong) UIButton *pauseButton;      // 暂停/恢复录音按钮
@property (nonatomic, strong) UIButton *rewindButton;     // 回退按钮
@property (nonatomic, strong) UIButton *finishButton;     // 完成录音按钮（改为停止录音）
@property (nonatomic, strong) UILabel *segmentInfoLabel;  // 段落信息标签

// 🆕 预览和试听UI
@property (nonatomic, strong) UIButton *previewButton;    // 试听按钮
@property (nonatomic, strong) UIButton *saveButton;       // 保存按钮
@property (nonatomic, strong) UIView *previewControlView;  // 预览控制面板
@property (nonatomic, assign) BOOL isInPreviewMode;       // 是否处于预览模式

// 耳返控制UI
@property (nonatomic, strong) UISwitch *earReturnSwitch;
@property (nonatomic, strong) UILabel *earReturnLabel;
@property (nonatomic, strong) UISlider *earReturnVolumeSlider;
@property (nonatomic, strong) UILabel *earReturnVolumeLabel;
@property (nonatomic, strong) UISlider *microphoneVolumeSlider;
@property (nonatomic, strong) UILabel *microphoneVolumeLabel;
@property (nonatomic, strong) UISlider *bgmVolumeSlider;  // 新增：BGM音量控制
@property (nonatomic, strong) UILabel *bgmVolumeLabel;

// 音效控制UI
@property (nonatomic, strong) UIButton *voiceEffectButton;
@property (nonatomic, strong) UIView *effectSelectorView;

// 音频系统
@property (nonatomic, strong) AudioSpectrumPlayer *player;
@property (nonatomic, strong) AVAudioRecorder *audioRecorder;
@property (nonatomic, strong) AVAudioSession *audioSession;
@property (nonatomic, strong) KaraokeAudioEngine *karaokeAudioEngine;

// 录音相关
@property (nonatomic, strong) NSString *recordingFilePath;
@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, assign) NSTimeInterval recordingStartTime;  // 🆕 记录录音起始时间（用于歌词同步）

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

// 🆕 防抖定时器（避免拖动时频繁重新生成）
@property (nonatomic, strong) NSTimer *parameterUpdateDebounceTimer;

// 🆕 试听模式更新定时器
@property (nonatomic, strong) NSTimer *previewUpdateTimer;

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
    
    // 🆕 可拖动的进度滑块（替换原来的进度条）
    self.progressSlider = [[UISlider alloc] init];
    self.progressSlider.minimumValue = 0.0;
    self.progressSlider.maximumValue = 1.0;
    self.progressSlider.value = 0.0;
    self.progressSlider.frame = CGRectMake(20, 150, self.view.bounds.size.width - 40, 20);
    self.progressSlider.minimumTrackTintColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    self.progressSlider.maximumTrackTintColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    [self.progressSlider addTarget:self action:@selector(progressSliderTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.progressSlider addTarget:self action:@selector(progressSliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [self.progressSlider addTarget:self action:@selector(progressSliderTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.view addSubview:self.progressSlider];
    
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
    
    // 🆕 分段录音控制按钮组（调整位置避免与耳返控制重叠）
    CGFloat buttonY = 290;  // 向上移动30px
    CGFloat buttonWidth = (self.view.bounds.size.width - 80) / 3;
    CGFloat buttonHeight = 40;  // 稍微缩小
    CGFloat buttonSpacing = 8;
    
    // 开始/停止录音按钮
    self.startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.startButton setTitle:@"开始录音" forState:UIControlStateNormal];
    [self.startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0];
    self.startButton.layer.cornerRadius = 8;
    self.startButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.startButton.frame = CGRectMake(20, buttonY, buttonWidth, buttonHeight);
    [self.startButton addTarget:self action:@selector(startButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.startButton];
    
    // 暂停/恢复按钮
    self.pauseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.pauseButton setTitle:@"⏸️ 暂停" forState:UIControlStateNormal];
    [self.pauseButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.pauseButton.backgroundColor = [UIColor colorWithRed:1.0 green:0.6 blue:0.0 alpha:0.8];
    self.pauseButton.layer.cornerRadius = 8;
    self.pauseButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.pauseButton.frame = CGRectMake(30 + buttonWidth, buttonY, buttonWidth, buttonHeight);
    self.pauseButton.hidden = YES;  // 初始隐藏
    [self.pauseButton addTarget:self action:@selector(pauseButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.pauseButton];
    
    // 完成录音按钮
    self.finishButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.finishButton setTitle:@"✅ 完成" forState:UIControlStateNormal];
    [self.finishButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.finishButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.4 alpha:0.8];
    self.finishButton.layer.cornerRadius = 8;
    self.finishButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.finishButton.frame = CGRectMake(40 + buttonWidth * 2, buttonY, buttonWidth, buttonHeight);
    self.finishButton.hidden = YES;  // 初始隐藏
    [self.finishButton addTarget:self action:@selector(finishButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.finishButton];
    
    // 回退按钮
    self.rewindButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.rewindButton setTitle:@"⏪ 回退10秒" forState:UIControlStateNormal];
    [self.rewindButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.rewindButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.3 blue:0.3 alpha:0.8];
    self.rewindButton.layer.cornerRadius = 8;
    self.rewindButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.rewindButton.frame = CGRectMake(20, buttonY + buttonHeight + buttonSpacing, self.view.bounds.size.width - 40, 36);
    self.rewindButton.hidden = YES;  // 初始隐藏
    [self.rewindButton addTarget:self action:@selector(rewindButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.rewindButton];
    
    // 🆕 段落信息标签
    self.segmentInfoLabel = [[UILabel alloc] init];
    self.segmentInfoLabel.text = @"";
    self.segmentInfoLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    self.segmentInfoLabel.font = [UIFont systemFontOfSize:11];
    self.segmentInfoLabel.textAlignment = NSTextAlignmentCenter;
    self.segmentInfoLabel.numberOfLines = 2;
    self.segmentInfoLabel.frame = CGRectMake(20, buttonY + buttonHeight + buttonSpacing + 38, self.view.bounds.size.width - 40, 30);
    [self.view addSubview:self.segmentInfoLabel];
    
    // 耳返控制界面（确保在最上层）
    [self setupEarReturnControls];
    
    // 音效选择按钮
    [self setupVoiceEffectButton];
    
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
    self.lyricsView.userInteractionEnabled = YES;  // 启用用户交互
    self.lyricsView.delegate = self;  // 🆕 设置代理
    
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
    
    // 🆕 智能降噪开关（放在 BGM 音量下方）
    UILabel *noiseReductionLabel = [[UILabel alloc] init];
    noiseReductionLabel.text = @"🔇 智能降噪";
    noiseReductionLabel.textColor = [UIColor whiteColor];
    noiseReductionLabel.font = [UIFont systemFontOfSize:14];
    noiseReductionLabel.frame = CGRectMake(20, startY + spacing * 4, 100, 20);
    [self.view addSubview:noiseReductionLabel];
    
    UISwitch *noiseReductionSwitch = [[UISwitch alloc] init];
    noiseReductionSwitch.on = NO; // 默认关闭
    noiseReductionSwitch.onTintColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    noiseReductionSwitch.frame = CGRectMake(110, startY + spacing * 4 - 5, 51, 31);
    noiseReductionSwitch.tag = 9001; // 标记为降噪开关
    [noiseReductionSwitch addTarget:self action:@selector(noiseReductionSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:noiseReductionSwitch];
    
    // 🆕 音高调节（放在降噪开关下方）
    UILabel *pitchShiftLabel = [[UILabel alloc] init];
    pitchShiftLabel.text = @"🎵 音高: 0半音";
    pitchShiftLabel.textColor = [UIColor whiteColor];
    pitchShiftLabel.font = [UIFont systemFontOfSize:14];
    pitchShiftLabel.frame = CGRectMake(20, startY + spacing * 5, 100, 20);
    pitchShiftLabel.tag = 9002; // 标记为音高标签
    [self.view addSubview:pitchShiftLabel];
    
    UISlider *pitchShiftSlider = [[UISlider alloc] init];
    pitchShiftSlider.minimumValue = -6.0f;
    pitchShiftSlider.maximumValue = 6.0f;
    pitchShiftSlider.value = 0.0f;
    pitchShiftSlider.minimumTrackTintColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    pitchShiftSlider.frame = CGRectMake(110, startY + spacing * 5, self.view.bounds.size.width - 130, 20);
    pitchShiftSlider.tag = 9003; // 标记为音高滑块
    pitchShiftSlider.userInteractionEnabled = YES;
    [pitchShiftSlider addTarget:self action:@selector(pitchShiftSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:pitchShiftSlider];
    
    NSLog(@"✅ 耳返控制界面已创建，所有滑块已启用交互");
    NSLog(@"✅ 智能降噪开关已添加到主界面");
    NSLog(@"✅ 音高调节滑块已添加到主界面");
}

- (void)setupVoiceEffectButton {
    // 创建音效选择按钮
    CGFloat buttonWidth = 140;
    CGFloat buttonHeight = 44;
    CGFloat buttonX = self.view.bounds.size.width - buttonWidth - 20;
    CGFloat buttonY = 100;
    
    self.voiceEffectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.voiceEffectButton setTitle:@"🎤 音效：原声" forState:UIControlStateNormal];
    [self.voiceEffectButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.voiceEffectButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.4 blue:0.8 alpha:0.8];
    self.voiceEffectButton.layer.cornerRadius = 22;
    self.voiceEffectButton.layer.borderWidth = 1;
    self.voiceEffectButton.layer.borderColor = [UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:1.0].CGColor;
    self.voiceEffectButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.voiceEffectButton.frame = CGRectMake(buttonX, buttonY, buttonWidth, buttonHeight);
    [self.voiceEffectButton addTarget:self action:@selector(showVoiceEffectSelector) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.voiceEffectButton];
    
    NSLog(@"✅ 音效选择按钮已创建");
}

- (void)showVoiceEffectSelector {
    // 如果已经显示，则隐藏
    if (self.effectSelectorView) {
        [self hideVoiceEffectSelector];
        return;
    }
    
    // 创建半透明背景
    UIView *backgroundView = [[UIView alloc] initWithFrame:self.view.bounds];
    backgroundView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    backgroundView.tag = 999;
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideVoiceEffectSelector)];
    [backgroundView addGestureRecognizer:tapGesture];
    [self.view addSubview:backgroundView];
    
    // 创建音效选择面板
    CGFloat panelWidth = 320;
    CGFloat panelHeight = 580;  // 适应12个音效
    CGFloat panelX = (self.view.bounds.size.width - panelWidth) / 2;
    CGFloat panelY = (self.view.bounds.size.height - panelHeight) / 2;
    
    self.effectSelectorView = [[UIView alloc] initWithFrame:CGRectMake(panelX, panelY, panelWidth, panelHeight)];
    self.effectSelectorView.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.95];
    self.effectSelectorView.layer.cornerRadius = 16;
    self.effectSelectorView.layer.borderWidth = 2;
    self.effectSelectorView.layer.borderColor = [UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:1.0].CGColor;
    
    // 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, panelWidth, 30)];
    titleLabel.text = @"🎤 选择音效";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:20];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.effectSelectorView addSubview:titleLabel];
    
    // 音效列表
    NSArray *effects = @[
        @[@(VoiceEffectTypeNone), @"原声", @"💬"],
        @[@(VoiceEffectTypeStudio), @"录音棚", @"🎙️"],
        @[@(VoiceEffectTypeConcertHall), @"音乐厅", @"🎭"],
        @[@(VoiceEffectTypeSuperReverb), @"超级混响", @"🌊"],
        @[@(VoiceEffectTypeSinger), @"唱将", @"🎵"],
        @[@(VoiceEffectTypeGodOfSong), @"歌神", @"👑"],
        @[@(VoiceEffectTypeEthereal), @"空灵", @"✨"],
        @[@(VoiceEffectTypeMagnetic), @"磁性", @"🔥"],
        @[@(VoiceEffectTypeBright), @"明亮", @"💎"],
        @[@(VoiceEffectTypeAutoTune), @"自动修音", @"🎤"],
        @[@(VoiceEffectTypePitchUp), @"升调+3", @"⬆️"],
        @[@(VoiceEffectTypePitchDown), @"降调-3", @"⬇️"]
    ];
    
    CGFloat buttonStartY = 70;
    CGFloat buttonSpacing = 45;
    CGFloat buttonHeight = 40;
    
    for (int i = 0; i < effects.count; i++) {
        NSArray *effect = effects[i];
        VoiceEffectType effectType = [effect[0] integerValue];
        NSString *name = effect[1];
        NSString *emoji = effect[2];
        
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = effectType;
        button.frame = CGRectMake(20, buttonStartY + i * buttonSpacing, panelWidth - 40, buttonHeight);
        
        NSString *buttonTitle = [NSString stringWithFormat:@"%@ %@", emoji, name];
        [button setTitle:buttonTitle forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        button.backgroundColor = [UIColor colorWithRed:0.25 green:0.45 blue:0.85 alpha:0.6];
        button.layer.cornerRadius = 8;
        button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        button.contentEdgeInsets = UIEdgeInsetsMake(0, 15, 0, 0);
        
        // 如果是当前选中的音效，高亮显示
        if (self.karaokeAudioEngine.voiceEffectProcessor.effectType == effectType) {
            button.backgroundColor = [UIColor colorWithRed:0.0 green:0.7 blue:1.0 alpha:0.8];
            button.layer.borderWidth = 2;
            button.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:1.0 alpha:1.0].CGColor;
        }
        
        [button addTarget:self action:@selector(selectVoiceEffect:) forControlEvents:UIControlEventTouchUpInside];
        [self.effectSelectorView addSubview:button];
    }
    
    // 添加到视图
    [self.view addSubview:self.effectSelectorView];
    
    // 动画效果
    self.effectSelectorView.alpha = 0;
    self.effectSelectorView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0 animations:^{
        self.effectSelectorView.alpha = 1;
        self.effectSelectorView.transform = CGAffineTransformIdentity;
    } completion:nil];
    
    NSLog(@"📱 显示音效选择面板");
}

- (void)hideVoiceEffectSelector {
    UIView *backgroundView = [self.view viewWithTag:999];
    
    [UIView animateWithDuration:0.2 animations:^{
        self.effectSelectorView.alpha = 0;
        self.effectSelectorView.transform = CGAffineTransformMakeScale(0.8, 0.8);
        backgroundView.alpha = 0;
    } completion:^(BOOL finished) {
        [self.effectSelectorView removeFromSuperview];
        [backgroundView removeFromSuperview];
        self.effectSelectorView = nil;
    }];
}

- (void)selectVoiceEffect:(UIButton *)sender {
    VoiceEffectType effectType = (VoiceEffectType)sender.tag;
    
    // 应用音效
    if (self.karaokeAudioEngine) {
        [self.karaokeAudioEngine setVoiceEffect:effectType];
        
        // 🆕 如果在预览模式且正在播放，使用防抖延迟更新
        if (self.isInPreviewMode) {
            [self scheduleParameterUpdateWithDelay];
        }
    }
    
    // 更新按钮标题
    NSString *effectName = [VoiceEffectProcessor nameForEffectType:effectType];
    [self.voiceEffectButton setTitle:[NSString stringWithFormat:@"🎤 音效：%@", effectName] forState:UIControlStateNormal];
    
    NSLog(@"🎵 选择音效: %@", effectName);
    
    // 关闭面板
    [self hideVoiceEffectSelector];
}

// 🆕 降噪开关改变
- (void)noiseReductionSwitchChanged:(UISwitch *)sender {
    BOOL enabled = sender.isOn;
    
    if (self.karaokeAudioEngine && self.karaokeAudioEngine.voiceEffectProcessor) {
        [self.karaokeAudioEngine.voiceEffectProcessor setNoiseReductionEnabled:enabled];
        NSLog(@"🔇 智能降噪: %@", enabled ? @"开启" : @"关闭");
        
        // 🆕 如果在预览模式且正在播放，使用防抖延迟更新
        if (self.isInPreviewMode) {
            [self scheduleParameterUpdateWithDelay];
        }
    }
}

// 🆕 音高滑块改变
- (void)pitchShiftSliderChanged:(UISlider *)sender {
    float pitchShift = roundf(sender.value); // 四舍五入到整数半音
    sender.value = pitchShift; // 捕捉到整数值
    
    // 更新标签
    UILabel *pitchLabel = (UILabel *)[self.view viewWithTag:9002];
    if (pitchLabel) {
        if (pitchShift > 0) {
            pitchLabel.text = [NSString stringWithFormat:@"🎵 音高: +%.0f半音", pitchShift];
        } else if (pitchShift < 0) {
            pitchLabel.text = [NSString stringWithFormat:@"🎵 音高: %.0f半音", pitchShift];
        } else {
            pitchLabel.text = @"🎵 音高: 0半音";
        }
    }
    
    // 应用音高变化
    if (self.karaokeAudioEngine && self.karaokeAudioEngine.voiceEffectProcessor) {
        [self.karaokeAudioEngine.voiceEffectProcessor setPitchShiftSemitones:pitchShift];
        NSLog(@"🎵 音高调节: %.0f 半音", pitchShift);
        
        // 🆕 如果在预览模式且正在播放，使用防抖延迟更新
        if (self.isInPreviewMode) {
            [self scheduleParameterUpdateWithDelay];
        }
    }
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
    // 🔧 Bug修复：预览模式下由previewUpdateTimer更新，避免冲突
    if (self.isInPreviewMode) {
        return;  // 预览模式下不更新，避免和previewUpdateTimer冲突
    }
    
    if (self.karaokeAudioEngine && self.karaokeAudioEngine.audioPlayer) {
        // 更新进度滑块 - 使用基于 BGM 读取位置的时间
        NSTimeInterval currentTime = self.karaokeAudioEngine.currentPlaybackTime;
        NSTimeInterval duration = self.karaokeAudioEngine.audioPlayer.duration;
        float progress = duration > 0 ? (float)(currentTime / duration) : 0.0f;
        
        // 🆕 只有在用户未拖动时才更新滑块
        if (!self.progressSlider.isTracking) {
            self.progressSlider.value = progress;
        }
        
        // 更新时间标签
        NSString *currentTimeStr = [self formatTime:currentTime];
        NSString *durationStr = [self formatTime:duration];
        self.durationLabel.text = [NSString stringWithFormat:@"%@ / %@", currentTimeStr, durationStr];
        
        // 🆕 只有在播放时才更新歌词（停止/暂停时不更新）
        if (self.karaokeAudioEngine.isPlaying) {
        [self.lyricsView updateWithTime:currentTime];
        }
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

// 🆕 进度滑块事件处理
- (void)progressSliderTouchDown:(UISlider *)sender {
    // 用户开始拖动，暂时停止自动更新
    NSLog(@"📍 用户开始拖动进度条");
}

- (void)progressSliderValueChanged:(UISlider *)sender {
    // 🔧 Bug修复：预览模式下禁止拖动进度条
    if (self.isInPreviewMode) {
        return;  // 预览模式下不响应拖动
    }
    
    // 实时更新预览时间和歌词
    if (self.karaokeAudioEngine.audioPlayer) {
        NSTimeInterval duration = self.karaokeAudioEngine.audioPlayer.duration;
        NSTimeInterval targetTime = duration * sender.value;
        
        // 更新时间显示
        NSString *targetTimeStr = [self formatTime:targetTime];
        NSString *durationStr = [self formatTime:duration];
        self.durationLabel.text = [NSString stringWithFormat:@"%@ / %@", targetTimeStr, durationStr];
        
        // 更新歌词预览
        [self.lyricsView updateWithTime:targetTime];
    }
}

- (void)progressSliderTouchUp:(UISlider *)sender {
    // 🔧 Bug修复：预览模式下禁止拖动进度条（避免干扰预览播放）
    if (self.isInPreviewMode) {
        NSLog(@"⚠️ 预览模式下不支持拖动进度条");
        // 恢复到当前实际播放位置
        if ([self.karaokeAudioEngine isPlayingPreview]) {
            NSTimeInterval currentTime = [self.karaokeAudioEngine currentPreviewTime];
            NSTimeInterval duration = [self.karaokeAudioEngine previewDuration];
            if (duration > 0) {
                self.progressSlider.value = currentTime / duration;
            }
        }
        return;
    }
    
    if (!self.karaokeAudioEngine.audioPlayer) {
        return;
    }
    
    NSTimeInterval duration = self.karaokeAudioEngine.audioPlayer.duration;
    NSTimeInterval targetTime = duration * sender.value;
    
    NSLog(@"📍 用户松开进度条，跳转到 %.2f 秒", targetTime);
    
    // 如果正在录音，使用jump或rewind
    if (self.karaokeAudioEngine.isRecording) {
        NSTimeInterval currentTime = self.karaokeAudioEngine.currentPlaybackTime;
        
        if (targetTime > currentTime) {
            // 向后跳转（跳过部分）
            [self confirmJumpToTime:targetTime];
        } else {
            // 向前回退
            [self confirmRewindToTime:targetTime];
        }
    } else {
        // 未录音，直接跳转播放位置
        [self.karaokeAudioEngine playFromTime:targetTime];
    }
}


- (void)startButtonTapped:(UIButton *)sender {
    if (self.isRecording) {
        // 🔧 停止录音：保存当前段落、停止录音状态、暂停BGM
        NSLog(@"🛑 用户点击停止录音");
        
        // 1. 停止录音引擎（保存当前段落）
        [self.karaokeAudioEngine stopRecording];
        
        // 2. 暂停BGM播放
        if (self.karaokeAudioEngine.isPlaying) {
            [self.karaokeAudioEngine pause];
            NSLog(@"⏸️ BGM已暂停");
        }
        
        // 3. 停止AUGraph（停止录音回调）
        Boolean isRunning = false;
        AUGraphIsRunning(self.karaokeAudioEngine.auGraph, &isRunning);
        if (isRunning) {
            CheckError(AUGraphStop(self.karaokeAudioEngine.auGraph), "AUGraphStop on stop button");
            NSLog(@"🛑 AUGraph已停止");
        }
        
        // 4. 更新状态
        self.isRecording = NO;
        
        // 5. 更新UI
        [self.startButton setTitle:@"继续录音" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0];
        
        // 显示完成按钮
        self.finishButton.hidden = NO;
        self.pauseButton.hidden = YES;
        self.rewindButton.hidden = NO;
        
        NSLog(@"✅ 录音已停止，可继续录音或完成");
    } else {
        // 开始/继续录音
        if (self.karaokeAudioEngine.recordingSegments.count == 0) {
            // 第一次录音，重置状态
        [self resetAudioEngineForNewRecording];
        }
        
        // 从当前位置开始录音
        NSTimeInterval startTime = self.progressSlider.value * self.karaokeAudioEngine.audioPlayer.duration;
        [self.karaokeAudioEngine playFromTime:startTime];
        [self.karaokeAudioEngine startRecordingFromTime:startTime];
        
        self.isRecording = YES;
        [self.startButton setTitle:@"停止录音" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
        
        // 显示控制按钮
        self.pauseButton.hidden = NO;
        self.finishButton.hidden = NO;
        self.rewindButton.hidden = NO;
        
        NSLog(@"🎤 开始录音（从 %.2f 秒）", startTime);
    }
}

// 🆕 暂停/恢复按钮
- (void)pauseButtonTapped {
    if (self.karaokeAudioEngine.isRecordingPaused) {
        // 恢复录音
        [self.karaokeAudioEngine resumeRecording];
        [self.pauseButton setTitle:@"⏸️ 暂停" forState:UIControlStateNormal];
        NSLog(@"▶️ 录音已恢复");
    } else {
        // 暂停录音
        [self.karaokeAudioEngine pauseRecording];
        [self.pauseButton setTitle:@"▶️ 恢复" forState:UIControlStateNormal];
        NSLog(@"⏸️ 录音已暂停");
    }
}

// 🆕 完成录音按钮（改为停止并进入预览模式）
- (void)finishButtonTapped {
    NSLog(@"✅ 停止录音，进入预览模式");
    
    // 如果正在录音，先停止
    if (self.karaokeAudioEngine.isRecording) {
        [self.karaokeAudioEngine stopRecording];
    }
    
    // 停止BGM
    if (self.karaokeAudioEngine.isPlaying) {
        [self.karaokeAudioEngine pause];
    }
    
    // 停止AUGraph
    Boolean isRunning = false;
    AUGraphIsRunning(self.karaokeAudioEngine.auGraph, &isRunning);
    if (isRunning) {
        CheckError(AUGraphStop(self.karaokeAudioEngine.auGraph), "AUGraphStop on finish");
    }
    
    // 进入预览模式
    [self enterPreviewMode];
}

#pragma mark - 🆕 预览模式

// 进入预览模式
- (void)enterPreviewMode {
    NSLog(@"🎬 进入预览模式");
    
    self.isInPreviewMode = YES;
    
    // 隐藏录音控制按钮
    self.startButton.hidden = YES;
    self.pauseButton.hidden = YES;
    self.rewindButton.hidden = YES;
    self.finishButton.hidden = YES;
    
    // 显示预览控制面板
    [self showPreviewControlPanel];
}

// 显示预览控制面板
- (void)showPreviewControlPanel {
    if (self.previewControlView) {
        self.previewControlView.hidden = NO;
        return;
    }
    
    // 🆕 创建预览控制面板（紧凑型，放在录音按钮位置）
    CGFloat panelY = 290;
    CGFloat panelWidth = self.view.bounds.size.width - 40;
    CGFloat panelHeight = 120;  // 缩小高度
    
    self.previewControlView = [[UIView alloc] initWithFrame:CGRectMake(20, panelY, panelWidth, panelHeight)];
    self.previewControlView.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.95];
    self.previewControlView.layer.cornerRadius = 12;
    [self.view addSubview:self.previewControlView];
    
    // 标题
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"🎬 预览模式 - 可调整参数后试听";
    titleLabel.textColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.frame = CGRectMake(0, 8, panelWidth, 22);
    [self.previewControlView addSubview:titleLabel];
    
    // 段落信息
    NSInteger segmentCount = self.karaokeAudioEngine.recordingSegments.count;
    NSTimeInterval recordedDuration = [self.karaokeAudioEngine getTotalRecordedDuration];
    UILabel *infoLabel = [[UILabel alloc] init];
    infoLabel.text = [NSString stringWithFormat:@"%ld个段落 | 已录制%.1f秒", (long)segmentCount, recordedDuration];
    infoLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    infoLabel.font = [UIFont systemFontOfSize:12];
    infoLabel.textAlignment = NSTextAlignmentCenter;
    infoLabel.frame = CGRectMake(0, 32, panelWidth, 18);
    [self.previewControlView addSubview:infoLabel];
    
    // 🆕 提示文字
    UILabel *hintLabel = [[UILabel alloc] init];
    hintLabel.text = @"⬇️ 下方可调整BGM/麦克风/音效参数";
    hintLabel.textColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    hintLabel.font = [UIFont systemFontOfSize:11];
    hintLabel.textAlignment = NSTextAlignmentCenter;
    hintLabel.frame = CGRectMake(0, 52, panelWidth, 16);
    [self.previewControlView addSubview:hintLabel];
    
    // 按钮布局（紧凑排列）
    CGFloat buttonY = 72;
    CGFloat buttonWidth = (panelWidth - 60) / 3;
    CGFloat buttonHeight = 40;
    
    // 试听按钮
    self.previewButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.previewButton setTitle:@"🎧 试听" forState:UIControlStateNormal];
    [self.previewButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.previewButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0];
    self.previewButton.layer.cornerRadius = 8;
    self.previewButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    self.previewButton.frame = CGRectMake(20, buttonY, buttonWidth, buttonHeight);
    [self.previewButton addTarget:self action:@selector(previewButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.previewControlView addSubview:self.previewButton];
    
    // 重新录制按钮
    UIButton *reRecordButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [reRecordButton setTitle:@"🔄 重录" forState:UIControlStateNormal];
    [reRecordButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    reRecordButton.backgroundColor = [UIColor colorWithRed:1.0 green:0.6 blue:0.0 alpha:1.0];
    reRecordButton.layer.cornerRadius = 8;
    reRecordButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    reRecordButton.frame = CGRectMake(30 + buttonWidth, buttonY, buttonWidth, buttonHeight);
    [reRecordButton addTarget:self action:@selector(reRecordButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.previewControlView addSubview:reRecordButton];
    
    // 保存按钮
    self.saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.saveButton setTitle:@"✅ 保存" forState:UIControlStateNormal];
    [self.saveButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.saveButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.4 alpha:1.0];
    self.saveButton.layer.cornerRadius = 8;
    self.saveButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    self.saveButton.frame = CGRectMake(40 + buttonWidth * 2, buttonY, buttonWidth, buttonHeight);
    [self.saveButton addTarget:self action:@selector(saveButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.previewControlView addSubview:self.saveButton];
    
    NSLog(@"✅ 预览控制面板已显示（紧凑型，不遮挡参数控制）");
}

// 试听按钮
- (void)previewButtonTapped {
    if ([self.karaokeAudioEngine isPlayingPreview]) {
        // 正在播放，停止
        [self.karaokeAudioEngine stopPreview];
        [self.previewButton setTitle:@"🎧 试听" forState:UIControlStateNormal];
        
        // 🆕 停止UI更新定时器
        [self stopPreviewUpdateTimer];
        
        NSLog(@"🛑 停止预览");
    } else {
        // 🆕 使用当前参数重新生成预览
        NSLog(@"🎧 开始播放预览（当前参数）");
        [self.previewButton setTitle:@"⏸️ 停止" forState:UIControlStateNormal];
        
        // 🆕 启动UI更新定时器
        [self startPreviewUpdateTimer];
        
        [self.karaokeAudioEngine playPreview:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // 播放完成或出错
                [self.previewButton setTitle:@"🎧 试听" forState:UIControlStateNormal];
                
                // 🆕 停止UI更新定时器
                [self stopPreviewUpdateTimer];
                
                if (error) {
                    NSLog(@"❌ 预览播放出错: %@", error);
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"播放失败"
                                                                                   message:error.localizedDescription
                                                                            preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:alert animated:YES completion:nil];
                } else {
                    NSLog(@"✅ 预览播放完成");
                }
            });
        }];
    }
}

// 重新录制按钮
- (void)reRecordButtonTapped {
    NSLog(@"🔄 重新录制");
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重新录制"
                                                                   message:@"确定要清空当前录音并重新开始吗？"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"重新录制" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        // 停止预览
        if ([self.karaokeAudioEngine isPlayingPreview]) {
            [self.karaokeAudioEngine stopPreview];
        }
        
        // 退出预览模式
        [self exitPreviewMode];
        
        // 重置引擎
        [self resetAudioEngineForNewRecording];
        
        // 重置UI
        [self resetToInitialState];
        
        NSLog(@"✅ 已重置，可以重新录音");
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 保存按钮
- (void)saveButtonTapped {
    NSLog(@"💾 保存录音文件");
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存录音"
                                                                   message:@"确定要保存这个录音吗？"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        // 显示保存中
        UIAlertController *savingAlert = [UIAlertController alertControllerWithTitle:@"保存中..."
                                                                               message:@"正在生成文件，请稍候"
                                                                        preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:savingAlert animated:YES completion:nil];
        
        // 异步保存
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self.karaokeAudioEngine savePreviewToFile:^(NSString *filePath, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [savingAlert dismissViewControllerAnimated:YES completion:^{
                        if (error) {
                            NSLog(@"❌ 保存失败: %@", error);
                            UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"保存失败"
                                                                                               message:error.localizedDescription
                                                                                        preferredStyle:UIAlertControllerStyleAlert];
                            [errorAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                            [self presentViewController:errorAlert animated:YES completion:nil];
                        } else {
                            NSLog(@"✅ 保存成功: %@", filePath);
                            
                            // 退出预览模式
                            [self exitPreviewMode];
                            
                            // 显示回放对话框
                            [self showRecordingPlaybackDialog];
                            
                            // 重置状态
                            [self resetToInitialState];
                        }
                    }];
                });
            }];
        });
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 退出预览模式
- (void)exitPreviewMode {
    NSLog(@"🚪 退出预览模式");
    
    self.isInPreviewMode = NO;
    
    // 🆕 停止预览UI更新定时器
    [self stopPreviewUpdateTimer];
    
    // 🆕 停止防抖定时器
    [self.parameterUpdateDebounceTimer invalidate];
    self.parameterUpdateDebounceTimer = nil;
    
    // 停止预览播放
    if ([self.karaokeAudioEngine isPlayingPreview]) {
        [self.karaokeAudioEngine stopPreview];
    }
    
    // 隐藏预览控制面板
    if (self.previewControlView) {
        self.previewControlView.hidden = YES;
    }
    
    // 显示录音控制按钮
    self.startButton.hidden = NO;
}

// 🆕 重置到初始状态
- (void)resetToInitialState {
    NSLog(@"🔄 重置所有状态到初始状态");
    
    // 1. 重置录音状态
    self.isRecording = NO;
    
    // 2. 重置UI按钮
    [self.startButton setTitle:@"开始录音" forState:UIControlStateNormal];
    self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0];
    self.pauseButton.hidden = YES;
    self.finishButton.hidden = YES;
    self.rewindButton.hidden = YES;
    
    // 3. 重置段落信息
    self.segmentInfoLabel.text = @"";
    
    // 4. 重置进度条到开头
    self.progressSlider.value = 0.0;
    
    // 5. 重置时间显示
    if (self.karaokeAudioEngine.audioPlayer) {
        NSTimeInterval duration = self.karaokeAudioEngine.audioPlayer.duration;
        self.durationLabel.text = [NSString stringWithFormat:@"0:00 / %@", [self formatTime:duration]];
    }
    
    // 6. 重置歌词到开头
    if (self.lyricsView) {
        [self.lyricsView updateWithTime:0.0];
        [self.lyricsView reset];
    }
    
    // 7. 重置VU表
    self.rmsProgressView.progress = 0.0;
    self.peakProgressView.progress = 0.0;
    
    NSLog(@"✅ 状态重置完成");
}

// 🆕 回退按钮
- (void)rewindButtonTapped {
    if (!self.karaokeAudioEngine.audioPlayer) {
        return;
    }
    
    NSTimeInterval currentTime = self.karaokeAudioEngine.currentPlaybackTime;
    NSTimeInterval targetTime = MAX(0, currentTime - 10.0);
    
    [self confirmRewindToTime:targetTime];
}

// 🆕 确认跳转
- (void)confirmJumpToTime:(NSTimeInterval)targetTime {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"跳转确认"
                                                                   message:[NSString stringWithFormat:@"跳转到 %@？\n跳过的部分将填充纯BGM", [self formatTime:targetTime]]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"跳转" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self.karaokeAudioEngine jumpToTime:targetTime];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 🆕 确认回退
- (void)confirmRewindToTime:(NSTimeInterval)targetTime {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"回退确认"
                                                                   message:[NSString stringWithFormat:@"回退到 %@？\n之后的录音将被删除", [self formatTime:targetTime]]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"回退" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self.karaokeAudioEngine rewindToTime:targetTime];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetAudioEngineForNewRecording {
    if (!self.karaokeAudioEngine) {
        return;
    }
    
    NSLog(@"🔄 重置音频引擎，准备新的录音...");
    
    // 1. 确保之前的录音已停止
    if (self.karaokeAudioEngine.isRecording) {
        [self.karaokeAudioEngine stopRecording];
    }
    
    // 2. 确保播放已停止
    if (self.karaokeAudioEngine.isPlaying) {
        [self.karaokeAudioEngine stop];
    }
    
    // 3. 调用reset方法重置状态（会重置BGM位置、AUGraph等）
    [self.karaokeAudioEngine reset];
    
    NSLog(@"✅ 音频引擎已重置");
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
            
            // 🆕 如果在预览模式且正在播放，使用防抖延迟更新
            if (self.isInPreviewMode) {
                [self scheduleParameterUpdateWithDelay];
            }
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
        
        // 🆕 如果在预览模式且正在播放，使用防抖延迟更新
        if (self.isInPreviewMode) {
            [self scheduleParameterUpdateWithDelay];
        }
    }
}

#pragma mark - 🆕 防抖和预览更新

// 防抖：延迟触发参数更新（避免拖动时频繁重新生成）
- (void)scheduleParameterUpdateWithDelay {
    // 取消之前的定时器
    [self.parameterUpdateDebounceTimer invalidate];
    
    // 创建新的定时器：500ms后触发
    self.parameterUpdateDebounceTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                                         repeats:NO
                                                                           block:^(NSTimer *timer) {
        NSLog(@"⏱️ 防抖定时器触发，开始更新参数...");
        if (self.isInPreviewMode) {
            [self.karaokeAudioEngine updatePreviewParametersIfPlaying];
        }
    }];
    
    NSLog(@"⏱️ 已安排防抖更新（500ms后执行）");
}

// 启动预览模式的UI更新定时器
- (void)startPreviewUpdateTimer {
    // 停止之前的定时器
    [self stopPreviewUpdateTimer];
    
    // 创建新定时器：30fps更新
    self.previewUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0
                                                               repeats:YES
                                                                 block:^(NSTimer *timer) {
        [self updatePreviewUI];
    }];
    
    NSLog(@"⏱️ 预览模式UI更新定时器已启动");
}

// 停止预览模式的UI更新定时器
- (void)stopPreviewUpdateTimer {
    if (self.previewUpdateTimer) {
        [self.previewUpdateTimer invalidate];
        self.previewUpdateTimer = nil;
        NSLog(@"⏱️ 预览模式UI更新定时器已停止");
    }
}

// 更新预览模式的UI（进度条、歌词）
- (void)updatePreviewUI {
    if (![self.karaokeAudioEngine isPlayingPreview]) {
        return;
    }
    
    // 获取预览播放器的当前时间
    NSTimeInterval currentTime = [self.karaokeAudioEngine currentPreviewTime];
    NSTimeInterval duration = [self.karaokeAudioEngine previewDuration];
    
    // 更新进度条
    if (duration > 0) {
        self.progressSlider.value = currentTime / duration;
    }
    
    // 更新歌词
    [self.lyricsView updateWithTime:currentTime];
}

#pragma mark - LyricsViewDelegate

// 🆕 歌词点击代理方法
- (void)lyricsView:(LyricsView *)lyricsView didTapLyricAtTime:(NSTimeInterval)time text:(NSString *)text index:(NSInteger)index {
    NSLog(@"🎵 用户点击歌词: 索引=%ld, 时间=%.2f秒, 文本=%@", (long)index, time, text);
    
    if (!self.karaokeAudioEngine.audioPlayer) {
        NSLog(@"⚠️ BGM未加载，无法跳转");
        return;
    }
    
    // 如果正在录音，需要确认跳转/回退
    if (self.karaokeAudioEngine.isRecording) {
        NSTimeInterval currentTime = self.karaokeAudioEngine.currentPlaybackTime;
        
        if (time > currentTime) {
            // 向后跳转（跳过部分）
            [self confirmJumpToTime:time];
        } else {
            // 向前回退
            [self confirmRewindToTime:time];
        }
    } else {
        // 未录音，直接跳转播放位置
        [self.karaokeAudioEngine playFromTime:time];
        
        // 更新进度条
        if (self.karaokeAudioEngine.audioPlayer.duration > 0) {
            self.progressSlider.value = time / self.karaokeAudioEngine.audioPlayer.duration;
        }
        
        // 立即更新歌词显示
        [self.lyricsView updateWithTime:time];
        
        NSLog(@"✅ 已跳转到 %.2f 秒", time);
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

// 🆕 录音段落更新回调
- (void)audioEngineDidUpdateRecordingSegments:(NSArray<RecordingSegment *> *)segments {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 更新段落信息显示
        if (segments.count == 0) {
            self.segmentInfoLabel.text = @"";
        } else {
            NSInteger recordedSegments = 0;
            NSTimeInterval totalDuration = 0;
            
            for (RecordingSegment *segment in segments) {
                if (segment.isRecorded) {
                    recordedSegments++;
                }
                totalDuration += segment.duration;
            }
            
            self.segmentInfoLabel.text = [NSString stringWithFormat:@"已录制 %ld 段落 | 总时长 %@",
                                          (long)recordedSegments,
                                          [self formatTime:totalDuration]];
        }
        
        NSLog(@"📊 段落更新: %lu 个段落", (unsigned long)segments.count);
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
            self.pauseButton.hidden = YES;
            self.finishButton.hidden = NO;
            self.rewindButton.hidden = NO;
            
            NSLog(@"💡 提示：可以点击按钮合成最终录音");
        }
    });
}

- (void)audioEngineDidEncounterError:(NSError *)error {
    NSLog(@"❌ 卡拉OK音频引擎错误: %@", error.localizedDescription);
}

@end
