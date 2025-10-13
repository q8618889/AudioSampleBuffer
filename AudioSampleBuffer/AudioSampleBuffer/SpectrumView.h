#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, ADSpectraStyle) {
    ADSpectraStyleRect = 0, //直角
    ADSpectraStyleRound //圆角
};

@interface SpectrumView : UIView

@property (nonatomic, assign) CGFloat barWidth;
@property (nonatomic, assign) CGFloat space;
@property (nonatomic, assign) CGFloat bottomSpace;
@property (nonatomic, assign) CGFloat topSpace;

- (void)updateSpectra:(NSArray *)spectra withStype:(ADSpectraStyle)style;

// 控制频谱视图的暂停和恢复
- (void)pauseRendering;
- (void)resumeRendering;

@end

NS_ASSUME_NONNULL_END
