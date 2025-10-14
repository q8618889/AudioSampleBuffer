//
//  GradientAnimationManager.m
//  AudioSampleBuffer
//
//

#import "GradientAnimationManager.h"

@implementation GradientAnimationManager

- (instancetype)initWithGradientLayer:(CAGradientLayer *)gradientLayer {
    if (self = [super initWithTargetView:nil]) {
        _gradientLayer = gradientLayer;
        _enterBackground = NO;
        
        // 设置默认参数
        [self setAnimationParameters:@{
            @"duration": @(0.01),
            @"stepCount": @(360),
            @"stepSize": @(1)
        }];
        
        // 初始化彩虹色
        NSArray *colors = [self createRainbowColorsWithStepCount:[self.parameters[@"stepCount"] integerValue]];
        [_gradientLayer setColors:colors];
    }
    return self;
}

- (void)startAnimation {
    [super startAnimation];
    if (!self.enterBackground) {
        [self performGradientAnimation];
    }
}

- (void)stopAnimation {
    [super stopAnimation];
    [self.gradientLayer removeAllAnimations];
}

- (void)pauseAnimation {
    [super pauseAnimation];
    [self.gradientLayer removeAllAnimations];
}

- (void)resumeAnimation {
    [super resumeAnimation];
    if (!self.enterBackground) {
        [self performGradientAnimation];
    }
}

- (void)performGradientAnimation {
    if (self.state != AnimationStateRunning || self.enterBackground) {
        return;
    }
    
    // 将最后一个颜色移动到前面，产生循环效果
    NSMutableArray *mutableColors = [[self.gradientLayer colors] mutableCopy];
    id lastColor = [mutableColors lastObject];
    [mutableColors removeLastObject];
    [mutableColors insertObject:lastColor atIndex:0];
    NSArray *shiftedColors = [NSArray arrayWithArray:mutableColors];
    
    // 更新模型图层的颜色
    [self.gradientLayer setColors:shiftedColors];
    
    // 创建动画
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"colors"];
    [animation setToValue:shiftedColors];
    [animation setDuration:[self.parameters[@"duration"] doubleValue]];
    [animation setRemovedOnCompletion:YES];
    [animation setFillMode:kCAFillModeForwards];
    [animation setDelegate:self];
    [self.gradientLayer addAnimation:animation forKey:@"gradientAnimation"];
}

- (void)setAnimationDuration:(NSTimeInterval)duration {
    self.parameters[@"duration"] = @(duration);
}

- (NSArray *)createRainbowColorsWithStepCount:(NSInteger)stepCount {
    NSMutableArray *colors = [NSMutableArray array];
    NSInteger stepSize = [self.parameters[@"stepSize"] integerValue];
    
    for (NSInteger hue = 0; hue < stepCount; hue += stepSize) {
        UIColor *color = [UIColor colorWithHue:1.0 * hue / stepCount
                                    saturation:1.0
                                    brightness:1.0
                                         alpha:1.0];
        [colors addObject:(id)[color CGColor]];
    }
    return [NSArray arrayWithArray:colors];
}

- (void)applicationDidEnterBackground {
    self.enterBackground = YES;
}

- (void)applicationDidBecomeActive {
    self.enterBackground = NO;
    if (self.state == AnimationStateRunning) {
        [self performGradientAnimation];
    }
}

#pragma mark - CAAnimationDelegate

- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)flag {
    if (flag && self.state == AnimationStateRunning && !self.enterBackground) {
        [self performGradientAnimation];
    }
}

@end
