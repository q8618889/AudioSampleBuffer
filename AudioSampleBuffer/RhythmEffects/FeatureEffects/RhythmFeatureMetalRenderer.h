#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../../AudioSampleBuffer/RealtimeAnalyzerDSP.h"

#import "RhythmFeatureEffectController.h"

NS_ASSUME_NONNULL_BEGIN

@interface RhythmFeatureMetalRenderer : NSObject

@property (nonatomic, strong, readonly) UIView *view;
@property (nonatomic, assign) RhythmFeatureEffectType effectType;
@property (nonatomic, assign) BOOL beatSyncEnabled;

- (instancetype)initWithFrame:(CGRect)frame;
- (void)updateFrame:(CGRect)frame;
- (void)triggerBeatWithStrongMix:(float)strongMix;
- (void)triggerWithCategoryFeatures:(AnalyzerCategoryFeatures)features;
- (void)tickWithDelta:(CFTimeInterval)dt;
- (void)resetEnvelope;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
