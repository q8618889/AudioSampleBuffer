
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class LRCParser;

@protocol AudioSpectrumPlayerDelegate <NSObject>

- (void)playerDidGenerateSpectrum:(NSArray *)spectrums;
- (void)didFinishPlay;

@optional
/// 播放时间更新（用于歌词同步）
- (void)playerDidUpdateTime:(NSTimeInterval)currentTime;
/// 歌词加载完成（parser为nil表示没有找到歌词文件）
- (void)playerDidLoadLyrics:(nullable LRCParser *)parser;

@end

@interface AudioSpectrumPlayer : NSObject

@property (nonatomic, weak) id <AudioSpectrumPlayerDelegate> delegate;
@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, assign) NSTimeInterval duration;  // 总时长
@property (nonatomic, assign, readonly) NSTimeInterval currentTime;  // 当前播放时间

/// 是否启用歌词功能（默认YES）
@property (nonatomic, assign) BOOL enableLyrics;

/// 当前歌词解析器
@property (nonatomic, strong, nullable, readonly) LRCParser *lyricsParser;

/// 🎵 音高调整（半音数，范围 -12.0 到 +12.0）
/// 0 = 原调，+1 = 升高一个半音，-1 = 降低一个半音
@property (nonatomic, assign) float pitchShift;

/// 🎵 速率调整（范围 0.5 到 2.0）
/// 1.0 = 原速
@property (nonatomic, assign) float playbackRate;

- (void)playWithFileName:(NSString *)fileName;
- (void)stop;

/// 手动加载歌词
- (void)loadLyricsForCurrentTrack;

@end

NS_ASSUME_NONNULL_END
