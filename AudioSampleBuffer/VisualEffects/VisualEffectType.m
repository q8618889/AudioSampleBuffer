//
//  VisualEffectType.m
//  AudioSampleBuffer
//
//  高端视觉效果类型实现
//

#import "VisualEffectType.h"
#import <Metal/Metal.h>

@implementation VisualEffectInfo

+ (instancetype)effectWithType:(VisualEffectType)type 
                          name:(NSString *)name 
                   description:(NSString *)effectDescription 
                      category:(EffectCategory)category 
              performanceLevel:(PerformanceLevel)performanceLevel {
    VisualEffectInfo *info = [[VisualEffectInfo alloc] init];
    info.type = type;
    info.name = name;
    info.effectDescription = effectDescription;
    info.category = category;
    info.performanceLevel = performanceLevel;
    info.requiresMetal = (category == EffectCategoryMetal);
    info.supportsCustomization = YES;
    return info;
}

@end

@interface VisualEffectRegistry ()
@property (nonatomic, strong) NSArray<VisualEffectInfo *> *effects;
@end

@implementation VisualEffectRegistry

+ (instancetype)sharedRegistry {
    static VisualEffectRegistry *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VisualEffectRegistry alloc] init];
        [instance setupEffects];
    });
    return instance;
}

- (void)setupEffects {
    NSMutableArray *effects = [NSMutableArray array];
    
    // 基础效果
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeClassicSpectrum
                                                   name:@"经典频谱"
                                            description:@"经典的频谱柱状图显示"
                                               category:EffectCategoryBasic
                                       performanceLevel:PerformanceLevelLow]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeCircularWave
                                                   name:@"环形波浪"
                                            description:@"圆形波浪扩散效果"
                                               category:EffectCategoryBasic
                                       performanceLevel:PerformanceLevelMedium]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeParticleFlow
                                                   name:@"粒子流"
                                            description:@"动态粒子流动效果"
                                               category:EffectCategoryBasic
                                       performanceLevel:PerformanceLevelMedium]];
    
    // Metal高端效果
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeNeonGlow
                                                   name:@"霓虹发光"
                                            description:@"炫酷的霓虹灯光效果"
                                               category:EffectCategoryMetal
                                       performanceLevel:PerformanceLevelHigh]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectType3DWaveform
                                                   name:@"3D波形"
                                            description:@"立体的3D音频波形"
                                               category:EffectCategoryMetal
                                       performanceLevel:PerformanceLevelHigh]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeFluidSimulation
                                                   name:@"流体模拟"
                                            description:@"真实的流体物理模拟"
                                               category:EffectCategoryMetal
                                       performanceLevel:PerformanceLevelExtreme]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeQuantumField
                                                   name:@"量子场"
                                            description:@"神秘的量子场能量效果"
                                               category:EffectCategoryMetal
                                       performanceLevel:PerformanceLevelExtreme]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeHolographic
                                                   name:@"全息效果"
                                            description:@"科幻的全息投影效果"
                                               category:EffectCategoryMetal
                                       performanceLevel:PerformanceLevelHigh]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeCyberPunk
                                                   name:@"赛博朋克"
                                            description:@"未来主义的赛博朋克风格"
                                               category:EffectCategoryMetal
                                       performanceLevel:PerformanceLevelHigh]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeAudioReactive3D
                                                   name:@"音频响应3D"
                                            description:@"立体音频响应几何体"
                                               category:EffectCategoryMetal
                                       performanceLevel:PerformanceLevelExtreme]];
    
    // 创意效果
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeGalaxy
                                                   name:@"星系"
                                            description:@"绚丽的星系旋转效果"
                                               category:EffectCategoryCreative
                                       performanceLevel:PerformanceLevelHigh]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeLightning
                                                   name:@"闪电"
                                            description:@"电闪雷鸣的能量效果"
                                               category:EffectCategoryCreative
                                       performanceLevel:PerformanceLevelMedium]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeFireworks
                                                   name:@"烟花"
                                            description:@"绚烂的烟花绽放效果"
                                               category:EffectCategoryCreative
                                       performanceLevel:PerformanceLevelHigh]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeLiquidMetal
                                                   name:@"液态金属"
                                            description:@"流动的液态金属质感"
                                               category:EffectCategoryCreative
                                       performanceLevel:PerformanceLevelExtreme]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeGeometricMorph
                                                   name:@"几何变形"
                                            description:@"动态几何形状变形"
                                               category:EffectCategoryCreative
                                       performanceLevel:PerformanceLevelHigh]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeFractalPattern
                                                   name:@"分形图案"
                                            description:@"复杂的分形数学图案"
                                               category:EffectCategoryCreative
                                       performanceLevel:PerformanceLevelHigh]];
    
    self.effects = [effects copy];
}

- (NSArray<VisualEffectInfo *> *)allEffects {
    return self.effects;
}

- (NSArray<VisualEffectInfo *> *)effectsForCategory:(EffectCategory)category {
    return [self.effects filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(VisualEffectInfo *effect, NSDictionary *bindings) {
        return effect.category == category;
    }]];
}

- (VisualEffectInfo *)effectInfoForType:(VisualEffectType)type {
    for (VisualEffectInfo *effect in self.effects) {
        if (effect.type == type) {
            return effect;
        }
    }
    return nil;
}

- (BOOL)deviceSupportsEffect:(VisualEffectType)type {
    VisualEffectInfo *info = [self effectInfoForType:type];
    if (!info) return NO;
    
    // 检查Metal支持
    if (info.requiresMetal) {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        return device != nil;
    }
    
    return YES;
}

@end
