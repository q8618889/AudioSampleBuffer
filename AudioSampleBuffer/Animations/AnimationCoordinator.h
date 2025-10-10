//
//  AnimationCoordinator.h
//  AudioSampleBuffer
//
//  Created by AI Assistant on 2025/9/29.
//

#import <Foundation/Foundation.h>
#import "GradientAnimationManager.h"
#import "RotationAnimationManager.h"
#import "SpectrumAnimationManager.h"
#import "ParticleAnimationManager.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * 动画协调器
 * 统一管理所有动画效果，提供简单的接口
 */
@interface AnimationCoordinator : NSObject

@property (nonatomic, strong) GradientAnimationManager *gradientManager;
@property (nonatomic, strong) RotationAnimationManager *rotationManager;
@property (nonatomic, strong) SpectrumAnimationManager *spectrumManager;
@property (nonatomic, strong) ParticleAnimationManager *particleManager;

/**
 * 创建动画协调器
 * @param containerView 主容器视图
 */
- (instancetype)initWithContainerView:(UIView *)containerView;

/**
 * 启动所有动画
 */
- (void)startAllAnimations;

/**
 * 停止所有动画
 */
- (void)stopAllAnimations;

/**
 * 暂停所有动画
 */
- (void)pauseAllAnimations;

/**
 * 恢复所有动画
 */
- (void)resumeAllAnimations;

/**
 * 应用进入后台
 */
- (void)applicationDidEnterBackground;

/**
 * 应用回到前台
 */
- (void)applicationDidBecomeActive;

/**
 * 设置渐变图层
 * @param gradientLayer 渐变图层
 */
- (void)setupGradientLayer:(CAGradientLayer *)gradientLayer;

/**
 * 添加旋转视图
 * @param views 视图数组
 * @param rotations 旋转圈数数组
 * @param durations 持续时间数组
 * @param rotationTypes 旋转类型数组
 */
- (void)addRotationViews:(NSArray<UIView *> *)views
               rotations:(NSArray<NSNumber *> *)rotations
               durations:(NSArray<NSNumber *> *)durations
           rotationTypes:(NSArray<NSNumber *> *)rotationTypes;

/**
 * 设置频谱容器视图
 * @param containerView 频谱容器视图
 */
- (void)setupSpectrumContainerView:(UIView *)containerView;

/**
 * 设置粒子容器图层
 * @param containerLayer 粒子容器图层
 */
- (void)setupParticleContainerLayer:(CALayer *)containerLayer;

/**
 * 更新频谱动画
 * @param spectrumData 频谱数据
 */
- (void)updateSpectrumAnimations:(NSArray *)spectrumData;

/**
 * 更新粒子图像
 * @param image 新的粒子图像
 */
- (void)updateParticleImage:(UIImage *)image;

/**
 * 测试旋转方向
 * @param testView 测试视图
 */
- (void)testRotationDirections:(UIView *)testView;

@end

NS_ASSUME_NONNULL_END
