//
//  LyricsIntegrationExample.m
//  AudioSampleBuffer
//
//  这是一个完整的集成示例，展示如何在ViewController中使用歌词功能
//  将这些代码复制到你的ViewController.m中即可
//

#import "ViewController.h"
#import "AudioSpectrumPlayer.h"
#import "LyricsView.h"
#import "LRCParser.h"

@interface ViewController () <AudioSpectrumPlayerDelegate>

@property (nonatomic, strong) AudioSpectrumPlayer *player;
@property (nonatomic, strong) LyricsView *lyricsView;
@property (nonatomic, strong) UILabel *songInfoLabel;  // 歌曲信息标签

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self setupLyricsUI];
    [self setupPlayer];
    
    // 自动播放一首歌（示例）
    [self playDemoSong];
}

#pragma mark - UI Setup

- (void)setupLyricsUI {
    // 1. 创建歌曲信息标签
    self.songInfoLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 80, self.view.bounds.size.width - 40, 60)];
    self.songInfoLabel.textAlignment = NSTextAlignmentCenter;
    self.songInfoLabel.numberOfLines = 2;
    self.songInfoLabel.font = [UIFont systemFontOfSize:16];
    self.songInfoLabel.textColor = [UIColor whiteColor];
    self.songInfoLabel.text = @"正在加载...";
    [self.view addSubview:self.songInfoLabel];
    
    // 2. 创建歌词容器（带圆角和半透明背景）
    CGFloat containerHeight = 400;
    CGFloat containerY = (self.view.bounds.size.height - containerHeight) / 2;
    
    UIView *lyricsContainer = [[UIView alloc] initWithFrame:CGRectMake(20,
                                                                        containerY,
                                                                        self.view.bounds.size.width - 40,
                                                                        containerHeight)];
    lyricsContainer.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    lyricsContainer.layer.cornerRadius = 15;
    lyricsContainer.clipsToBounds = YES;
    lyricsContainer.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:lyricsContainer];
    
    // 3. 创建歌词视图
    self.lyricsView = [[LyricsView alloc] initWithFrame:lyricsContainer.bounds];
    self.lyricsView.backgroundColor = [UIColor clearColor];
    
    // 自定义歌词样式
    self.lyricsView.highlightColor = [UIColor colorWithRed:0.3 green:0.8 blue:1.0 alpha:1.0];  // 青色高亮
    self.lyricsView.normalColor = [UIColor colorWithWhite:1.0 alpha:0.45];
    self.lyricsView.highlightFont = [UIFont boldSystemFontOfSize:19];
    self.lyricsView.lyricsFont = [UIFont systemFontOfSize:15];
    self.lyricsView.lineSpacing = 28;
    self.lyricsView.autoScroll = YES;
    
    [lyricsContainer addSubview:self.lyricsView];
    
    // 4. 添加控制按钮（可选）
    [self setupControlButtons];
}

- (void)setupControlButtons {
    // 播放/暂停按钮
    UIButton *playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    playButton.frame = CGRectMake(self.view.bounds.size.width / 2 - 50,
                                  self.view.bounds.size.height - 100,
                                  100,
                                  44);
    [playButton setTitle:@"播放测试" forState:UIControlStateNormal];
    playButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    playButton.tintColor = [UIColor whiteColor];
    playButton.backgroundColor = [[UIColor blueColor] colorWithAlphaComponent:0.6];
    playButton.layer.cornerRadius = 22;
    [playButton addTarget:self action:@selector(playDemoSong) forControlEvents:UIControlEventTouchUpInside];
    playButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:playButton];
}

- (void)setupPlayer {
    // 创建播放器
    self.player = [[AudioSpectrumPlayer alloc] init];
    self.player.delegate = self;
    self.player.enableLyrics = YES;  // 启用歌词功能（默认就是YES）
}

#pragma mark - Actions

- (void)playDemoSong {
    // 播放示例歌曲（确保文件存在）
    [self.player playWithFileName:@"周深 - Rubia.mp3"];
    
    // 更新UI
    self.songInfoLabel.text = @"正在播放...\n周深 - Rubia";
}

#pragma mark - AudioSpectrumPlayerDelegate

// 必需方法：频谱数据更新
- (void)playerDidGenerateSpectrum:(NSArray *)spectrums {
    // 这里处理音频频谱数据，用于可视化
    // 你的原有代码...
}

// 必需方法：播放结束
- (void)didFinishPlay {
    NSLog(@"播放结束");
    self.songInfoLabel.text = @"播放结束";
    [self.lyricsView reset];
}

// 可选方法：歌词加载完成
- (void)playerDidLoadLyrics:(LRCParser *)parser {
    if (parser) {
        NSLog(@"✅ 歌词加载成功！");
        NSLog(@"   歌曲: %@", parser.title ?: @"未知");
        NSLog(@"   艺术家: %@", parser.artist ?: @"未知");
        NSLog(@"   歌词行数: %lu", (unsigned long)parser.lyrics.count);
        
        // 更新歌词视图
        self.lyricsView.parser = parser;
        
        // 更新歌曲信息
        NSString *title = parser.title ?: @"未知歌曲";
        NSString *artist = parser.artist ?: @"未知艺术家";
        self.songInfoLabel.text = [NSString stringWithFormat:@"%@ - %@\n🎵 歌词已加载", artist, title];
        
        // 可选：显示前几行歌词作为预览
        if (parser.lyrics.count > 0) {
            NSLog(@"   第一行歌词: %@", parser.lyrics[0].text);
        }
    } else {
        NSLog(@"⚠️ 未找到歌词");
        self.songInfoLabel.text = @"播放中\n暂无歌词";
    }
}

// 可选方法：播放时间更新（每秒调用一次）
- (void)playerDidUpdateTime:(NSTimeInterval)currentTime {
    // 更新歌词显示
    [self.lyricsView updateWithTime:currentTime];
    
    // 可选：更新进度显示
    // NSLog(@"当前播放时间: %.1f秒", currentTime);
}

@end

/*
 ====================================================================
 使用说明：
 ====================================================================
 
 1. 将上面的代码复制到你的 ViewController.m 中
 
 2. 确保在 ViewController.h 中导入必要的头文件：
    #import "AudioSpectrumPlayer.h"
    #import "LyricsView.h"
    
 3. 确保在项目中添加了以下文件：
    - LRCParser.h/m
    - LyricsView.h/m
    - LyricsManager.h/m
    
 4. 在 Audio 文件夹中添加测试文件：
    - 音频文件：周深 - Rubia.mp3
    - 歌词文件：周深 - Rubia.lrc（可选，会自动加载）
    
 5. 运行项目，歌词会自动加载并同步显示！
 
 ====================================================================
 高级定制：
 ====================================================================
 
 1. 自定义歌词颜色：
    self.lyricsView.highlightColor = [UIColor yellowColor];
    self.lyricsView.normalColor = [UIColor lightGrayColor];
 
 2. 自定义字体大小：
    self.lyricsView.highlightFont = [UIFont boldSystemFontOfSize:20];
    self.lyricsView.lyricsFont = [UIFont systemFontOfSize:14];
 
 3. 调整行间距：
    self.lyricsView.lineSpacing = 35;
 
 4. 禁用自动滚动：
    self.lyricsView.autoScroll = NO;
 
 5. 手动加载歌词：
    [self.player loadLyricsForCurrentTrack];
 
 6. 禁用歌词功能：
    self.player.enableLyrics = NO;
    
 ====================================================================
 */

