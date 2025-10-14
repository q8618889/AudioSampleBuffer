//
//  RotationAnimationManager.m
//  AudioSampleBuffer
//
//

#import "RotationAnimationManager.h"

@interface RotationAnimationManager ()
@property (nonatomic, strong) NSMutableArray<UIView *> *managedViews;
@property (nonatomic, strong) NSMutableArray<CALayer *> *managedLayers;
@end

@implementation RotationAnimationManager

- (instancetype)initWithTargetView:(UIView *)targetView 
                      rotationType:(RotationType)rotationType 
                          duration:(NSTimeInterval)duration {
    if (self = [super initWithTargetView:targetView]) {
        _managedViews = [NSMutableArray array];
        _managedLayers = [NSMutableArray array];
        
        // 设置默认参数
        [self setAnimationParameters:@{
            @"rotations": @(3.0),
            @"duration": @(duration),
            @"rotationType": @(rotationType)
        }];
        
        if (targetView) {
            [_managedViews addObject:targetView];
        }
    }
    return self;
}

- (void)startAnimation {
    [super startAnimation];
    
    // 为所有管理的视图添加旋转动画
    for (UIView *view in self.managedViews) {
        [self addRotationAnimationToLayer:view.layer];
    }
    
    // 为所有管理的图层添加旋转动画
    for (CALayer *layer in self.managedLayers) {
        [self addRotationAnimationToLayer:layer];
    }
}

- (void)stopAnimation {
    [super stopAnimation];
    
    // 移除所有旋转动画
    for (UIView *view in self.managedViews) {
        [view.layer removeAnimationForKey:@"rotationAnimation"];
    }
    
    for (CALayer *layer in self.managedLayers) {
        [layer removeAnimationForKey:@"rotationAnimation"];
    }
}

- (void)pauseAnimation {
    [super pauseAnimation];
    [self stopAnimation];
}

- (void)resumeAnimation {
    [super resumeAnimation];
    [self startAnimation];
}

- (void)setRotations:(CGFloat)rotations 
            duration:(NSTimeInterval)duration 
        rotationType:(RotationType)rotationType {
    [self setAnimationParameters:@{
        @"rotations": @(rotations),
        @"duration": @(duration),
        @"rotationType": @(rotationType)
    }];
}

- (void)addRotationAnimationsToViews:(NSArray<UIView *> *)views
                           rotations:(NSArray<NSNumber *> *)rotations
                           durations:(NSArray<NSNumber *> *)durations
                       rotationTypes:(NSArray<NSNumber *> *)rotationTypes {
    
    [self.managedViews addObjectsFromArray:views];
    
    for (NSInteger i = 0; i < views.count; i++) {
        UIView *view = views[i];
        
        // 获取参数，如果数组长度不够则使用默认值
        CGFloat rotation = i < rotations.count ? [rotations[i] floatValue] : [self.parameters[@"rotations"] floatValue];
        NSTimeInterval duration = i < durations.count ? [durations[i] doubleValue] : [self.parameters[@"duration"] doubleValue];
        RotationType rotationType = i < rotationTypes.count ? [rotationTypes[i] integerValue] : [self.parameters[@"rotationType"] integerValue];
        
        [self addRotationAnimationToLayer:view.layer 
                             withRotations:rotation 
                                  duration:duration 
                              rotationType:rotationType];
    }
}

- (void)addRotationAnimationToLayer:(CALayer *)layer {
    CGFloat rotations = [self.parameters[@"rotations"] floatValue];
    NSTimeInterval duration = [self.parameters[@"duration"] doubleValue];
    RotationType rotationType = [self.parameters[@"rotationType"] integerValue];
    
    [self addRotationAnimationToLayer:layer 
                        withRotations:rotations 
                             duration:duration 
                         rotationType:rotationType];
}

- (void)addRotationAnimationToLayer:(CALayer *)layer 
                      withRotations:(CGFloat)rotations 
                           duration:(NSTimeInterval)duration 
                       rotationType:(RotationType)rotationType {
    
    CABasicAnimation *rotationAnimation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rotationAnimation.fromValue = @(0);
    
    // 计算最终的旋转值
    CGFloat finalRotationValue;
    CGFloat absRotations = fabs(rotations); // 取绝对值
    
    switch (rotationType) {
        case RotationTypeClockwise:
            finalRotationValue = absRotations * M_PI; // 顺时针为正值
            break;
        case RotationTypeCounterClockwise:
            finalRotationValue = -absRotations * M_PI; // 逆时针为负值
            break;
        case RotationTypeAlternating:
            // 交替旋转逻辑：可以根据当前时间或其他条件决定方向
            finalRotationValue = absRotations * M_PI;
            break;
    }
    
    rotationAnimation.toValue = @(finalRotationValue);
    rotationAnimation.duration = duration;
    rotationAnimation.repeatCount = MAXFLOAT;
    rotationAnimation.removedOnCompletion = NO;
    rotationAnimation.fillMode = kCAFillModeForwards;
    
    [layer addAnimation:rotationAnimation forKey:@"rotationAnimation"];
    
    // 添加到管理列表中
    if (![self.managedLayers containsObject:layer]) {
        [self.managedLayers addObject:layer];
    }
}

@end
