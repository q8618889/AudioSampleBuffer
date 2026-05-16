#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RhythmFeatureEffectType) {
    RhythmFeatureEffectTypeGlitch = 0,
    RhythmFeatureEffectTypeEchoTrail = 1,
    RhythmFeatureEffectTypeShockwave = 2,
    RhythmFeatureEffectTypeZoomBlurHit = 3,
    RhythmFeatureEffectTypeKaleidoscope = 4,
    RhythmFeatureEffectTypeWarpPull = 5,
    RhythmFeatureEffectTypeDroplet = 6,
    RhythmFeatureEffectTypePortal = 7,
    RhythmFeatureEffectTypeImpactWave = 8,
    RhythmFeatureEffectTypeMusicMicroscope = 9,
};

@interface RhythmFeatureEffectController : NSObject

@property (nonatomic, assign) RhythmFeatureEffectType selectedEffectType;
@property (nonatomic, assign, readonly) BOOL prefersMetalOverlay;
@property (nonatomic, assign, readonly) BOOL prefersTransformRenderer;
@property (nonatomic, assign) CGFloat transformIntensity;
@property (nonatomic, assign) CGFloat transformBeatBoost;
@property (nonatomic, assign) CGFloat transformRadius;
@property (nonatomic, assign) CGFloat transformSpeed;

/// Beat-sync mode: when YES, effects only animate on beat events (0 -> configured value -> 0).
/// When NO, effects play continuously with the configured intensity.
@property (nonatomic, assign) BOOL beatSyncEnabled;

- (NSDictionary<NSString *, NSNumber *> *)effectParametersForBeatWithStrongMix:(float)strongMix;
- (NSString *)displayNameForCurrentEffect;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
