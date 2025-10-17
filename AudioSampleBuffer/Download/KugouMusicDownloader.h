//
//  KugouMusicDownloader.h
//  AudioSampleBuffer
//
//  酷狗音乐下载器 - 参考 music-dl 项目实现
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 酷狗音乐歌曲信息
 */
@interface KugouSongInfo : NSObject

@property (nonatomic, copy) NSString *songId;           // 歌曲Hash
@property (nonatomic, copy) NSString *songName;         // 歌曲名
@property (nonatomic, copy) NSString *artistName;       // 艺术家
@property (nonatomic, copy) NSString *albumName;        // 专辑名
@property (nonatomic, assign) NSInteger duration;       // 时长（秒）
@property (nonatomic, assign) NSInteger fileSize;       // 文件大小
@property (nonatomic, copy, nullable) NSString *downloadUrl;  // 下载链接
@property (nonatomic, copy, nullable) NSString *lyricsUrl;    // 歌词链接

@end

/**
 * 酷狗音乐下载器
 */
@interface KugouMusicDownloader : NSObject

/**
 * 搜索音乐
 */
+ (void)searchMusic:(NSString *)keyword
              limit:(NSInteger)limit
         completion:(void(^)(NSArray<KugouSongInfo *> * _Nullable songs, NSError * _Nullable error))completion;

/**
 * 获取下载链接
 */
+ (void)getDownloadURL:(NSString *)songHash
            completion:(void(^)(NSString * _Nullable url, NSError * _Nullable error))completion;

/**
 * 获取歌词
 */
+ (void)getLyrics:(NSString *)songHash
       completion:(void(^)(NSString * _Nullable lyrics, NSError * _Nullable error))completion;

/**
 * 下载音乐文件
 */
+ (void)downloadMusic:(KugouSongInfo *)songInfo
       toDirectory:(NSString *)directory
          progress:(nullable void(^)(float progress))progressBlock
        completion:(void(^)(NSString * _Nullable filePath, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
