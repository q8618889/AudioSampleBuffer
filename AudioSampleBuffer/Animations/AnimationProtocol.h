//
//  AnimationProtocol.h
//  AudioSampleBuffer
//
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 动画状态枚举
 */
typedef NS_ENUM(NSUInteger, AnimationState) {
    AnimationStateStopped = 0,
    AnimationStateRunning,
    AnimationStatePaused
};

/**
 * 动画管理器协议
 * 所有动画管理器都应该遵循这个协议
 */
@protocol AnimationManagerProtocol <NSObject>

@required
/**
 * 开始动画
 */
- (void)startAnimation;

/**
 * 停止动画
 */
- (void)stopAnimation;

/**
 * 暂停动画
 */
- (void)pauseAnimation;

/**
 * 恢复动画
 */
- (void)resumeAnimation;

/**
 * 获取动画状态
 */
- (AnimationState)animationState;

@optional
/**
 * 设置动画参数
 */
- (void)setAnimationParameters:(NSDictionary *)parameters;

/**
 * 获取动画参数
 */
- (NSDictionary *)animationParameters;

@end

/**
 * 动画管理器基类
 */
@interface BaseAnimationManager : NSObject <AnimationManagerProtocol>

@property (nonatomic, assign) AnimationState state;
@property (nonatomic, strong) NSMutableDictionary *parameters;
@property (nonatomic, weak) UIView *targetView;

- (instancetype)initWithTargetView:(UIView *)targetView;

@end

NS_ASSUME_NONNULL_END
