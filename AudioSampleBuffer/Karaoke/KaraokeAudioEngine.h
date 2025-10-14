//
//  KaraokeAudioEngine.h
//  AudioSampleBuffer
//
//  Created on 2025/10/14.
//  参考：https://blog.csdn.net/weixin_43030741/article/details/103477017
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

NS_ASSUME_NONNULL_BEGIN

@protocol KaraokeAudioEngineDelegate <NSObject>

@optional
- (void)audioEngineDidUpdateMicrophoneLevel:(float)level;
- (void)audioEngineDidUpdatePeakLevel:(float)peak;
- (void)audioEngineDidEncounterError:(NSError *)error;
- (void)audioEngineDidFinishPlaying;  // BGM播放完成回调

@end

@interface KaraokeAudioEngine : NSObject <AVAudioPlayerDelegate>

@property (nonatomic, weak) id<KaraokeAudioEngineDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL isPlaying;
@property (nonatomic, assign, readonly) BOOL isRecording;

// 音频播放器（用于BGM音量控制）
@property (nonatomic, strong, readonly) AVAudioPlayer *audioPlayer;

// 获取当前播放时间（基于BGM读取位置）
@property (nonatomic, assign, readonly) NSTimeInterval currentPlaybackTime;

// 耳返相关属性（外部只读，通过方法设置）
@property (nonatomic, assign, readonly) BOOL enableEarReturn;
@property (nonatomic, assign, readonly) float earReturnVolume;
@property (nonatomic, assign, readonly) float microphoneVolume;

// 音频文件播放
- (void)loadAudioFile:(NSString *)filePath;
- (void)play;
- (void)pause;
- (void)stop;

// 录音控制（使用AudioUnit录音）
- (void)startRecording;
- (void)stopRecording;
- (NSString *)getRecordingFilePath;

// 耳返控制
- (void)setEarReturnEnabled:(BOOL)enabled;
- (void)setEarReturnVolume:(float)volume;
- (void)setMicrophoneVolume:(float)volume;

@end

NS_ASSUME_NONNULL_END