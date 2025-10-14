//
//  SpectrumAnimationManager.h
//  AudioSampleBuffer
//
//

#import "AnimationProtocol.h"
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 频谱动画类型
 */
typedef NS_ENUM(NSUInteger, SpectrumAnimationType) {
    SpectrumAnimationTypeScale = 0,     // 缩放动画
    SpectrumAnimationTypeShadow,        // 阴影动画
    SpectrumAnimationTypeBackgroundColor, // 背景色动画
    SpectrumAnimationTypeCombined       // 组合动画
};

/**
 * 频谱响应动画管理器
 * 负责管理根据音频频谱数据产生的动画效果
 */
@interface SpectrumAnimationManager : BaseAnimationManager

/**
 * 创建频谱动画管理器
 * @param containerView 容器视图
 */
- (instancetype)initWithContainerView:(UIView *)containerView;

/**
 * 更新频谱动画
 * @param spectrumData 频谱数据数组
 * @param threshold 触发阈值
 */
- (void)updateSpectrumAnimations:(NSArray *)spectrumData threshold:(CGFloat)threshold;

/**
 * 为指定视图添加缩放动画
 * @param view 目标视图
 * @param intensity 动画强度
 */
- (void)addScaleAnimationToView:(UIView *)view intensity:(CGFloat)intensity;

/**
 * 为指定视图添加阴影动画
 * @param view 目标视图
 * @param intensity 动画强度
 */
- (void)addShadowAnimationToView:(UIView *)view intensity:(CGFloat)intensity;

/**
 * 为指定视图添加背景色动画
 * @param view 目标视图
 * @param intensity 动画强度
 */
- (void)addBackgroundColorAnimationToView:(UIView *)view intensity:(CGFloat)intensity;

/**
 * 为指定视图添加组合动画
 * @param view 目标视图
 * @param intensity 动画强度
 */
- (void)addCombinedAnimationToView:(UIView *)view intensity:(CGFloat)intensity;

/**
 * 设置动画阈值
 * @param threshold 阈值
 */
- (void)setAnimationThreshold:(CGFloat)threshold;

/**
 * 获取随机颜色
 * @param alpha 透明度
 * @return 随机颜色
 */
- (UIColor *)randomColorWithAlpha:(CGFloat)alpha;

@end

NS_ASSUME_NONNULL_END
