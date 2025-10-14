//
//  PCMAudioPlayer.h
//  AudioSampleBuffer
//
//  Created on 2025/10/14.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

NS_ASSUME_NONNULL_BEGIN

@protocol PCMAudioPlayerDelegate <NSObject>
@optional
- (void)audioPlayerDidFinishPlaying;
- (void)audioPlayerDidUpdateProgress:(float)progress currentTime:(NSTimeInterval)currentTime;
@end

@interface PCMAudioPlayer : NSObject

@property (nonatomic, weak) id<PCMAudioPlayerDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL isPlaying;
@property (nonatomic, assign, readonly) NSTimeInterval duration;
@property (nonatomic, assign, readonly) NSTimeInterval currentTime;

// 加载PCM文件
- (BOOL)loadPCMFile:(NSString *)filePath 
         sampleRate:(Float64)sampleRate 
           channels:(UInt32)channels 
       bitsPerSample:(UInt32)bitsPerSample;

// 播放控制
- (void)play;
- (void)pause;
- (void)stop;

// 跳转
- (void)seekToTime:(NSTimeInterval)time;

@end

NS_ASSUME_NONNULL_END

