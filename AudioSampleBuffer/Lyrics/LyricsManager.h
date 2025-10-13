//
//  LyricsManager.h
//  AudioSampleBuffer
//
//  Created for managing lyrics download and storage
//

#import <Foundation/Foundation.h>
#import "LRCParser.h"

NS_ASSUME_NONNULL_BEGIN

typedef void(^LyricsCompletionBlock)(LRCParser * _Nullable parser, NSError * _Nullable error);

/// 歌词管理器
@interface LyricsManager : NSObject

+ (instancetype)sharedManager;

/**
 * 为音频文件获取歌词
 * 优先级：
 *   1. Bundle中的.lrc文件（随应用打包）
 *   2. 沙盒Documents中的.lrc文件（动态下载）
 *   3. MP3的ID3歌词标签（USLT frame）
 *   4. 网易云API动态获取（如果有musicId）
 *
 * @param audioPath 音频文件路径
 * @param completion 完成回调
 */
- (void)fetchLyricsForAudioFile:(NSString *)audioPath
                     completion:(LyricsCompletionBlock)completion;

/**
 * 从网易云音乐API获取歌词
 *
 * @param musicId 网易云音乐歌曲ID
 * @param completion 完成回调
 */
- (void)fetchLyricsFromNetease:(NSString *)musicId
                    completion:(LyricsCompletionBlock)completion;

/**
 * 从本地LRC文件加载歌词
 *
 * @param lrcPath LRC文件路径
 * @param completion 完成回调
 */
- (void)loadLocalLyrics:(NSString *)lrcPath
             completion:(LyricsCompletionBlock)completion;

/**
 * 从音频文件元数据中提取网易云音乐ID（如果有）
 *
 * @param audioPath 音频文件路径
 * @return 音乐ID，如果没有则返回nil
 */
- (nullable NSString *)extractNeteaseIdFromAudio:(NSString *)audioPath;

/**
 * 保存歌词到本地
 *
 * @param lrcContent 歌词内容
 * @param audioPath 对应的音频文件路径
 * @return 保存成功返回YES
 */
- (BOOL)saveLyrics:(NSString *)lrcContent forAudioFile:(NSString *)audioPath;

/**
 * 从MP3的ID3标签中提取歌词（USLT frame）
 *
 * @param audioPath 音频文件路径
 * @return 歌词内容，如果没有则返回nil
 */
- (nullable NSString *)extractLyricsFromID3:(NSString *)audioPath;

/**
 * 获取歌词沙盒存储目录
 *
 * @return 歌词存储目录路径
 */
- (NSString *)lyricsSandboxDirectory;

@end

NS_ASSUME_NONNULL_END

