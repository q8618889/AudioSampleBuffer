//
//  QQMusicLyricsAPI.h
//  AudioSampleBuffer
//
//  QQ音乐歌词API - 自动从QQ音乐获取歌词
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * QQ音乐歌词数据模型
 */
@interface QQMusicLyrics : NSObject

@property (nonatomic, copy, nullable) NSString *originalLyrics;    // 原文歌词 (LRC格式)
@property (nonatomic, copy, nullable) NSString *translatedLyrics;  // 翻译歌词 (LRC格式)
@property (nonatomic, copy, nullable) NSString *romaLyrics;        // 罗马音/拼音歌词 (LRC格式)
@property (nonatomic, copy, nullable) NSString *wordByWordLyrics;  // 🆕 逐字歌词 (增强LRC格式，每个字有独立时间戳)
@property (nonatomic, copy, nullable) NSString *songName;          // 歌曲名
@property (nonatomic, copy, nullable) NSString *artistName;        // 艺术家
@property (nonatomic, assign) BOOL hasWordByWord;                  // 🆕 是否包含逐字歌词

@end

/**
 * QQ音乐歌词API客户端
 */
@interface QQMusicLyricsAPI : NSObject

/**
 * 通过 songmid 获取歌词
 * @param songMid QQ音乐歌曲的唯一标识 (如: "001OyHbk2MSIi4")
 * @param completion 完成回调，返回歌词对象或错误
 */
+ (void)fetchLyricsWithSongMid:(NSString *)songMid
                    completion:(void(^)(QQMusicLyrics * _Nullable lyrics, NSError * _Nullable error))completion;

/**
 * 通过 songid 获取歌词
 * @param songId QQ音乐歌曲的数字ID (如: "102065756")
 * @param completion 完成回调，返回歌词对象或错误
 */
+ (void)fetchLyricsWithSongId:(NSString *)songId
                   completion:(void(^)(QQMusicLyrics * _Nullable lyrics, NSError * _Nullable error))completion;

/**
 * 通过歌曲名和艺术家搜索并获取歌词
 * @param songName 歌曲名
 * @param artistName 艺术家名（可选，传入可提高匹配准确度）
 * @param completion 完成回调，返回歌词对象或错误
 */
+ (void)searchAndFetchLyricsWithSongName:(NSString *)songName
                              artistName:(nullable NSString *)artistName
                              completion:(void(^)(QQMusicLyrics * _Nullable lyrics, NSError * _Nullable error))completion;

/**
 * 从音频文件元数据中提取 QQ音乐 ID 并获取歌词
 * @param audioFilePath 音频文件路径 (支持 MP3, OGG 等格式)
 * @param completion 完成回调，返回歌词对象或错误
 */
+ (void)fetchLyricsFromAudioFile:(NSString *)audioFilePath
                      completion:(void(^)(QQMusicLyrics * _Nullable lyrics, NSError * _Nullable error))completion;

/**
 * 从音频文件中读取 QQ音乐元数据
 * @param audioFilePath 音频文件路径
 * @return 包含 songmid, songid, songName, artistName 等的字典，如果没有找到返回 nil
 */
+ (nullable NSDictionary *)extractQQMusicMetadataFromFile:(NSString *)audioFilePath;

/**
 * 🆕 通过 songmid 获取逐字歌词（卡拉OK模式歌词）
 * @param songMid QQ音乐歌曲的唯一标识
 * @param completion 完成回调，返回包含逐字歌词的歌词对象或错误
 * @discussion 逐字歌词格式示例: [00:10.00]<00:10.00,00:10.50>你<00:10.50,00:11.00>好
 *             每个字都有独立的开始和结束时间戳
 */
+ (void)fetchWordByWordLyricsWithSongMid:(NSString *)songMid
                               completion:(void(^)(QQMusicLyrics * _Nullable lyrics, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END

