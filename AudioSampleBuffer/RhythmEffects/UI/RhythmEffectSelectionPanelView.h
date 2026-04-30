#import <UIKit/UIKit.h>

#import "RhythmColorMaskEffect.h"
#import "RhythmFeatureEffectController.h"

NS_ASSUME_NONNULL_BEGIN

@interface RhythmEffectSelectionPanelView : UIView

@property (nonatomic, copy, nullable) void (^closeHandler)(void);
@property (nonatomic, copy, nullable) void (^toggleEnabledHandler)(BOOL enabled);
@property (nonatomic, copy, nullable) void (^dispersionSelectionHandler)(RhythmDispersionEffectType type);
@property (nonatomic, copy, nullable) void (^featureSelectionHandler)(RhythmFeatureEffectType type);
@property (nonatomic, copy, nullable) void (^featureParameterChangedHandler)(CGFloat intensity, CGFloat beatBoost, CGFloat radius, CGFloat speed);
@property (nonatomic, copy, nullable) void (^beatSyncChangedHandler)(BOOL beatSyncEnabled);

- (void)applyRhythmEnabled:(BOOL)enabled
        dispersionEffect:(RhythmDispersionEffectType)dispersionEffect
             featureEffect:(RhythmFeatureEffectType)featureEffect
         transformIntensity:(CGFloat)transformIntensity
            transformBeatBoost:(CGFloat)transformBeatBoost
              transformRadius:(CGFloat)transformRadius
               transformSpeed:(CGFloat)transformSpeed
              beatSyncEnabled:(BOOL)beatSyncEnabled;

@end

NS_ASSUME_NONNULL_END
