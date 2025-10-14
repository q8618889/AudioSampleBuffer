//
//  LyricsEffectCell.m
//  AudioSampleBuffer
//
//  支持特效的歌词单元格实现
//

#import "LyricsEffectCell.h"
#import <QuartzCore/QuartzCore.h>

@interface LyricsEffectCell ()

@property (nonatomic, strong) NSMutableArray<UILabel *> *characterLabels;
@property (nonatomic, strong) UILabel *mainLabel;
@property (nonatomic, strong) CAEmitterLayer *particleEmitter;

@end

@implementation LyricsEffectCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    
    // 主标签（用于大部分特效）
    _mainLabel = [[UILabel alloc] init];
    _mainLabel.textAlignment = NSTextAlignmentCenter;
    _mainLabel.numberOfLines = 0;
    _mainLabel.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:_mainLabel];
    
    _characterLabels = [NSMutableArray array];
    _effectType = LyricsEffectTypeNone;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _mainLabel.frame = self.contentView.bounds;
}

- (void)setLyricsText:(NSString *)lyricsText {
    _lyricsText = lyricsText;
    _mainLabel.text = lyricsText;
}

- (void)setIsHighlighted:(BOOL)isHighlighted {
    _isHighlighted = isHighlighted;
    _mainLabel.textColor = isHighlighted ? _highlightColor : _normalColor;
    _mainLabel.font = isHighlighted ? _highlightFont : _normalFont;
}

- (void)applyEffect:(BOOL)animated {
    if (!_isHighlighted) {
        [self resetEffect];
        return;
    }
    
    switch (_effectType) {
        case LyricsEffectTypeNone:
            [self applyNoneEffect:animated];
            break;
        case LyricsEffectTypeFadeInOut:
            [self applyFadeInOutEffect:animated];
            break;
        case LyricsEffectTypeSplitMerge:
            [self applySplitMergeEffect:animated];
            break;
        case LyricsEffectTypeCharacterAssemble:
            [self applyCharacterAssembleEffect:animated];
            break;
        case LyricsEffectTypeWave:
            [self applyWaveEffect:animated];
            break;
        case LyricsEffectTypeBounce:
            [self applyBounceEffect:animated];
            break;
        case LyricsEffectTypeGlitch:
            [self applyGlitchEffect:animated];
            break;
        case LyricsEffectTypeNeon:
            [self applyNeonEffect:animated];
            break;
        case LyricsEffectTypeTypewriter:
            [self applyTypewriterEffect:animated];
            break;
        case LyricsEffectTypeParticle:
            [self applyParticleEffect:animated];
            break;
        default:
            [self applyNoneEffect:animated];
            break;
    }
}

- (void)resetEffect {
    // 🔧 移除所有子视图的动画和效果
    [_mainLabel.layer removeAllAnimations];
    
    // 清理字符标签
    for (UILabel *label in _characterLabels) {
        [label.layer removeAllAnimations];
        [label removeFromSuperview];
    }
    [_characterLabels removeAllObjects];
    
    // 移除粒子效果
    if (_particleEmitter) {
        [_particleEmitter removeFromSuperlayer];
        _particleEmitter = nil;
    }
    
    // 重置主标签状态
    _mainLabel.alpha = 1.0;
    _mainLabel.transform = CGAffineTransformIdentity;
    _mainLabel.hidden = NO;
    
    // 🔧 清除所有可能的阴影和发光效果
    _mainLabel.layer.shadowOpacity = 0;
    _mainLabel.layer.shadowRadius = 0;
    
    // 🔧 确保 contentView 中只有 mainLabel
    for (UIView *subview in self.contentView.subviews) {
        if (subview != _mainLabel) {
            [subview removeFromSuperview];
        }
    }
}

#pragma mark - 特效实现

// 默认效果 - 简单放大
- (void)applyNoneEffect:(BOOL)animated {
    if (animated) {
        [UIView animateWithDuration:0.3 animations:^{
            self.mainLabel.transform = CGAffineTransformMakeScale(1.1, 1.1);
        }];
    } else {
        self.mainLabel.transform = CGAffineTransformMakeScale(1.1, 1.1);
    }
}

// 淡入淡出效果 - 带脉冲循环
- (void)applyFadeInOutEffect:(BOOL)animated {
    _mainLabel.transform = CGAffineTransformMakeScale(1.15, 1.15);
    
    if (animated) {
        // 🌫️ 呼吸脉冲效果 - 无限循环
        CABasicAnimation *pulseAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
        pulseAnimation.fromValue = @(0.7);
        pulseAnimation.toValue = @(1.0);
        pulseAnimation.duration = 1.2;
        pulseAnimation.autoreverses = YES;
        pulseAnimation.repeatCount = HUGE_VALF;  // ♻️ 无限循环
        pulseAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        
        [_mainLabel.layer addAnimation:pulseAnimation forKey:@"fadePulse"];
        
        // 🌫️ 微缩放效果
        CABasicAnimation *scaleAnimation = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        scaleAnimation.fromValue = @(1.1);
        scaleAnimation.toValue = @(1.2);
        scaleAnimation.duration = 1.2;
        scaleAnimation.autoreverses = YES;
        scaleAnimation.repeatCount = HUGE_VALF;
        
        [_mainLabel.layer addAnimation:scaleAnimation forKey:@"fadeScale"];
    }
}

// 撕裂合并效果
- (void)applySplitMergeEffect:(BOOL)animated {
    if (!animated) return;
    
    _mainLabel.hidden = YES;
    
    // 创建左右两部分
    NSString *text = _lyricsText ?: @"";
    NSInteger midPoint = text.length / 2;
    
    NSString *leftPart = [text substringToIndex:midPoint];
    NSString *rightPart = [text substringFromIndex:midPoint];
    
    UILabel *leftLabel = [self createCharacterLabel:leftPart];
    UILabel *rightLabel = [self createCharacterLabel:rightPart];
    
    CGRect bounds = _mainLabel.bounds;
    leftLabel.frame = CGRectMake(bounds.origin.x - 200, bounds.origin.y, bounds.size.width / 2, bounds.size.height);
    rightLabel.frame = CGRectMake(bounds.origin.x + bounds.size.width + 200, bounds.origin.y, bounds.size.width / 2, bounds.size.height);
    
    leftLabel.textAlignment = NSTextAlignmentRight;
    rightLabel.textAlignment = NSTextAlignmentLeft;
    
    [self.contentView addSubview:leftLabel];
    [self.contentView addSubview:rightLabel];
    [_characterLabels addObject:leftLabel];
    [_characterLabels addObject:rightLabel];
    
    // 动画合并
    [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
        leftLabel.frame = CGRectMake(bounds.origin.x, bounds.origin.y, bounds.size.width / 2, bounds.size.height);
        rightLabel.frame = CGRectMake(bounds.origin.x + bounds.size.width / 2, bounds.origin.y, bounds.size.width / 2, bounds.size.height);
    } completion:^(BOOL finished) {
        self.mainLabel.hidden = NO;
        [leftLabel removeFromSuperview];
        [rightLabel removeFromSuperview];
    }];
}

// 字符拼接效果
- (void)applyCharacterAssembleEffect:(BOOL)animated {
    if (!animated) return;
    
    _mainLabel.hidden = YES;
    
    NSString *text = _lyricsText ?: @"";
    CGFloat totalWidth = _mainLabel.bounds.size.width;
    CGFloat charWidth = totalWidth / MAX(1, text.length);
    
    for (NSInteger i = 0; i < text.length; i++) {
        NSString *character = [text substringWithRange:NSMakeRange(i, 1)];
        UILabel *charLabel = [self createCharacterLabel:character];
        
        charLabel.frame = CGRectMake(charWidth * i, 0, charWidth, _mainLabel.bounds.size.height);
        charLabel.alpha = 0.0;
        charLabel.transform = CGAffineTransformMakeScale(0.1, 0.1);
        
        [self.contentView addSubview:charLabel];
        [_characterLabels addObject:charLabel];
        
        // 逐个字符动画
        [UIView animateWithDuration:0.3 delay:i * 0.05 options:UIViewAnimationOptionCurveEaseOut animations:^{
            charLabel.alpha = 1.0;
            charLabel.transform = CGAffineTransformIdentity;
        } completion:^(BOOL finished) {
            if (i == text.length - 1) {
                // 最后一个字符完成后，显示主标签
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    self.mainLabel.hidden = NO;
                    for (UILabel *label in self.characterLabels) {
                        [label removeFromSuperview];
                    }
                    [self.characterLabels removeAllObjects];
                });
            }
        }];
    }
}

// 波浪效果 - 优化版：在原位置波浪，支持循环
- (void)applyWaveEffect:(BOOL)animated {
    if (!animated) return;
    
    _mainLabel.hidden = YES;
    
    NSString *text = _lyricsText ?: @"";
    
    // 🎨 计算字符宽度（使用字体测量，保持原始间距）
    UIFont *font = _highlightFont;
    NSDictionary *attributes = @{NSFontAttributeName: font};
    
    CGFloat xOffset = 0;
    CGFloat labelHeight = _mainLabel.bounds.size.height;
    CGFloat labelCenterY = _mainLabel.bounds.size.height / 2;
    
    for (NSInteger i = 0; i < text.length; i++) {
        NSString *character = [text substringWithRange:NSMakeRange(i, 1)];
        
        // 计算字符实际宽度
        CGSize charSize = [character sizeWithAttributes:attributes];
        
        UILabel *charLabel = [self createCharacterLabel:character];
        charLabel.frame = CGRectMake(xOffset, 0, charSize.width, labelHeight);
        
        [self.contentView addSubview:charLabel];
        [_characterLabels addObject:charLabel];
        
        // 🌊 循环波浪动画
        CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.y"];
        animation.values = @[@0, @(-15), @0];  // 波浪幅度
        animation.keyTimes = @[@0, @0.5, @1.0];
        animation.duration = 0.8;
        animation.beginTime = CACurrentMediaTime() + i * 0.06;  // 字符间延迟
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        animation.repeatCount = HUGE_VALF;  // ♻️ 无限循环
        
        [charLabel.layer addAnimation:animation forKey:@"wave"];
        
        xOffset += charSize.width;
    }
}

// 弹跳效果
- (void)applyBounceEffect:(BOOL)animated {
    if (!animated) {
        _mainLabel.transform = CGAffineTransformMakeScale(1.2, 1.2);
        return;
    }
    
    _mainLabel.transform = CGAffineTransformMakeScale(0.5, 0.5);
    
    [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:1.0 options:0 animations:^{
        self.mainLabel.transform = CGAffineTransformMakeScale(1.2, 1.2);
    } completion:nil];
}

// 故障艺术效果 - 循环播放
- (void)applyGlitchEffect:(BOOL)animated {
    if (!animated) return;
    
    // 创建多个重叠标签模拟故障
    for (NSInteger i = 0; i < 3; i++) {
        UILabel *glitchLabel = [self createCharacterLabel:_lyricsText];
        glitchLabel.frame = _mainLabel.frame;
        glitchLabel.alpha = 0.6;
        
        if (i == 0) {
            glitchLabel.textColor = [UIColor redColor];
        } else if (i == 1) {
            glitchLabel.textColor = [UIColor cyanColor];
        } else {
            glitchLabel.textColor = [UIColor yellowColor];
        }
        
        [self.contentView addSubview:glitchLabel];
        [_characterLabels addObject:glitchLabel];
        
        // 📺 随机偏移动画 - 无限循环
        CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
        animation.values = @[@0, @(arc4random() % 8 - 4), @(arc4random() % 8 - 4), @0];
        animation.keyTimes = @[@0, @0.3, @0.6, @1.0];
        animation.duration = 0.4;
        animation.repeatCount = HUGE_VALF;  // ♻️ 无限循环
        animation.beginTime = CACurrentMediaTime() + i * 0.1;
        
        [glitchLabel.layer addAnimation:animation forKey:@"glitch"];
        
        // 📺 闪烁效果
        CAKeyframeAnimation *alphaAnimation = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        alphaAnimation.values = @[@0.6, @0.8, @0.4, @0.6];
        alphaAnimation.keyTimes = @[@0, @0.3, @0.7, @1.0];
        alphaAnimation.duration = 0.6;
        alphaAnimation.repeatCount = HUGE_VALF;
        
        [glitchLabel.layer addAnimation:alphaAnimation forKey:@"glitchAlpha"];
    }
}

// 霓虹发光效果 - 循环播放
- (void)applyNeonEffect:(BOOL)animated {
    _mainLabel.layer.shadowColor = _highlightColor.CGColor;
    _mainLabel.layer.shadowRadius = 15.0;
    _mainLabel.layer.shadowOpacity = 1.0;
    _mainLabel.layer.shadowOffset = CGSizeZero;
    
    if (animated) {
        // 💡 发光动画 - 无限循环
        CABasicAnimation *glowAnimation = [CABasicAnimation animationWithKeyPath:@"shadowRadius"];
        glowAnimation.fromValue = @(5.0);
        glowAnimation.toValue = @(20.0);
        glowAnimation.duration = 0.8;
        glowAnimation.autoreverses = YES;
        glowAnimation.repeatCount = HUGE_VALF;  // ♻️ 无限循环
        
        [_mainLabel.layer addAnimation:glowAnimation forKey:@"neonGlow"];
        
        // 💡 颜色脉冲动画
        CABasicAnimation *colorAnimation = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
        colorAnimation.fromValue = @(0.6);
        colorAnimation.toValue = @(1.0);
        colorAnimation.duration = 1.0;
        colorAnimation.autoreverses = YES;
        colorAnimation.repeatCount = HUGE_VALF;
        
        [_mainLabel.layer addAnimation:colorAnimation forKey:@"neonPulse"];
    }
    
    _mainLabel.transform = CGAffineTransformMakeScale(1.15, 1.15);
}

// 打字机效果
- (void)applyTypewriterEffect:(BOOL)animated {
    if (!animated) return;
    
    _mainLabel.text = @"";
    NSString *fullText = _lyricsText ?: @"";
    
    __block NSInteger currentIndex = 0;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer * _Nonnull timer) {
        if (currentIndex < fullText.length) {
            self.mainLabel.text = [fullText substringToIndex:currentIndex + 1];
            currentIndex++;
        } else {
            [timer invalidate];
        }
    }];
    
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}

// 粒子效果
- (void)applyParticleEffect:(BOOL)animated {
    if (!animated) return;
    
    // 创建粒子发射器
    _particleEmitter = [CAEmitterLayer layer];
    _particleEmitter.emitterPosition = CGPointMake(self.contentView.bounds.size.width / 2, 
                                                    self.contentView.bounds.size.height / 2);
    _particleEmitter.emitterSize = self.contentView.bounds.size;
    _particleEmitter.emitterShape = kCAEmitterLayerRectangle;
    
    CAEmitterCell *particle = [CAEmitterCell emitterCell];
    particle.birthRate = 50;
    particle.lifetime = 1.0;
    particle.velocity = 50;
    particle.velocityRange = 20;
    particle.emissionRange = M_PI * 2;
    particle.scale = 0.3;
    particle.scaleRange = 0.2;
    particle.alphaSpeed = -1.0;
    particle.color = _highlightColor.CGColor;
    
    // 创建一个小圆点作为粒子
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(10, 10), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(context, _highlightColor.CGColor);
    CGContextFillEllipseInRect(context, CGRectMake(0, 0, 10, 10));
    UIImage *particleImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    particle.contents = (__bridge id)particleImage.CGImage;
    
    _particleEmitter.emitterCells = @[particle];
    [self.contentView.layer addSublayer:_particleEmitter];
    
    // 1秒后停止粒子
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.particleEmitter.birthRate = 0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.particleEmitter removeFromSuperlayer];
            self.particleEmitter = nil;
        });
    });
    
    _mainLabel.transform = CGAffineTransformMakeScale(1.2, 1.2);
}

#pragma mark - Helper Methods

- (UILabel *)createCharacterLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.textColor = _highlightColor;
    label.font = _highlightFont;
    label.textAlignment = NSTextAlignmentCenter;
    label.backgroundColor = [UIColor clearColor];
    return label;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    
    // 🔧 修复重叠bug：彻底清理所有特效
    [self resetEffect];
    
    // 清理所有动画
    [self.contentView.layer removeAllAnimations];
    [self.layer removeAllAnimations];
    
    // 重置透明度
    self.alpha = 1.0;
    self.contentView.alpha = 1.0;
    
    // 重置变换
    self.transform = CGAffineTransformIdentity;
    self.contentView.transform = CGAffineTransformIdentity;
}

@end

