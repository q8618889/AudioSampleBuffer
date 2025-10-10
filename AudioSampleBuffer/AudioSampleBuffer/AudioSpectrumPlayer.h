
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol AudioSpectrumPlayerDelegate <NSObject>

- (void)playerDidGenerateSpectrum:(NSArray *)spectrums;
-(void)didFinishPlay;
@end

@interface AudioSpectrumPlayer : NSObject

@property (nonatomic, weak) id <AudioSpectrumPlayerDelegate> delegate;
@property(nonatomic,assign)BOOL  isPlaying;
@property (nonatomic, assign) NSTimeInterval duration;//总时长
- (void)playWithFileName:(NSString *)fileName;
- (void)stop;


@end

NS_ASSUME_NONNULL_END
