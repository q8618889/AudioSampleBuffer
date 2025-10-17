//
//  MusicDownloadManager.h
//  AudioSampleBuffer
//
//  音乐下载管理器 - 从云端搜索并下载音乐
//  参考 music-dl 项目实现：https://github.com/0xHJK/music-dl
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 音乐来源平台
 */
typedef NS_ENUM(NSInteger, MusicSourcePlatform) {
    MusicSourcePlatformQQMusic = 0,      // QQ音乐
    MusicSourcePlatformNetease = 1,      // 网易云音乐
    MusicSourcePlatformKugou = 2,        // 酷狗音乐
    MusicSourcePlatformBaidu = 3,        // 百度音乐
};

/**
 * 音乐质量等级
 */
typedef NS_ENUM(NSInteger, MusicQuality) {
    MusicQualityLossless = 0,  // 无损（FLAC/APE）
    MusicQuality320K = 1,      // 320K MP3
    MusicQuality128K = 2,      // 128K MP3
    MusicQualityAuto = 3,      // 自动选择最高质量
};

/**
 * 音乐搜索结果
 */
@interface MusicSearchResult : NSObject

@property (nonatomic, copy) NSString *songId;           // 歌曲ID
@property (nonatomic, copy) NSString *songName;         // 歌曲名
@property (nonatomic, copy) NSString *artistName;       // 艺术家
@property (nonatomic, copy) NSString *albumName;        // 专辑名
@property (nonatomic, assign) NSTimeInterval duration;  // 时长（秒）
@property (nonatomic, assign) NSInteger fileSize;       // 文件大小（字节）
@property (nonatomic, assign) MusicQuality quality;     // 音质
@property (nonatomic, assign) MusicSourcePlatform platform; // 来源平台
@property (nonatomic, copy, nullable) NSString *downloadUrl; // 下载链接
@property (nonatomic, copy, nullable) NSString *coverUrl;    // 封面链接
@property (nonatomic, copy, nullable) NSString *lyricsUrl;   // 歌词链接

@end

/**
 * 下载进度回调
 */
typedef void(^MusicDownloadProgressBlock)(float progress, NSString *status);

/**
 * 音乐下载管理器
 */
@interface MusicDownloadManager : NSObject

+ (instancetype)sharedManager;

#pragma mark - 搜索功能

/**
 * 搜索音乐
 * @param keyword 搜索关键词（歌名 + 歌手效果更好，如"七里香 周杰伦"）
 * @param platforms 搜索平台数组（传 nil 则搜索所有平台）
 * @param maxResults 每个平台最大结果数（默认5）
 * @param completion 完成回调，返回搜索结果数组
 */
- (void)searchMusic:(NSString *)keyword
          platforms:(nullable NSArray<NSNumber *> *)platforms
         maxResults:(NSInteger)maxResults
         completion:(void(^)(NSArray<MusicSearchResult *> * _Nullable results, NSError * _Nullable error))completion;

#pragma mark - 下载功能

/**
 * 下载音乐文件
 * @param searchResult 搜索结果对象
 * @param quality 期望的音质（会自动降级）
 * @param downloadLyrics 是否同时下载歌词
 * @param downloadCover 是否同时下载封面
 * @param progressBlock 进度回调
 * @param completion 完成回调，返回本地文件路径
 */
- (void)downloadMusic:(MusicSearchResult *)searchResult
              quality:(MusicQuality)quality
      downloadLyrics:(BOOL)downloadLyrics
       downloadCover:(BOOL)downloadCover
             progress:(nullable MusicDownloadProgressBlock)progressBlock
           completion:(void(^)(NSString * _Nullable filePath, NSError * _Nullable error))completion;

/**
 * 快捷方法：搜索并下载第一个匹配结果
 * @param keyword 搜索关键词
 * @param quality 音质要求
 * @param progressBlock 进度回调
 * @param completion 完成回调
 */
- (void)searchAndDownloadMusic:(NSString *)keyword
                        quality:(MusicQuality)quality
                       progress:(nullable MusicDownloadProgressBlock)progressBlock
                     completion:(void(^)(NSString * _Nullable filePath, NSError * _Nullable error))completion;

#pragma mark - 配置

/**
 * 设置下载目录（默认为 Documents/Downloads）
 */
- (void)setDownloadDirectory:(NSString *)path;

/**
 * 获取下载目录
 */
- (NSString *)downloadDirectory;

/**
 * 取消所有下载任务
 */
- (void)cancelAllDownloads;

@end

NS_ASSUME_NONNULL_END
