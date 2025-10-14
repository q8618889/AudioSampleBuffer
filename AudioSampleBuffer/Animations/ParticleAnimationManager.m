//
//  ParticleAnimationManager.m
//  AudioSampleBuffer
//
//

#import "ParticleAnimationManager.h"

@implementation ParticleAnimationManager

- (instancetype)initWithContainerLayer:(CALayer *)containerLayer {
    if (self = [super initWithTargetView:nil]) {
        _containerLayer = containerLayer;
        
        // 创建发射器图层
        _emitterLayer = [CAEmitterLayer layer];
        [_containerLayer addSublayer:_emitterLayer];
        
        // 设置默认参数
        [self setAnimationParameters:@{
            @"birthRate": @(0.5),
            @"lifetime": @(10.0),
            @"velocity": @(1.0),
            @"velocityRange": @(5.0),
            @"yAcceleration": @(20.0),
            @"zAcceleration": @(20.0),
            @"spin": @(0.25),
            @"spinRange": @(5.0),
            @"emissionRange": @(M_PI),
            @"scale": @(0.03),
            @"scaleRange": @(0.03),
            @"alphaSpeed": @(-0.22),
            @"alphaRange": @(-0.8),
            @"particleCount": @(8)
        }];
        
        [self setupEmitterLayer];
    }
    return self;
}

- (void)setupEmitterLayer {
    // 设置发射器属性
    self.emitterLayer.emitterShape = kCAEmitterLayerCuboid;
    self.emitterLayer.emitterMode = kCAEmitterLayerCircle;
}

- (void)startAnimation {
    [super startAnimation];
    // 粒子系统本身就是持续的，不需要额外启动
}

- (void)stopAnimation {
    [super stopAnimation];
    // 停止粒子发射
    for (CAEmitterCell *cell in self.emitterLayer.emitterCells) {
        cell.birthRate = 0;
    }
}

- (void)pauseAnimation {
    [super pauseAnimation];
    [self stopAnimation];
}

- (void)resumeAnimation {
    [super resumeAnimation];
    // 恢复粒子发射
    float birthRate = [self.parameters[@"birthRate"] floatValue];
    for (CAEmitterCell *cell in self.emitterLayer.emitterCells) {
        cell.birthRate = birthRate;
    }
}

- (void)setParticleImage:(UIImage *)image {
    if (!image) return;
    
    NSArray *particleCells = [self createParticleCellsWithImage:image];
    self.emitterLayer.emitterCells = particleCells;
}

- (void)setEmitterPosition:(CGPoint)position {
    self.emitterLayer.emitterPosition = position;
}

- (void)setEmitterSize:(CGSize)size {
    self.emitterLayer.emitterSize = size;
}

- (void)configureParticleWithBirthRate:(float)birthRate
                              lifetime:(float)lifetime
                              velocity:(float)velocity
                                 scale:(float)scale {
    [self setAnimationParameters:@{
        @"birthRate": @(birthRate),
        @"lifetime": @(lifetime),
        @"velocity": @(velocity),
        @"scale": @(scale)
    }];
    
    // 如果已有粒子单元，更新它们的参数
    if (self.emitterLayer.emitterCells.count > 0) {
        for (CAEmitterCell *cell in self.emitterLayer.emitterCells) {
            cell.birthRate = birthRate;
            cell.lifetime = lifetime;
            cell.velocity = velocity;
            cell.scale = scale;
        }
    }
}

- (NSArray<CAEmitterCell *> *)createParticleCellsWithImage:(UIImage *)image {
    NSMutableArray *cells = [NSMutableArray array];
    NSInteger particleCount = [self.parameters[@"particleCount"] integerValue];
    
    for (int i = 0; i < particleCount; i++) {
        CAEmitterCell *cell = [CAEmitterCell emitterCell];
        
        // 设置粒子参数
        cell.birthRate = [self.parameters[@"birthRate"] floatValue];
        cell.lifetime = [self.parameters[@"lifetime"] floatValue];
        cell.velocity = [self.parameters[@"velocity"] floatValue];
        cell.velocityRange = [self.parameters[@"velocityRange"] floatValue];
        cell.yAcceleration = [self.parameters[@"yAcceleration"] floatValue];
        cell.zAcceleration = [self.parameters[@"zAcceleration"] floatValue];
        cell.spin = [self.parameters[@"spin"] floatValue];
        cell.spinRange = [self.parameters[@"spinRange"] floatValue];
        cell.emissionRange = [self.parameters[@"emissionRange"] floatValue];
        cell.scale = [self.parameters[@"scale"] floatValue];
        cell.scaleRange = [self.parameters[@"scaleRange"] floatValue];
        cell.alphaSpeed = [self.parameters[@"alphaSpeed"] floatValue];
        cell.alphaRange = [self.parameters[@"alphaRange"] floatValue];
        
        // 设置粒子图像
        cell.contents = (__bridge id)image.CGImage;
        cell.color = [UIColor whiteColor].CGColor;
        
        [cells addObject:cell];
    }
    
    return [NSArray arrayWithArray:cells];
}

- (void)updateParticleImage:(UIImage *)image {
    [self setParticleImage:image];
}

@end
