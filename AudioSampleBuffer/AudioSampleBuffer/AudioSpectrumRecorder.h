#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol AudioSpectrumRecorderDelegate <NSObject>

- (void)recorderDidGenerateSpectrum:(NSArray *)spectrums;

@end

@interface AudioSpectrumRecorder : NSObject

@property (nonatomic, weak) id <AudioSpectrumRecorderDelegate> delegate;

- (void)startRecord;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
