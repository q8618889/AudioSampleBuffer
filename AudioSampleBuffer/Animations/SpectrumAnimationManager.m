//
//  SpectrumAnimationManager.m
//  AudioSampleBuffer
//
//

#import "SpectrumAnimationManager.h"

@interface SpectrumAnimationManager ()
@property (nonatomic, weak) UIView *containerView;
@property (nonatomic, strong) NSMutableArray<UIView *> *spectrumViews;
@end

@implementation SpectrumAnimationManager

- (instancetype)initWithContainerView:(UIView *)containerView {
    if (self = [super initWithTargetView:containerView]) {
        _containerView = containerView;
        _spectrumViews = [NSMutableArray array];
        
        // 设置默认参数
        [self setAnimationParameters:@{
            @"threshold": @(0.05),
            @"scaleDuration": @(0.5),
            @"shadowDuration": @(3.0),
            @"backgroundColorDuration": @(2.0),
            @"maxIntensity": @(1.0)
        }];
    }
    return self;
}

- (void)startAnimation {
    [super startAnimation];
}

- (void)stopAnimation {
    [super stopAnimation];
    
    // 移除所有频谱视图的动画
    for (UIView *view in self.spectrumViews) {
        [view.layer removeAllAnimations];
    }
}

- (void)updateSpectrumAnimations:(NSArray *)spectrumData threshold:(CGFloat)threshold {
    if (self.state != AnimationStateRunning || !spectrumData || spectrumData.count == 0) {
        return;
    }
    
    NSArray *firstChannelData = spectrumData.firstObject;
    if (!firstChannelData || firstChannelData.count == 0) {
        return;
    }
    
    // 开始批量动画事务
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    NSUInteger sourceNumber = 80; // 频带数量
    for (NSInteger i = 0; i < firstChannelData.count && i < sourceNumber; i++) {
        CGFloat amplitude = [firstChannelData[i] floatValue];
        
        if (amplitude > threshold) {
            // 根据标签查找对应的视图
            UIView *view = [self.containerView viewWithTag:100 + sourceNumber - i];
            if (view) {
                [self addCombinedAnimationToView:view intensity:amplitude];
                
                // 添加到管理列表中
                if (![self.spectrumViews containsObject:view]) {
                    [self.spectrumViews addObject:view];
                }
            }
        }
    }
    
    [CATransaction commit];
}

- (void)addScaleAnimationToView:(UIView *)view intensity:(CGFloat)intensity {
    CABasicAnimation *scaleAnimation = [CABasicAnimation animationWithKeyPath:@"transform.scale.y"];
    scaleAnimation.fromValue = @(1.0);
    scaleAnimation.toValue = @(0.0);
    scaleAnimation.duration = [self.parameters[@"scaleDuration"] doubleValue];
    scaleAnimation.repeatCount = 1;
    scaleAnimation.removedOnCompletion = NO;
    scaleAnimation.fillMode = kCAFillModeForwards;
    
    [view.layer addAnimation:scaleAnimation forKey:@"scaleAnimation"];
}

- (void)addShadowAnimationToView:(UIView *)view intensity:(CGFloat)intensity {
    CABasicAnimation *shadowAnimation = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
    shadowAnimation.fromValue = @(0.0);
    shadowAnimation.toValue = @(intensity);
    shadowAnimation.duration = [self.parameters[@"shadowDuration"] doubleValue];
    shadowAnimation.fillMode = kCAFillModeForwards;
    shadowAnimation.removedOnCompletion = NO;
    
    // 设置阴影属性
    view.layer.shadowColor = [UIColor whiteColor].CGColor;
    view.layer.shadowOffset = CGSizeMake(0, 1);
    view.layer.shadowRadius = 2.0;
    
    [view.layer addAnimation:shadowAnimation forKey:@"shadowAnimation"];
}

- (void)addBackgroundColorAnimationToView:(UIView *)view intensity:(CGFloat)intensity {
    CABasicAnimation *backgroundColorAnimation = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
    
    // 根据强度生成随机颜色
    CGFloat alpha = intensity * 0.3; // 限制透明度
    UIColor *fromColor = [self randomColorWithAlpha:alpha];
    UIColor *toColor = [[UIColor lightGrayColor] colorWithAlphaComponent:0.0];
    
    backgroundColorAnimation.fromValue = (__bridge id)fromColor.CGColor;
    backgroundColorAnimation.toValue = (__bridge id)toColor.CGColor;
    backgroundColorAnimation.duration = [self.parameters[@"backgroundColorDuration"] doubleValue];
    backgroundColorAnimation.fillMode = kCAFillModeForwards;
    backgroundColorAnimation.removedOnCompletion = NO;
    
    [view.layer addAnimation:backgroundColorAnimation forKey:@"backgroundColorAnimation"];
}

- (void)addCombinedAnimationToView:(UIView *)view intensity:(CGFloat)intensity {
    // 组合多种动画效果
    [self addScaleAnimationToView:view intensity:intensity];
    [self addShadowAnimationToView:view intensity:intensity];
    [self addBackgroundColorAnimationToView:view intensity:intensity];
}

- (void)setAnimationThreshold:(CGFloat)threshold {
    self.parameters[@"threshold"] = @(threshold);
}

- (UIColor *)randomColorWithAlpha:(CGFloat)alpha {
    CGFloat red = (arc4random() % 255) / 255.0;
    CGFloat green = (arc4random() % 255) / 255.0;
    CGFloat blue = (arc4random() % 255) / 255.0;
    
    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

@end
