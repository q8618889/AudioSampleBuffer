#import <Foundation/Foundation.h>

#import "RhythmColorMaskEffect.h"
#import "RhythmFeatureEffectController.h"

NS_ASSUME_NONNULL_BEGIN

@interface RhythmEffectDescriptor : NSObject

@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *summary;
@property (nonatomic, assign, readonly) NSInteger rawValue;

+ (instancetype)descriptorWithTitle:(NSString *)title
                            summary:(NSString *)summary
                           rawValue:(NSInteger)rawValue;

+ (NSArray<RhythmEffectDescriptor *> *)dispersionDescriptors;
+ (NSArray<RhythmEffectDescriptor *> *)featureDescriptors;

@end

NS_ASSUME_NONNULL_END
