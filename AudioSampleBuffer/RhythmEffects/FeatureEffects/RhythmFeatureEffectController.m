#import "RhythmFeatureEffectController.h"

@implementation RhythmFeatureEffectController

static RhythmFeatureEffectType RhythmNormalizedFeatureEffectType(RhythmFeatureEffectType effectType) {
    switch (effectType) {
        case RhythmFeatureEffectTypeDroplet:
        case RhythmFeatureEffectTypeImpactWave:
        case RhythmFeatureEffectTypeMusicMicroscope:
            return effectType;
        case RhythmFeatureEffectTypePortal:
        case RhythmFeatureEffectTypeGlitch:
        case RhythmFeatureEffectTypeEchoTrail:
        case RhythmFeatureEffectTypeShockwave:
        case RhythmFeatureEffectTypeZoomBlurHit:
        case RhythmFeatureEffectTypeKaleidoscope:
        case RhythmFeatureEffectTypeWarpPull:
        default:
            return RhythmFeatureEffectTypeDroplet;
    }
}

- (BOOL)prefersMetalOverlay {
    RhythmFeatureEffectType type = RhythmNormalizedFeatureEffectType(self.selectedEffectType);
    return type == RhythmFeatureEffectTypeMusicMicroscope;
}

- (BOOL)prefersTransformRenderer {
    switch (RhythmNormalizedFeatureEffectType(self.selectedEffectType)) {
        case RhythmFeatureEffectTypeDroplet:
        case RhythmFeatureEffectTypeImpactWave:
            return YES;
        case RhythmFeatureEffectTypeMusicMicroscope:
        default:
            return NO;
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _selectedEffectType = RhythmFeatureEffectTypeDroplet;
        _transformIntensity = 0.72f;
        _transformBeatBoost = 0.82f;
        _transformRadius = 0.56f;
        _transformSpeed = 0.64f;
        _beatSyncEnabled = NO;
    }
    return self;
}

- (NSDictionary<NSString *, NSNumber *> *)effectParametersForBeatWithStrongMix:(float)strongMix {
    (void)strongMix;
    float boost = 0.0f;
    float blur = 0.0f;
    float flash = 0.0f;
    float scale = 0.0f;

    switch (RhythmNormalizedFeatureEffectType(self.selectedEffectType)) {
        case RhythmFeatureEffectTypeDroplet:
        case RhythmFeatureEffectTypeImpactWave:
        case RhythmFeatureEffectTypeMusicMicroscope:
            break;
        default:
            break;
    }

    return @{
        @"boost": @(boost),
        @"blur": @(blur),
        @"flash": @(flash),
        @"scale": @(scale),
    };
}

- (NSString *)displayNameForCurrentEffect {
    switch (RhythmNormalizedFeatureEffectType(self.selectedEffectType)) {
        case RhythmFeatureEffectTypeDroplet: return @"Droplet";
        case RhythmFeatureEffectTypeImpactWave: return @"Impact Wave";
        case RhythmFeatureEffectTypeMusicMicroscope: return @"Music Microscope";
        default:
            return @"Droplet";
    }
}

- (void)reset {
    self.transformIntensity = 0.72f;
    self.transformBeatBoost = 0.82f;
    self.transformRadius = 0.56f;
    self.transformSpeed = 0.64f;
}

@end
