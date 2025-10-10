//
//  GradientAnimationManager.h
//  AudioSampleBuffer
//
//  Created by AI Assistant on 2025/9/29.
//

#import "AnimationProtocol.h"
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 渐变动画管理器
 * 负责管理彩虹渐变色循环动画
 */
@interface GradientAnimationManager : BaseAnimationManager <CAAnimationDelegate>

@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@property (nonatomic, assign) BOOL enterBackground;

/**
 * 创建渐变动画管理器
 * @param gradientLayer 目标渐变图层
 */
- (instancetype)initWithGradientLayer:(CAGradientLayer *)gradientLayer;

/**
 * 设置渐变动画速度
 * @param duration 动画持续时间
 */
- (void)setAnimationDuration:(NSTimeInterval)duration;

/**
 * 创建彩虹色数组
 * @param stepCount 颜色步数
 * @return 颜色数组
 */
- (NSArray *)createRainbowColorsWithStepCount:(NSInteger)stepCount;

/**
 * 应用进入后台状态
 */
- (void)applicationDidEnterBackground;

/**
 * 应用回到前台状态
 */
- (void)applicationDidBecomeActive;

@end

NS_ASSUME_NONNULL_END
