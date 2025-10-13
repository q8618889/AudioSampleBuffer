//
//  LRCParser.h
//  AudioSampleBuffer
//
//  Created for parsing LRC lyrics files
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 歌词行模型
@interface LRCLine : NSObject

@property (nonatomic, assign) NSTimeInterval time;  // 时间戳（秒）
@property (nonatomic, copy) NSString *text;          // 歌词文本

- (instancetype)initWithTime:(NSTimeInterval)time text:(NSString *)text;

@end

/// LRC歌词解析器
@interface LRCParser : NSObject

/// 歌曲元信息
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *artist;
@property (nonatomic, copy, nullable) NSString *album;
@property (nonatomic, copy, nullable) NSString *by;
@property (nonatomic, assign) NSTimeInterval offset;  // 时间偏移（毫秒）

/// 歌词行数组，按时间排序
@property (nonatomic, strong, readonly) NSArray<LRCLine *> *lyrics;

/**
 * 从LRC格式字符串解析歌词
 * @param lrcString LRC格式的歌词文本
 * @return 解析成功返回YES
 */
- (BOOL)parseFromString:(NSString *)lrcString;

/**
 * 从LRC文件解析歌词
 * @param filePath LRC文件路径
 * @return 解析成功返回YES
 */
- (BOOL)parseFromFile:(NSString *)filePath;

/**
 * 根据播放时间获取当前应该显示的歌词
 * @param currentTime 当前播放时间（秒）
 * @return 当前歌词行，如果没有则返回nil
 */
- (nullable LRCLine *)lyricLineForTime:(NSTimeInterval)currentTime;

/**
 * 根据播放时间获取当前歌词的索引
 * @param currentTime 当前播放时间（秒）
 * @return 歌词索引，如果没有则返回-1
 */
- (NSInteger)indexForTime:(NSTimeInterval)currentTime;

@end

NS_ASSUME_NONNULL_END

