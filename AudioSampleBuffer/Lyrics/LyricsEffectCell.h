//
//  LyricsEffectCell.h
//  AudioSampleBuffer
//
//  支持特效的歌词单元格
//

#import <UIKit/UIKit.h>
#import "LyricsEffectType.h"

NS_ASSUME_NONNULL_BEGIN

@interface LyricsEffectCell : UITableViewCell

/// 歌词文本
@property (nonatomic, copy) NSString *lyricsText;

/// 是否高亮显示
@property (nonatomic, assign) BOOL isHighlighted;

/// 当前特效类型
@property (nonatomic, assign) LyricsEffectType effectType;

/// 高亮颜色
@property (nonatomic, strong) UIColor *highlightColor;

/// 普通颜色
@property (nonatomic, strong) UIColor *normalColor;

/// 高亮字体
@property (nonatomic, strong) UIFont *highlightFont;

/// 普通字体
@property (nonatomic, strong) UIFont *normalFont;

/**
 * 应用特效动画
 * @param animated 是否动画
 */
- (void)applyEffect:(BOOL)animated;

/**
 * 重置特效
 */
- (void)resetEffect;

@end

NS_ASSUME_NONNULL_END

