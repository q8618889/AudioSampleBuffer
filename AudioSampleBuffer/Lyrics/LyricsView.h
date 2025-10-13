//
//  LyricsView.h
//  AudioSampleBuffer
//
//  Created for displaying synchronized lyrics
//

#import <UIKit/UIKit.h>
#import "LRCParser.h"

NS_ASSUME_NONNULL_BEGIN

/// 歌词显示视图
@interface LyricsView : UIView

/// 歌词解析器
@property (nonatomic, strong, nullable) LRCParser *parser;

/// 当前高亮歌词颜色
@property (nonatomic, strong) UIColor *highlightColor;

/// 普通歌词颜色
@property (nonatomic, strong) UIColor *normalColor;

/// 字体大小
@property (nonatomic, strong) UIFont *lyricsFont;

/// 高亮歌词字体大小
@property (nonatomic, strong) UIFont *highlightFont;

/// 行间距
@property (nonatomic, assign) CGFloat lineSpacing;

/// 是否启用自动滚动（默认YES）
@property (nonatomic, assign) BOOL autoScroll;

/**
 * 更新当前播放时间，自动高亮并滚动到对应歌词
 * @param currentTime 当前播放时间（秒）
 */
- (void)updateWithTime:(NSTimeInterval)currentTime;

/**
 * 重置显示
 */
- (void)reset;

/**
 * 滚动到指定索引的歌词
 * @param index 歌词索引
 * @param animated 是否动画
 */
- (void)scrollToIndex:(NSInteger)index animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END

