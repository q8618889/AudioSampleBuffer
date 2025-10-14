//
//  LyricsEffectControlPanel.h
//  AudioSampleBuffer
//
//  歌词特效控制面板
//

#import <UIKit/UIKit.h>
#import "LyricsEffectType.h"

NS_ASSUME_NONNULL_BEGIN

@protocol LyricsEffectControlDelegate <NSObject>

- (void)lyricsEffectDidChange:(LyricsEffectType)effectType;

@end

@interface LyricsEffectControlPanel : UIView

@property (nonatomic, weak) id<LyricsEffectControlDelegate> delegate;
@property (nonatomic, assign) LyricsEffectType currentEffect;

- (void)showAnimated:(BOOL)animated;
- (void)hideAnimated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END

