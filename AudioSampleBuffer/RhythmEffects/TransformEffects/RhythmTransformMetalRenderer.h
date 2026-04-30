#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "RhythmFeatureEffectController.h"

@class AVPlayer;

NS_ASSUME_NONNULL_BEGIN

@interface RhythmTransformMetalRenderer : NSObject

@property (nonatomic, assign) RhythmFeatureEffectType effectType;
@property (nonatomic, assign) CGFloat baseIntensity;
@property (nonatomic, assign) CGFloat beatBoost;
@property (nonatomic, assign) CGFloat radius;
@property (nonatomic, assign) CGFloat speed;
@property (nonatomic, assign) BOOL beatSyncEnabled;

- (instancetype)initWithFrame:(CGRect)frame;
- (UIView *)view;
- (void)attachToPlayer:(nullable AVPlayer *)player;
- (void)updateFrame:(CGRect)frame;
- (void)triggerBeatWithStrongMix:(float)strongMix;
- (void)tickWithDelta:(CFTimeInterval)dt;
- (void)resetEnvelope;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
