//
//  AnimationCoordinator.m
//  AudioSampleBuffer
//
//

#import "AnimationCoordinator.h"

@interface AnimationCoordinator ()
@property (nonatomic, weak) UIView *containerView;
@end

@implementation AnimationCoordinator

- (instancetype)initWithContainerView:(UIView *)containerView {
    if (self = [super init]) {
        _containerView = containerView;
    }
    return self;
}

- (void)startAllAnimations {
    [self.gradientManager startAnimation];
    [self.rotationManager startAnimation];
    [self.spectrumManager startAnimation];
    [self.particleManager startAnimation];
}

- (void)stopAllAnimations {
    [self.gradientManager stopAnimation];
    [self.rotationManager stopAnimation];
    [self.spectrumManager stopAnimation];
    [self.particleManager stopAnimation];
}

- (void)pauseAllAnimations {
    [self.gradientManager pauseAnimation];
    [self.rotationManager pauseAnimation];
    [self.spectrumManager pauseAnimation];
    [self.particleManager pauseAnimation];
}

- (void)resumeAllAnimations {
    [self.gradientManager resumeAnimation];
    [self.rotationManager resumeAnimation];
    [self.spectrumManager resumeAnimation];
    [self.particleManager resumeAnimation];
}

- (void)applicationDidEnterBackground {
    [self.gradientManager applicationDidEnterBackground];
    [self pauseAllAnimations];
}

- (void)applicationDidBecomeActive {
    [self.gradientManager applicationDidBecomeActive];
    [self resumeAllAnimations];
}

- (void)setupGradientLayer:(CAGradientLayer *)gradientLayer {
    if (!self.gradientManager) {
        self.gradientManager = [[GradientAnimationManager alloc] initWithGradientLayer:gradientLayer];
    }
}

- (void)addRotationViews:(NSArray<UIView *> *)views
               rotations:(NSArray<NSNumber *> *)rotations
               durations:(NSArray<NSNumber *> *)durations
           rotationTypes:(NSArray<NSNumber *> *)rotationTypes {
    
    if (!self.rotationManager) {
        self.rotationManager = [[RotationAnimationManager alloc] initWithTargetView:nil 
                                                                       rotationType:RotationTypeClockwise 
                                                                           duration:10.0];
    }
    
    [self.rotationManager addRotationAnimationsToViews:views 
                                             rotations:rotations 
                                             durations:durations 
                                         rotationTypes:rotationTypes];
}

- (void)setupSpectrumContainerView:(UIView *)containerView {
    if (!self.spectrumManager) {
        self.spectrumManager = [[SpectrumAnimationManager alloc] initWithContainerView:containerView];
    }
}

- (void)setupParticleContainerLayer:(CALayer *)containerLayer {
    if (!self.particleManager) {
        self.particleManager = [[ParticleAnimationManager alloc] initWithContainerLayer:containerLayer];
    }
}

- (void)updateSpectrumAnimations:(NSArray *)spectrumData {
    [self.spectrumManager updateSpectrumAnimations:spectrumData threshold:0.05];
}

- (void)updateParticleImage:(UIImage *)image {
    [self.particleManager updateParticleImage:image];
}

- (void)testRotationDirections:(UIView *)testView {
    NSLog(@"🔄 测试旋转方向:");
    
    // 创建两个测试视图
    UIView *clockwiseView = [[UIView alloc] initWithFrame:CGRectMake(50, 100, 50, 50)];
    clockwiseView.backgroundColor = [UIColor redColor];
    [testView addSubview:clockwiseView];
    
    UIView *counterClockwiseView = [[UIView alloc] initWithFrame:CGRectMake(150, 100, 50, 50)];
    counterClockwiseView.backgroundColor = [UIColor blueColor];
    [testView addSubview:counterClockwiseView];
    
    // 添加标识线条
    UIView *clockwiseLine = [[UIView alloc] initWithFrame:CGRectMake(75, 100, 2, 25)];
    clockwiseLine.backgroundColor = [UIColor whiteColor];
    [clockwiseView addSubview:clockwiseLine];
    
    UIView *counterClockwiseLine = [[UIView alloc] initWithFrame:CGRectMake(25, 0, 2, 25)];
    counterClockwiseLine.backgroundColor = [UIColor whiteColor];
    [counterClockwiseView addSubview:counterClockwiseLine];
    
    // 测试顺时针旋转（红色方块）
    [self.rotationManager addRotationAnimationToLayer:clockwiseView.layer 
                                         withRotations:1.0 
                                              duration:4.0 
                                          rotationType:RotationTypeClockwise];
    
    // 测试逆时针旋转（蓝色方块）
    [self.rotationManager addRotationAnimationToLayer:counterClockwiseView.layer 
                                         withRotations:1.0 
                                              duration:4.0 
                                          rotationType:RotationTypeCounterClockwise];
    
    NSLog(@"🔴 红色方块应该顺时针旋转");
    NSLog(@"🔵 蓝色方块应该逆时针旋转");
    NSLog(@"⏱️ 每个旋转1圈，持续4秒");
}

@end
