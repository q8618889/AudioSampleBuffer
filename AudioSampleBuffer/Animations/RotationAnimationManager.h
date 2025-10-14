//
//  RotationAnimationManager.h
//  AudioSampleBuffer
//
//

#import "AnimationProtocol.h"
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 旋转动画类型
 */
typedef NS_ENUM(NSUInteger, RotationType) {
    RotationTypeClockwise = 0,      // 顺时针
    RotationTypeCounterClockwise,   // 逆时针
    RotationTypeAlternating         // 交替旋转
};

/**
 * 旋转动画管理器
 * 负责管理各种旋转动画效果
 */
@interface RotationAnimationManager : BaseAnimationManager

/**
 * 创建旋转动画管理器
 * @param targetView 目标视图
 * @param rotationType 旋转类型
 * @param duration 动画持续时间
 */
- (instancetype)initWithTargetView:(UIView *)targetView 
                      rotationType:(RotationType)rotationType 
                          duration:(NSTimeInterval)duration;

/**
 * 设置旋转参数
 * @param rotations 旋转圈数
 * @param duration 持续时间
 * @param rotationType 旋转类型
 */
- (void)setRotations:(CGFloat)rotations 
            duration:(NSTimeInterval)duration 
        rotationType:(RotationType)rotationType;

/**
 * 添加多个视图的旋转动画
 * @param views 视图数组
 * @param rotations 旋转圈数数组
 * @param durations 持续时间数组
 * @param rotationTypes 旋转类型数组
 */
- (void)addRotationAnimationsToViews:(NSArray<UIView *> *)views
                           rotations:(NSArray<NSNumber *> *)rotations
                           durations:(NSArray<NSNumber *> *)durations
                       rotationTypes:(NSArray<NSNumber *> *)rotationTypes;

/**
 * 为图层添加旋转动画
 * @param layer 目标图层
 */
- (void)addRotationAnimationToLayer:(CALayer *)layer;

/**
 * 为图层添加旋转动画（详细参数版本）
 * @param layer 目标图层
 * @param rotations 旋转圈数
 * @param duration 持续时间
 * @param rotationType 旋转类型
 */
- (void)addRotationAnimationToLayer:(CALayer *)layer 
                      withRotations:(CGFloat)rotations 
                           duration:(NSTimeInterval)duration 
                       rotationType:(RotationType)rotationType;

@end

NS_ASSUME_NONNULL_END
