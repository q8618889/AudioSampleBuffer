//
//  SpectrumView.m
//  AudioSampleBuffer
//
//  Refactored to use modular animation system
//

#import "SpectrumView.h"
#import "../Animations/AnimationCoordinator.h"

#define AngleToRadian(x) (M_PI*(x)/180.0) // 把角度转换成弧度
#define RadianToAngle(x) (180.0*(x)/M_PI) // 把弧度转换成角度

@interface SpectrumView ()<CAAnimationDelegate>
{
    CGPoint lastPointTopL;
    CGPoint lastPointTopR;
    BOOL enterBackground;
    NSInteger sourceNumber;
    NSMutableArray *initColors;
    UIView *boxView;
}

@property (nonatomic, strong) CAGradientLayer *leftGradientLayer; //左声道layer
@property (nonatomic, strong) CAGradientLayer *rightGradientLayer; //右声道layer
@property CGContextRef context;

// 新的动画系统
@property (nonatomic, strong) AnimationCoordinator *animationCoordinator;
@end

@implementation SpectrumView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        // 初始化动画协调器
        self.animationCoordinator = [[AnimationCoordinator alloc] initWithContainerView:self];
        
        [self configInit];
        [self setupView];
        
        lastPointTopL = CGPointMake(self.center.x+120, self.center.y);
        lastPointTopR = CGPointMake(self.center.x+120, self.center.y);
        
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(hadEnterBackGround) 
                                                     name:UIApplicationDidEnterBackgroundNotification 
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(hadEnterForeGround) 
                                                     name:UIApplicationDidBecomeActiveNotification 
                                                   object:nil];

        initColors = [NSMutableArray array];
        for (NSInteger hue = 0; hue < 80; hue += 5) {
            [initColors addObject:(id)[UIColor colorWithRed:hue/255.0 green:hue/255.0f blue:hue/255.0 alpha:0.25f]];
        }
    }
    return self;
}

- (void)hadEnterBackGround {
    NSLog(@"SpectrumView进入后台");
    enterBackground = YES;
    [self.animationCoordinator applicationDidEnterBackground];
}

- (void)hadEnterForeGround {
    NSLog(@"SpectrumView回到app");
    enterBackground = NO;
    [self.animationCoordinator applicationDidBecomeActive];
}

- (void)configInit {
    CGFloat barSpace = self.frame.size.width / (CGFloat)(80 * 3 - 1); //80与RealtimeAnalyzer中frequencyBands数一致
    self.barWidth = barSpace * 2;
    self.space = barSpace;
    self.bottomSpace = 0;
    self.topSpace = -50;
    self.backgroundColor = [UIColor darkTextColor];
}

- (void)setupView {
    // 创建频谱容器视图
    boxView = [[UIView alloc] initWithFrame:CGRectMake(0, 
                                                      ([UIScreen mainScreen].bounds.size.height/2)-((80/([UIScreen mainScreen].bounds.size.width/50))*50)/2-[UIApplication sharedApplication].statusBarFrame.size.height, 
                                                      [UIScreen mainScreen].bounds.size.height,
                                                      (80/([UIScreen mainScreen].bounds.size.width/50))*50)];
    [self addSubview:boxView];
    
    // 设置频谱动画管理器
    [self.animationCoordinator setupSpectrumContainerView:boxView];
    
    // 添加渐变图层
    [self.layer addSublayer:self.rightGradientLayer];
    [self.layer addSublayer:self.leftGradientLayer];
    
    // 设置渐变图层动画
    [self.animationCoordinator setupGradientLayer:self.leftGradientLayer];
    
    // 为渐变图层添加旋转动画
    [self.animationCoordinator.rotationManager addRotationAnimationToLayer:self.rightGradientLayer 
                                                              withRotations:6.0 
                                                                   duration:100.0 
                                                               rotationType:RotationTypeCounterClockwise];
    
    [self.animationCoordinator.rotationManager addRotationAnimationToLayer:self.leftGradientLayer 
                                                              withRotations:6.0 
                                                                   duration:100.0 
                                                               rotationType:RotationTypeCounterClockwise];
    
    // 创建频谱视觉元素
    [self createSpectrumViews];
    
    // 启动动画
    [self.animationCoordinator startAllAnimations];
}

- (void)createSpectrumViews {
    CGFloat margin_X = 1; // 水平间距
    CGFloat _margin_Y = 1; // 数值间距
    CGFloat itemWidth = 50; // 宽
    CGFloat itemHeight = 50; // 高
    int totalColumns = [UIScreen mainScreen].bounds.size.width/50; // 每行最大列数
    sourceNumber = 80;  // 数据源
    
    for(int index = 0; index < sourceNumber; index++) {
        UIView *itemView = [[UIView alloc] init];
        itemView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.0];
        itemView.layer.cornerRadius = 5;
        itemView.tag = 100 + index;
        
        int row = index / totalColumns;
        int col = index % totalColumns;
        
        CGFloat cellX = col * (itemWidth + margin_X);
        CGFloat cellY = row * (itemHeight + _margin_Y);
        
        itemView.frame = CGRectMake(cellX, cellY, itemWidth, itemHeight);
        itemView.layer.shadowColor = [UIColor lightGrayColor].CGColor;
        itemView.layer.shadowOffset = CGSizeMake(0, 1);
        itemView.layer.shadowOpacity = 0;
        [boxView addSubview:itemView];
    }
}

#pragma mark - public method
- (void)updateSpectra:(NSArray *)spectra withStype:(ADSpectraStyle)style {
    if (spectra.count == 0) return;
    
    // 使用动画管理器处理频谱响应动画
    [self.animationCoordinator updateSpectrumAnimations:spectra];
    
    // 绘制频谱路径
    [self drawSpectrumPaths:spectra withStyle:style];
}

- (void)drawSpectrumPaths:(NSArray *)spectra withStyle:(ADSpectraStyle)style {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    UIBezierPath *leftPath = [UIBezierPath bezierPath];
    NSUInteger count = [spectra.firstObject count];
    
    for (int i = 0; i < count; i++) {
        CGFloat y = [self translateAmplitudeToYPosition:[spectra[0][i] floatValue]];
        CGFloat angleTemp = 2.0 + i * (360.0 - 0) / (80 - 0);
        CGFloat musicLineHeight = CGRectGetHeight(self.bounds) - self.bottomSpace - y + 1;
        
        NSArray *rectanglePointArray = [self calculateFourKeyPointForRectangleWithCircleCenter:self.center 
                                                                             innerCircleRadius:120 
                                                                                rectangleWidht:10 
                                                                               rectangleHeight:musicLineHeight 
                                                                                         angle:angleTemp];
        
        CGPoint topLeftPoint = ((NSValue *)rectanglePointArray[0]).CGPointValue;
        CGPoint topRightPoint = ((NSValue *)rectanglePointArray[1]).CGPointValue;
        CGPoint bottomRightPoint = ((NSValue *)rectanglePointArray[2]).CGPointValue;
        CGPoint bottomLeftPoint = ((NSValue *)rectanglePointArray[3]).CGPointValue;
        
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:topLeftPoint];
        [path addLineToPoint:topRightPoint];
        [path addLineToPoint:bottomRightPoint];
        [path addLineToPoint:bottomLeftPoint];
        [path closePath];
        
        [leftPath appendPath:path];
    }
    
    CAShapeLayer *leftMaskLayer = [CAShapeLayer layer];
    leftMaskLayer.path = leftPath.CGPath;
    self.leftGradientLayer.frame = CGRectMake(0, self.topSpace, CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds) - self.topSpace - self.bottomSpace);
    self.leftGradientLayer.mask = leftMaskLayer;
    
    [CATransaction commit];
}

/**
 计算矩形的四个顶点坐标
 
 @param cirlceCenter 圆心
 @param innerCircleRadius 内圆半径
 @param rectangleWidht 矩形宽
 @param rectangleHeight 矩形高
 @param angle 矩形绕圆心的角度
 @return 数组，包含四个顶点坐标（顺时针，上左，上右，下右，下左）
 */
- (NSArray *)calculateFourKeyPointForRectangleWithCircleCenter:(CGPoint)cirlceCenter 
                                               innerCircleRadius:(CGFloat)innerCircleRadius 
                                                  rectangleWidht:(CGFloat)rectangleWidht 
                                                 rectangleHeight:(CGFloat)rectangleHeight 
                                                           angle:(CGFloat)angle {
    CGFloat cirlceCenterX = cirlceCenter.x;
    CGFloat cirlceCenterY = cirlceCenter.y;
    
    CGFloat tempAngle = 360 - angle;
    CGFloat tempRadian = AngleToRadian(tempAngle);
    
    CGFloat middlePointX_LeftLine = cirlceCenterX + innerCircleRadius * cos(tempRadian);
    CGFloat middlePointY_LeftLine = cirlceCenterY - innerCircleRadius * sin(tempRadian);
    
    CGFloat topLeftPointX = middlePointX_LeftLine - rectangleWidht / 2 * sin(tempRadian);
    CGFloat topLeftPointY = middlePointY_LeftLine - rectangleWidht / 2 * cos(tempRadian);
    NSValue *topLeftPointValue = [NSValue valueWithCGPoint:CGPointMake(topLeftPointX, topLeftPointY)];
    
    CGFloat topRightPointX = topLeftPointX + rectangleHeight * cos(tempRadian);
    CGFloat topRightPointY = topLeftPointY - rectangleHeight * sin(tempRadian);
    NSValue *topRightPointValue = [NSValue valueWithCGPoint:CGPointMake(topRightPointX, topRightPointY)];
    
    CGFloat bottomLeftPointX = middlePointX_LeftLine + rectangleWidht / 2 * sin(tempRadian);
    CGFloat bottomLeftPointY = middlePointY_LeftLine + rectangleWidht / 2 * cos(tempRadian);
    NSValue *bottomLeftPointValue = [NSValue valueWithCGPoint:CGPointMake(bottomLeftPointX, bottomLeftPointY)];
    
    CGFloat bottomRightPointX = bottomLeftPointX + rectangleHeight * cos(tempRadian);
    CGFloat bottomRightPointY = bottomLeftPointY - rectangleHeight * sin(tempRadian);
    NSValue *bottomRightPointValue = [NSValue valueWithCGPoint:CGPointMake(bottomRightPointX, bottomRightPointY)];
    
    NSArray *pointArray = @[topLeftPointValue, topRightPointValue, bottomRightPointValue, bottomLeftPointValue];
    
    return pointArray;
}

#pragma mark - private method
- (CGFloat)translateAmplitudeToYPosition:(float)amplitude {
    CGFloat barHeight = (CGFloat)amplitude * self.frame.size.width/2;
    return CGRectGetHeight(self.bounds) - self.bottomSpace - barHeight;
}

- (CAGradientLayer *)leftGradientLayer {
    if (!_leftGradientLayer) {
        _leftGradientLayer = [CAGradientLayer layer];
        _leftGradientLayer.colors = @[(id)[UIColor colorWithRed:235/255.0 green:18/255.0 blue:26/255.0 alpha:1.0].CGColor, 
                                     (id)[UIColor colorWithRed:255/255.0 green:165/255.0 blue:0/255.0 alpha:1.0].CGColor];
        _leftGradientLayer.locations = @[@0.6, @1.0];
      
        NSMutableArray *colors = [NSMutableArray array];
        for (NSInteger hue = 0; hue < 360; hue += 7) {
            UIColor *color = [UIColor colorWithHue:1.0 * hue / 360.0
                                        saturation:1.0
                                        brightness:1.0
                                             alpha:1.0];
            [colors addObject:(id)[color CGColor]];
        }

        [_leftGradientLayer setColors:[NSArray arrayWithArray:colors]];
    }
    return _leftGradientLayer;
}

- (CAGradientLayer *)rightGradientLayer {
    if (!_rightGradientLayer) {
        _rightGradientLayer = [CAGradientLayer layer];

        NSMutableArray *colors = [NSMutableArray array];
        for (NSInteger hue = 0; hue < 360; hue += 22.5) {
            UIColor *color = [UIColor colorWithHue:1.0 * hue / 360.0
                                        saturation:1.0
                                        brightness:1.0
                                             alpha:1.0];
            [colors addObject:(id)[color CGColor]];
        }

        [_rightGradientLayer setColors:[NSArray arrayWithArray:colors]];
    }
    return _rightGradientLayer;
}

// 这些方法现在由动画管理器处理
- (void)performAnimation {
    // 已移至GradientAnimationManager
}

- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)flag {
    // 已移至GradientAnimationManager
}

#pragma mark 计算圆圈上点在IOS系统中的坐标
+ (CGPoint)calcCircleCoordinateWithCenter:(CGPoint)center  
                             andWithAngle:(CGFloat)angle 
                            andWithRadius:(CGFloat)radius {
    CGFloat x2 = radius*cosf(angle*M_PI/180);
    CGFloat y2 = radius*sinf(angle*M_PI/180);
    return CGPointMake(center.x+x2, center.y-y2);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
