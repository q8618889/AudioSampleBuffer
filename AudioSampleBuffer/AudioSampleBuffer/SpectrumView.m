
#import "SpectrumView.h"
#define AngleToRadian(x) (M_PI*(x)/180.0) // 把角度转换成弧度
#define RadianToAngle(x) (180.0*(x)/M_PI) // 把弧度转换成角度
@interface SpectrumView ()<CAAnimationDelegate>
{
    CGPoint lastPointTopL;
     CGPoint lastPointTopR;
    BOOL enterBackground;
    NSInteger sourceNumber;
    NSMutableArray * initColors;
    
    UIView * boxView;
}

@property (nonatomic, strong) CAGradientLayer *leftGradientLayer; //左声道layer
@property (nonatomic, strong) CAGradientLayer *rightGradientLayer; //右声道layer
@property  CGContextRef context;
@end

@implementation SpectrumView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self configInit];
        [self setupView];
        lastPointTopL = CGPointMake(self.center.x+120, self.center.y);
        lastPointTopR = CGPointMake(self.center.x+120, self.center.y);
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(hadEnterBackGround) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(hadEnterForeGround) name:UIApplicationDidBecomeActiveNotification object:nil];

        initColors= [NSMutableArray array];
           for (NSInteger hue = 0; hue < 80; hue += 5) {
            
             
               [initColors addObject:(id)[UIColor colorWithRed:hue/255.0 green:hue/255.0f blue:hue/255.0 alpha:0.25f]];
           }


    }
    return self;
}
- (void)hadEnterBackGround{
    NSLog(@"进入后台");
    enterBackground =  YES;
    
}

- (void)hadEnterForeGround{
    NSLog(@"回到app");
    if (enterBackground == YES)
    {
        [self performAnimation];
    }
    enterBackground =  NO;

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
    
    boxView = [[UIView alloc]initWithFrame:CGRectMake(0, ([UIScreen mainScreen].bounds.size.height/2)-((80/([UIScreen mainScreen].bounds.size.width/50))*50)/2-[UIApplication sharedApplication].statusBarFrame.size.height, [UIScreen mainScreen].bounds.size.height,(80/([UIScreen mainScreen].bounds.size.width/50))*50)];
    [self addSubview:boxView];
  
    

    
    
    [self.layer addSublayer:self.rightGradientLayer];
    [self.layer addSublayer:self.leftGradientLayer];
    
    
    
    CABasicAnimation *rotationAnimations = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rotationAnimations.fromValue = [NSNumber numberWithFloat:0];
    rotationAnimations.toValue = [NSNumber numberWithFloat:-6.0*M_PI];
    rotationAnimations.repeatCount = MAXFLOAT;
    rotationAnimations.duration = 100;
    rotationAnimations.removedOnCompletion = NO;
    // 显然这比网上的做法：监听UIApplicationDidBecomeActiveNotification在通知里面重新开始动画简单多了
    [self.rightGradientLayer addAnimation:rotationAnimations forKey:@"rotationAnimations"];
    [self.leftGradientLayer addAnimation:rotationAnimations forKey:@"rotationAnimationss"];
    
    CGFloat margin_X = 1; // 水平间距
    CGFloat _margin_Y = 1; // 数值间距
    CGFloat itemWidth = 50; // 宽
    CGFloat itemHeight = 50; // 高
    int totalColumns = [UIScreen mainScreen].bounds.size.width/50; // 每行最大列数（影响到底几个换行）
   sourceNumber  = 80;  // 数据源
    for(int index = 0; index < sourceNumber; index++) {
        UIView * itemView = [[UIView alloc]init];
        itemView.backgroundColor = [[UIColor whiteColor]colorWithAlphaComponent:0.0];
        itemView.layer.cornerRadius =5;

        itemView.tag = 100+index;
        int row = index / totalColumns;
        
        int col = index % totalColumns;
        
        
        CGFloat cellX =  col * (itemWidth + margin_X);
        
        CGFloat cellY = row * (itemHeight + _margin_Y);
        
        itemView.frame = CGRectMake(cellX,cellY, itemWidth, itemHeight);
        itemView.layer.shadowColor = [UIColor lightGrayColor].CGColor;
        itemView.layer.shadowOffset = CGSizeMake(0,1);
        itemView.layer.shadowOpacity = 0;
        [boxView addSubview:itemView];
    }

}
#pragma mark - public method
- (void)updateSpectra:(NSArray *)spectra withStype:(ADSpectraStyle)style {
    if (spectra.count == 0) return;
    
//    NSArray * last =spectra[0];
//    CGFloat y = [last[(last.count-1)-arc4random()%10] floatValue];
//
//    if ( y  >0.002) {
//
//    }
    
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    UIBezierPath *leftPath = [UIBezierPath bezierPath];
    UIBezierPath *rightPath = [UIBezierPath bezierPath];
    NSUInteger count = [spectra.firstObject count];
    for (int i = 0; i < count; i++) {
        
        CGFloat s = 1500>count > 10.0f ?10.0:0.05;
        if ([spectra[0][i] floatValue] > s)
        {
            UIView * view  = [boxView viewWithTag:100+sourceNumber-i];
       
            
            CABasicAnimation *rotationAnimation2 = [CABasicAnimation animationWithKeyPath:@"transform.scale.y"];
            rotationAnimation2.fromValue = [NSNumber numberWithFloat:1];
            rotationAnimation2.toValue = [NSNumber numberWithDouble:0];//缩放效果
            rotationAnimation2.repeatCount = 1;
            rotationAnimation2.duration = 0.5;
            rotationAnimation2.removedOnCompletion = NO;
            // 显然这比网上的做法：监听UIApplicationDidBecomeActiveNotification在通知里面重新开始动画简单多了
            [view.layer addAnimation:rotationAnimation2 forKey:@"rotationAnimation2"];
            
            
            CABasicAnimation *anim2 = [CABasicAnimation animationWithKeyPath:@"shadowOffset"];
            anim2.toValue = [NSNumber numberWithFloat:1];
            anim2.duration = 3;
            anim2.fillMode = kCAFillModeForwards;
            anim2.removedOnCompletion = NO;
            [view.layer addAnimation:anim2 forKey:@"anim2"];
            
            CABasicAnimation *anim1 = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
            anim1.duration = 2;
             int  a =arc4random()%3;
            anim1.fromValue =  (__bridge id _Nullable)[[UIColor lightGrayColor]  colorWithAlphaComponent:a*0.1].CGColor;
            anim1.toValue =  (__bridge id _Nullable)[[UIColor lightGrayColor]  colorWithAlphaComponent:0.0].CGColor;
            //填充效果：动画结束后，动画将保持最后的表现状态
            anim1.fillMode = kCAFillModeForwards;
            anim1.removedOnCompletion = NO;
            anim1.beginTime = 0.0f;
            [view.layer addAnimation:anim1 forKey:@"backgroundColor"];
            
         

            
            
            
//            CABasicAnimation *anim2 = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
//            anim2.duration = 0.5;
//            anim2.fromValue =  (__bridge id _Nullable)[[UIColor lightGrayColor] colorWithAlphaComponent:a *0.1].CGColor;
//            anim2.toValue =  (__bridge id _Nullable)[[UIColor lightGrayColor] colorWithAlphaComponent:0.0].CGColor;
//            //填充效果：动画结束后，动画将保持最后的表现状态
//            anim2.fillMode = kCAFillModeForwards;
//            anim2.removedOnCompletion = NO;
//            anim2.beginTime = 0.0f;
//            [view.layer addAnimation:anim2 forKey:@"backgroundColor"];
//            view.layer.shadowColor = [UIColor whiteColor].CGColor;
//            view.layer.shadowOffset = CGSizeMake(0,1);
//            view.layer.shadowOpacity = 0;
            
            
        
            
            
            
//            [UIView animateWithDuration:[spectra[0][i] floatValue]*100 animations:^{
////                view.backgroundColor = self->initColors[arc4random()%self->initColors.count];
//                view.backgroundColor  = [[UIColor whiteColor]colorWithAlphaComponent:0.3];
//                view.layer.shadowColor = [[UIColor colorWithRed:135/225.0 green:206/255.0 blue:250/255.0 alpha:1.0] colorWithAlphaComponent:1.0].CGColor;
//                view.layer.shadowOffset = CGSizeMake(0,1);
//                view.layer.shadowOpacity = 2;
//
//
//
//
//            } completion:^(BOOL finished) {
//
//
//                [UIView animateWithDuration:0.11 animations:^{
//                    view.backgroundColor  = [[UIColor whiteColor]colorWithAlphaComponent:0.1];
//                    view.layer.shadowColor = [UIColor whiteColor].CGColor;
//                    view.layer.shadowOffset = CGSizeMake(0,1);
//                    view.layer.shadowOpacity = 0;
//                }];
//
//
//            }];
        }
        
        CGFloat y = [self translateAmplitudeToYPosition:[spectra[0][i] floatValue]];
        CGFloat angleTemp =  2.0 + i * (360.0 - 0) / (80 - 0);;
        CGFloat  musicLineHeight = CGRectGetHeight(self.bounds) - self.bottomSpace -y+1;
        NSArray *rectanglePointArray = [self calculateFourKeyPointForRectangleWithCircleCenter:self.center innerCircleRadius:120 rectangleWidht:10 rectangleHeight:musicLineHeight angle:angleTemp];
        CGPoint topLeftPoint = ((NSValue *)rectanglePointArray[0]).CGPointValue;
        CGPoint topRightPoint = ((NSValue *)rectanglePointArray[1]).CGPointValue;
        CGPoint bottomRightPoint = ((NSValue *)rectanglePointArray[2]).CGPointValue;
        CGPoint bottomLeftPoint = ((NSValue *)rectanglePointArray[3]).CGPointValue;

        /**线段*/
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:topLeftPoint];
        [path addLineToPoint:topRightPoint];
        [path addLineToPoint:bottomRightPoint];
        [path addLineToPoint:bottomLeftPoint];
        [path closePath];
//
        

        
        /**流体*/
//         UIBezierPath *paths = [UIBezierPath bezierPath];
//         [paths moveToPoint:topLeftPoint];
//         [paths addLineToPoint:topRightPoint];
//         [paths addLineToPoint:lastPointTopR];
//         [paths addLineToPoint:lastPointTopL];
//         [paths closePath];
//        [paths addQuadCurveToPoint:(CGPoint)topRightPoint  controlPoint:lastPointTopR ];
//
//        [paths addQuadCurveToPoint:(CGPoint) topRightPoint  controlPoint:lastPointTopL];
//        [paths addCurveToPoint:topRightPoint controlPoint1:lastPointTopR controlPoint2:lastPointTopL];
        
         
//        lastPointTopL=topLeftPoint;
//        lastPointTopR=topRightPoint;
        
        [leftPath appendPath:path];
//        [rightPath appendPath:path];
        /**点状*/
//        NSArray *rectanglePointArrays = [self calculateFourKeyPointForRectangleWithCircleCenter:self.center innerCircleRadius:125 rectangleWidht:2 rectangleHeight:musicLineHeight angle:angleTemp];
//        UIBezierPath *paths = [UIBezierPath bezierPathWithArcCenter:CGPointMake(((NSValue *)rectanglePointArrays[2]).CGPointValue.x, ((NSValue *)rectanglePointArrays[1]).CGPointValue.y) radius:2.0 startAngle:(-0.2*M_PI) endAngle:1.5f*M_PI clockwise:YES];
//        [paths closePath];
//        [rightPath appendPath:paths];
        
   


        /**波浪线*/
        //CGContextRef context = UIGraphicsGetCurrentContext();
        //CGContextSetFillColorWithColor(context, [UIColor greenColor].CGColor); // 填充色
        //CGContextSetStrokeColorWithColor(context, [UIColor redColor].CGColor); // 轨迹颜色
        //CGContextSetLineWidth(context, 1); // 轨迹宽度
        //CGContextAddArc(context, 100, 200, 80, -90 * M_PI / 180, 0.75 * M_PI / 180, 1); // 第二个参数：中心横坐标，第三个参数：中心纵坐标，第四个参数：半径，第五个参数:从哪开始，第六个参数：到哪结束，最后一个参数：0：顺时针，1：逆时针
        ////    CGContextStrokePath(context);  // 这是画线，也就是弧线。
        ////    CGContextFillPath(context);  // 这是填充颜色
        //CGContextDrawPath(context, kCGPathEOFillStroke); // 写这句就可以有填充色。
        ////绘制填充    CGPathDrawingMode是个枚举类，kCGPathFill填充非零绕数规则 没有边框 ,kCGPathEOFill表示用奇偶规则  也没有边框 ,kCGPathStroke路径  只有边框 ,kCGPathFillStroke路径填充 边框和填充色都有 , kCGPathEOFillStroke表示描线，不是填充  边框和填充色都有。专业的解释我不懂，效果我都试过了。
        
   
    }
    
    CAShapeLayer *leftMaskLayer = [CAShapeLayer layer];
    leftMaskLayer.path = leftPath.CGPath;
    self.leftGradientLayer.frame = CGRectMake(0, self.topSpace, CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds) - self.topSpace - self.bottomSpace);
    self.leftGradientLayer.mask = leftMaskLayer;
    
//    CAShapeLayer *rightMaskLayer = [CAShapeLayer layer];
//    rightMaskLayer.path = rightPath.CGPath;
//    self.rightGradientLayer.frame = CGRectMake(0, self.topSpace, CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds) - self.topSpace - self.bottomSpace);
//    self.rightGradientLayer.mask = rightMaskLayer;
    
//    if (spectra.count >= 2) {
//        UIBezierPath *rightPath = [UIBezierPath bezierPath];
//        count = [spectra[1] count];
//        for (int i = 0; i < count; i++) {
//            CGFloat x = (CGFloat)(count - 1 - i) * (self.barWidth + self.space) + self.space;
//            CGFloat y = [self translateAmplitudeToYPosition:[spectra[1][i] floatValue]];
//            CGRect rect = CGRectMake(x, y, self.barWidth, CGRectGetHeight(self.bounds) - self.bottomSpace -y);
//            UIBezierPath *bar;
//            switch (style) {
//                case ADSpectraStyleRect:
//                    bar = [UIBezierPath bezierPathWithRect:rect];
//                    break;
//                case ADSpectraStyleRound:
//                    bar = [UIBezierPath bezierPathWithRoundedRect:rect byRoundingCorners:UIRectCornerTopLeft | UIRectCornerTopRight cornerRadii:CGSizeMake(self.barWidth/2, self.barWidth/2)];
//                    break;
//            };
//            [rightPath appendPath:bar];
//        }
//        CAShapeLayer *rightMaskLayer = [CAShapeLayer layer];
//        rightMaskLayer.path = rightPath.CGPath;
//        self.rightGradientLayer.frame = CGRectMake(0, self.topSpace, CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds) - self.topSpace - self.bottomSpace);
//        self.rightGradientLayer.mask = rightMaskLayer;
//    }
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
- (NSArray *)calculateFourKeyPointForRectangleWithCircleCenter:(CGPoint)cirlceCenter innerCircleRadius:(CGFloat)innerCircleRadius rectangleWidht:(CGFloat)rectangleWidht rectangleHeight:(CGFloat)rectangleHeight angle:(CGFloat)angle {
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
//    CGFloat barHeight = (CGFloat)amplitude * (CGRectGetHeight(self.bounds) - self.bottomSpace - self.topSpace);
    CGFloat barHeight = (CGFloat)amplitude * self.frame.size.width/2;
    return CGRectGetHeight(self.bounds) - self.bottomSpace - barHeight;
}

- (CAGradientLayer *)leftGradientLayer {
    if (!_leftGradientLayer) {
        _leftGradientLayer = [CAGradientLayer layer];
        _leftGradientLayer.colors = @[(id)[UIColor colorWithRed:235/255.0 green:18/255.0 blue:26/255.0 alpha:1.0].CGColor, (id)[UIColor colorWithRed:255/255.0 green:165/255.0 blue:0/255.0 alpha:1.0].CGColor];
        _leftGradientLayer.locations = @[@0.6, @1.0];
      
        NSMutableArray *colors = [NSMutableArray array];
        for (NSInteger hue = 0; hue < 360; hue += 7) {

            UIColor *color;
            color = [UIColor colorWithHue:1.0 * hue / 360.0
                               saturation:1.0
                               brightness:1.0
                                    alpha:1.0];
            [colors addObject:(id)[color CGColor]];
        }

            [_leftGradientLayer setColors:[NSArray arrayWithArray:colors]];
        
        [self performAnimation];

    }
    return _leftGradientLayer;
}
//
- (CAGradientLayer *)rightGradientLayer {
    if (!_rightGradientLayer) {
        _rightGradientLayer = [CAGradientLayer layer];
//        _rightGradientLayer.colors = @[(id)[UIColor colorWithRed:0/255.0 green:128/255.0 blue:128/255.0 alpha:1.0].CGColor, (id)[UIColor colorWithRed:52/255.0 green:232/255.0 blue:158/255.0 alpha:1.0].CGColor];
//        _rightGradientLayer.locations = @[@0.6, @1.0];

        NSMutableArray *colors = [NSMutableArray array];
        for (NSInteger hue = 0; hue < 360; hue += 22.5) {

            UIColor *color;
            color = [UIColor colorWithHue:1.0 * hue / 360.0
                               saturation:1.0
                               brightness:1.0
                                    alpha:1.0];
            [colors addObject:(id)[color CGColor]];
        }

        [_rightGradientLayer setColors:[NSArray arrayWithArray:colors]];
    }
    return _rightGradientLayer;
}
- (void)performAnimation {
    // Move the last color in the array to the front
    // shifting all the other colors.
    CAGradientLayer *layer = (id)_leftGradientLayer;
    NSMutableArray *mutable = [[_leftGradientLayer colors] mutableCopy];
    id lastColor = [mutable lastObject];
    [mutable removeLastObject];
    [mutable insertObject:lastColor atIndex:0];
    NSArray *shiftedColors = [NSArray arrayWithArray:mutable];
    // Update the colors on the model layer
    [layer setColors:shiftedColors];
    
    // Create an animation to slowly move the gradient left to right.
    CABasicAnimation *animation;
    animation = [CABasicAnimation animationWithKeyPath:@"colors"];
    [animation setToValue:shiftedColors];
    [animation setDuration:0.15];
    [animation setRemovedOnCompletion:YES];
    [animation setFillMode:kCAFillModeForwards];
    [animation setDelegate:self];
    [layer addAnimation:animation forKey:@"animateGradient"];
    

    
}

- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)flag {
    if (enterBackground == YES)
    {
        return;
    }
    [self performAnimation];
}
/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/
#pragma mark 计算圆圈上点在IOS系统中的坐标
+(CGPoint) calcCircleCoordinateWithCenter:(CGPoint) center  andWithAngle : (CGFloat) angle andWithRadius: (CGFloat) radius{
    CGFloat x2 = radius*cosf(angle*M_PI/180);
    CGFloat y2 = radius*sinf(angle*M_PI/180);
    return CGPointMake(center.x+x2, center.y-y2);
}
//center中心点坐标
//angle是角度，如果是6个点 应分别传入 60 120 180 240 300 360
//radius半径
@end
