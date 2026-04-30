//
//  RhythmColorMaskEffect.m
//

#import "RhythmColorMaskEffect.h"

@interface RhythmColorMaskEffect ()
@property (nonatomic, assign) CGFloat intensity;       // 0..1，beat 后衰减
@property (nonatomic, assign) CGPoint offset;          // 当前位移
@property (nonatomic, assign) NSInteger hueIndex;      // 色循环索引
@property (nonatomic, assign) CGFloat punchScale;
@property (nonatomic, assign) CGFloat sweepProgress;
@property (nonatomic, strong) CAGradientLayer *sweepLayer;
@end

@implementation RhythmColorMaskEffect

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.alpha = 0.0;
        self.backgroundColor = [self colorForIndex:0 style:RhythmColorMaskStyleHueCycle];
        _style = RhythmColorMaskStyleHueCycle;
        _dispersionEffectType = RhythmDispersionEffectTypeColorPulse;
        _maxAlpha = 0.0;
        _shiftMax = 0.0;
        _intensity = 0.0;
        _offset = CGPointZero;
        _hueIndex = 0;
        _punchScale = 0.0;
        _sweepProgress = 0.0;

        _sweepLayer = [CAGradientLayer layer];
        _sweepLayer.hidden = YES;
        _sweepLayer.opacity = 0.0f;
        _sweepLayer.colors = @[
            (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
            (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.78].CGColor,
            (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
        ];
        _sweepLayer.locations = @[@0.0, @0.5, @1.0];
        [self.layer addSublayer:_sweepLayer];
    }
    return self;
}

#pragma mark - Color palette

- (UIColor *)colorForIndex:(NSInteger)idx style:(RhythmColorMaskStyle)style {
    switch (style) {
        case RhythmColorMaskStyleWarmCool: {
            switch (idx % 2) {
                case 0:  return [UIColor colorWithRed:0.95 green:0.30 blue:0.20 alpha:1.0]; // 暖红
                default: return [UIColor colorWithRed:0.20 green:0.60 blue:0.95 alpha:1.0]; // 冷蓝
            }
        }
        case RhythmColorMaskStyleNeon: {
            switch (idx % 3) {
                case 0:  return [UIColor colorWithRed:0.95 green:0.20 blue:0.85 alpha:1.0]; // 粉
                case 1:  return [UIColor colorWithRed:0.20 green:0.95 blue:0.95 alpha:1.0]; // 青
                default: return [UIColor colorWithRed:0.50 green:0.20 blue:0.95 alpha:1.0]; // 紫
            }
        }
        case RhythmColorMaskStyleHueCycle:
        default: {
            switch (idx % 6) {
                case 0:  return [UIColor colorWithRed:0.95 green:0.20 blue:0.30 alpha:1.0]; // 红
                case 1:  return [UIColor colorWithRed:0.20 green:0.55 blue:0.95 alpha:1.0]; // 蓝
                case 2:  return [UIColor colorWithRed:0.95 green:0.50 blue:0.10 alpha:1.0]; // 橙
                case 3:  return [UIColor colorWithRed:0.30 green:0.85 blue:0.55 alpha:1.0]; // 青绿
                case 4:  return [UIColor colorWithRed:0.75 green:0.25 blue:0.85 alpha:1.0]; // 紫
                default: return [UIColor colorWithRed:0.95 green:0.80 blue:0.20 alpha:1.0]; // 黄
            }
        }
    }
}

#pragma mark - Public API

- (void)triggerOnBeatWithStrongMix:(float)strongMix axis:(NSInteger)axis {
    if (self.maxAlpha < 0.005) return;

    self.hueIndex = self.hueIndex + 1;
    self.backgroundColor = [self colorForIndex:self.hueIndex style:self.style];

    self.intensity = (CGFloat)(0.80 + 0.20 * strongMix);
    self.punchScale = (CGFloat)(0.06 + 0.10 * strongMix);
    self.sweepProgress = 0.0;

    CGFloat dir = (self.hueIndex % 2 == 0) ? 1.0 : -1.0;
    CGFloat amp = self.shiftMax * (CGFloat)(0.55 + 0.45 * strongMix);
    switch (self.dispersionEffectType) {
        case RhythmDispersionEffectTypeDualChromaticShift:
            amp *= 1.45;
            break;
        case RhythmDispersionEffectTypeFrameShakeZoomPunch:
            amp *= 1.25;
            self.punchScale *= 1.4;
            break;
        case RhythmDispersionEffectTypeSweepLight:
        case RhythmDispersionEffectTypeVignetteBreath:
        case RhythmDispersionEffectTypeEdgeGlowPulse:
            amp *= 0.55;
            break;
        case RhythmDispersionEffectTypeLocalFlash:
            self.backgroundColor = (self.hueIndex % 2 == 0) ? [UIColor whiteColor] : [UIColor blackColor];
            amp = 0.0;
            break;
        case RhythmDispersionEffectTypeColorPulse:
        default:
            break;
    }

    if (axis == 0) {
        self.offset = CGPointMake(dir * amp, 0);
    } else {
        self.offset = CGPointMake(0, dir * amp);
    }
}

- (void)tickWithDelta:(CFTimeInterval)dt {
    if (self.maxAlpha < 0.005) {
        if (self.alpha > 0.0 || !CGAffineTransformIsIdentity(self.transform)) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            self.alpha = 0.0;
            self.transform = CGAffineTransformIdentity;
            [CATransaction commit];
        }
        self.intensity = 0.0;
        self.offset = CGPointZero;
        self.punchScale = 0.0;
        self.sweepProgress = 0.0;
        self.layer.shadowOpacity = 0.0;
        self.layer.borderWidth = 0.0;
        self.sweepLayer.hidden = YES;
        self.sweepLayer.opacity = 0.0f;
        return;
    }

    self.intensity *= exp(-6.0 * dt);
    if (self.intensity < 0.005) self.intensity = 0.0;

    CGFloat decay = exp(-6.5 * dt);
    CGPoint p = self.offset;
    p.x *= decay;
    p.y *= decay;
    if (fabs(p.x) < 0.05) p.x = 0.0;
    if (fabs(p.y) < 0.05) p.y = 0.0;
    self.offset = p;

    self.punchScale *= exp(-7.2 * dt);
    if (self.punchScale < 0.001) self.punchScale = 0.0;
    self.sweepProgress = MIN(1.0, self.sweepProgress + dt * 4.2);

    CGFloat alpha = self.intensity * self.maxAlpha;
    if (alpha < 0.001) alpha = 0.0;
    if (alpha > self.maxAlpha) alpha = self.maxAlpha;

    CGFloat scale = 1.0;
    UIColor *fillColor = self.backgroundColor ?: [UIColor clearColor];
    self.layer.shadowColor = fillColor.CGColor;
    self.layer.shadowOffset = CGSizeZero;
    self.layer.shadowRadius = 0.0;
    self.layer.shadowOpacity = 0.0f;
    self.layer.borderWidth = 0.0;
    self.layer.borderColor = [UIColor clearColor].CGColor;
    self.sweepLayer.hidden = YES;
    self.sweepLayer.opacity = 0.0f;

    switch (self.dispersionEffectType) {
        case RhythmDispersionEffectTypeDualChromaticShift:
            alpha = MIN(self.maxAlpha * 1.15, alpha * 1.18);
            self.layer.shadowRadius = 18.0;
            self.layer.shadowOpacity = (float)(0.20 * self.intensity);
            break;
        case RhythmDispersionEffectTypeLocalFlash:
            alpha *= 0.90;
            break;
        case RhythmDispersionEffectTypeSweepLight: {
            alpha *= 0.25;
            self.backgroundColor = [UIColor clearColor];
            self.sweepLayer.hidden = NO;
            self.sweepLayer.opacity = (float)(0.85 * self.intensity);
            CGFloat sweepWidth = MAX(80.0, self.bounds.size.width * 0.35);
            CGFloat startX = -sweepWidth;
            CGFloat endX = self.bounds.size.width + sweepWidth;
            CGFloat sweepX = startX + (endX - startX) * self.sweepProgress;
            self.sweepLayer.frame = CGRectMake(sweepX - sweepWidth * 0.5, 0.0, sweepWidth, self.bounds.size.height);
            break;
        }
        case RhythmDispersionEffectTypeVignetteBreath:
            fillColor = [UIColor colorWithWhite:0.03 alpha:1.0];
            alpha *= 0.45;
            self.layer.shadowRadius = 28.0;
            self.layer.shadowOpacity = (float)(0.22 * self.intensity);
            break;
        case RhythmDispersionEffectTypeEdgeGlowPulse:
            alpha *= 0.16;
            self.backgroundColor = [UIColor clearColor];
            self.layer.borderWidth = 3.0 + 3.0 * self.intensity;
            self.layer.borderColor = [fillColor colorWithAlphaComponent:(0.55 * self.intensity)].CGColor;
            self.layer.shadowRadius = 22.0;
            self.layer.shadowOpacity = (float)(0.28 * self.intensity);
            break;
        case RhythmDispersionEffectTypeFrameShakeZoomPunch:
            alpha *= 0.18;
            scale = 1.0 + self.punchScale;
            break;
        case RhythmDispersionEffectTypeColorPulse:
        default:
            break;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.backgroundColor = fillColor;
    self.alpha = alpha;
    CGAffineTransform translation = CGAffineTransformMakeTranslation(p.x, p.y);
    self.transform = CGAffineTransformScale(translation, scale, scale);
    [CATransaction commit];
}

- (void)reset {
    self.intensity = 0.0;
    self.offset = CGPointZero;
    self.hueIndex = 0;
    self.punchScale = 0.0;
    self.sweepProgress = 0.0;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.alpha = 0.0;
    self.transform = CGAffineTransformIdentity;
    self.layer.shadowOpacity = 0.0;
    self.layer.borderWidth = 0.0;
    self.sweepLayer.hidden = YES;
    self.sweepLayer.opacity = 0.0f;
    [CATransaction commit];
}

- (NSString *)displayNameForCurrentEffect {
    switch (self.dispersionEffectType) {
        case RhythmDispersionEffectTypeDualChromaticShift: return @"双层色偏";
        case RhythmDispersionEffectTypeLocalFlash: return @"局部闪白/黑";
        case RhythmDispersionEffectTypeSweepLight: return @"扫光";
        case RhythmDispersionEffectTypeVignetteBreath: return @"Vignette 呼吸";
        case RhythmDispersionEffectTypeEdgeGlowPulse: return @"边缘发光";
        case RhythmDispersionEffectTypeFrameShakeZoomPunch: return @"Frame Punch";
        case RhythmDispersionEffectTypeColorPulse:
        default:
            return @"颜色脉冲";
    }
}

@end
