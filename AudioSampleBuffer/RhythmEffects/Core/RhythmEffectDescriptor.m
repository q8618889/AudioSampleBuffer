#import "RhythmEffectDescriptor.h"

@interface RhythmEffectDescriptor ()

@property (nonatomic, copy, readwrite) NSString *title;
@property (nonatomic, copy, readwrite) NSString *summary;
@property (nonatomic, assign, readwrite) NSInteger rawValue;

@end

@implementation RhythmEffectDescriptor

+ (instancetype)descriptorWithTitle:(NSString *)title
                            summary:(NSString *)summary
                           rawValue:(NSInteger)rawValue {
    RhythmEffectDescriptor *descriptor = [[self alloc] init];
    descriptor.title = [title copy];
    descriptor.summary = [summary copy];
    descriptor.rawValue = rawValue;
    return descriptor;
}

+ (NSArray<RhythmEffectDescriptor *> *)dispersionDescriptors {
    return @[
        [self descriptorWithTitle:@"颜色脉冲" summary:@"拍点切色和轻位移，适合常驻律动。" rawValue:RhythmDispersionEffectTypeColorPulse],
        [self descriptorWithTitle:@"双层色偏" summary:@"更强的色偏和偏移，适合强调强拍。" rawValue:RhythmDispersionEffectTypeDualChromaticShift],
        [self descriptorWithTitle:@"局部闪白/黑" summary:@"短促曝光闪，适合切拍和鼓点。" rawValue:RhythmDispersionEffectTypeLocalFlash],
        [self descriptorWithTitle:@"扫光" summary:@"一道扫过的亮带，适合流动感段落。" rawValue:RhythmDispersionEffectTypeSweepLight],
        [self descriptorWithTitle:@"Vignette 呼吸" summary:@"四周压暗再回弹，适合氛围型铺底。" rawValue:RhythmDispersionEffectTypeVignetteBreath],
        [self descriptorWithTitle:@"边缘发光" summary:@"屏幕边缘打亮，适合副歌抬升。" rawValue:RhythmDispersionEffectTypeEdgeGlowPulse],
        [self descriptorWithTitle:@"Frame Punch" summary:@"轻微抖动和 zoom punch，适合重拍。" rawValue:RhythmDispersionEffectTypeFrameShakeZoomPunch],
    ];
}

+ (NSArray<RhythmEffectDescriptor *> *)featureDescriptors {
    return @[
        [self descriptorWithTitle:@"珠滴" summary:@"水珠折射和液态拉扯，重点改画面本身。" rawValue:RhythmFeatureEffectTypeDroplet],
        [self descriptorWithTitle:@"冲击波" summary:@"拍点炸出一圈位移波纹，适合卡鼓点。" rawValue:RhythmFeatureEffectTypeImpactWave],
    ];
}

@end
