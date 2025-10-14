//
//  ParticleAnimationManager.h
//  AudioSampleBuffer
//
//

#import "AnimationProtocol.h"
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 粒子动画管理器
 * 负责管理基于音频封面的粒子效果
 */
@interface ParticleAnimationManager : BaseAnimationManager

@property (nonatomic, strong) CAEmitterLayer *emitterLayer;
@property (nonatomic, strong) CALayer *containerLayer;

/**
 * 创建粒子动画管理器
 * @param containerLayer 容器图层
 */
- (instancetype)initWithContainerLayer:(CALayer *)containerLayer;

/**
 * 设置粒子图像
 * @param image 粒子图像
 */
- (void)setParticleImage:(UIImage *)image;

/**
 * 设置发射器位置
 * @param position 发射器位置
 */
- (void)setEmitterPosition:(CGPoint)position;

/**
 * 设置发射器大小
 * @param size 发射器大小
 */
- (void)setEmitterSize:(CGSize)size;

/**
 * 配置粒子参数
 * @param birthRate 粒子产生速度
 * @param lifetime 粒子存活时间
 * @param velocity 初始速度
 * @param scale 缩放比例
 */
- (void)configureParticleWithBirthRate:(float)birthRate
                              lifetime:(float)lifetime
                              velocity:(float)velocity
                                 scale:(float)scale;

/**
 * 创建粒子单元
 * @param image 粒子图像
 * @return 粒子单元数组
 */
- (NSArray<CAEmitterCell *> *)createParticleCellsWithImage:(UIImage *)image;

/**
 * 更新粒子图像（用于音频切换时）
 * @param image 新的粒子图像
 */
- (void)updateParticleImage:(UIImage *)image;

@end

NS_ASSUME_NONNULL_END
