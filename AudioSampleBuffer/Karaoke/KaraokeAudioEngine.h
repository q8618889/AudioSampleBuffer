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
#import "VoiceEffectProcessor.h"

NS_ASSUME_NONNULL_BEGIN

// 录音段落信息
@interface RecordingSegment : NSObject
@property (nonatomic, strong) NSMutableData *audioData;  // 🔧 改为存储混合后的音频（向后兼容）
@property (nonatomic, strong) NSMutableData *vocalData;  // 🆕 原始人声数据（未混BGM，已应用音效）
@property (nonatomic, assign) NSTimeInterval startTime;  // 在BGM中的起始时间（秒）
@property (nonatomic, assign) NSTimeInterval duration;   // 段落时长（秒）
@property (nonatomic, assign) BOOL isRecorded;  // 是否录制了人声（NO表示纯BGM段落）
@property (nonatomic, assign) VoiceEffectType appliedEffect;  // 🆕 录制时应用的音效类型
@property (nonatomic, assign) float appliedMicVolume;  // 🆕 录制时应用的麦克风音量
@end

@protocol KaraokeAudioEngineDelegate <NSObject>

@optional
- (void)audioEngineDidUpdateMicrophoneLevel:(float)level;
- (void)audioEngineDidUpdatePeakLevel:(float)peak;
- (void)audioEngineDidEncounterError:(NSError *)error;
- (void)audioEngineDidFinishPlaying;  // BGM播放完成回调
- (void)audioEngineDidUpdateRecordingSegments:(NSArray<RecordingSegment *> *)segments;  // 录音段落更新

@end

@interface KaraokeAudioEngine : NSObject <AVAudioPlayerDelegate>

@property (nonatomic, weak) id<KaraokeAudioEngineDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL isPlaying;
@property (nonatomic, assign, readonly) BOOL isRecording;
@property (nonatomic, assign, readonly) BOOL isRecordingPaused;  // 录音是否暂停（BGM继续播放）

// 音频播放器（用于BGM音量控制）
@property (nonatomic, strong, readonly) AVAudioPlayer *audioPlayer;

// 获取当前播放时间（基于BGM读取位置）
@property (nonatomic, assign, readonly) NSTimeInterval currentPlaybackTime;

// 录音段落管理（外部只读，返回不可变副本）
@property (nonatomic, copy, readonly) NSArray<RecordingSegment *> *recordingSegments;

// 耳返相关属性（外部只读，通过方法设置）
@property (nonatomic, assign, readonly) BOOL enableEarReturn;
@property (nonatomic, assign, readonly) float earReturnVolume;
@property (nonatomic, assign, readonly) float microphoneVolume;

// AudioUnit访问（用于手动控制）
@property (nonatomic, assign, readonly) AUGraph auGraph;

// 音频文件播放
- (void)loadAudioFile:(NSString *)filePath;
- (void)play;
- (void)playFromTime:(NSTimeInterval)startTime;  // 从指定时间开始播放
- (void)pause;
- (void)stop;
- (void)reset;  // 重置到初始状态，准备新的录音

// 分段录音控制
- (void)startRecording;  // 开始录音（从当前位置）
- (void)startRecordingFromTime:(NSTimeInterval)startTime;  // 从指定时间开始录音
- (void)pauseRecording;  // 暂停录音（BGM继续，不写入人声）
- (void)resumeRecording;  // 恢复录音
- (void)stopRecording;   // 停止录音并保存当前段落
- (void)finishRecording;  // 完成所有录音，合成最终文件

// 🆕 预览和试听
- (NSData *)previewSynthesizedAudio;  // 预览合成（不保存文件，返回音频数据）
- (NSData *)previewSynthesizedAudioWithBGMVolume:(float)bgmVolume 
                                       micVolume:(float)micVolume 
                                          effect:(VoiceEffectType)effectType;  // 🆕 使用指定参数预览
- (void)playPreview:(void (^)(NSError *error))completion;  // 播放预览音频
- (void)stopPreview;  // 停止预览播放
- (BOOL)isPlayingPreview;  // 是否正在播放预览
- (void)savePreviewToFile:(void (^)(NSString *filePath, NSError *error))completion;  // 保存预览到文件
- (void)invalidatePreviewCache;  // 🆕 清除预览缓存（参数改变时调用）

// 段落管理
- (void)jumpToTime:(NSTimeInterval)targetTime;  // 跳转到指定时间（跳过的部分填充BGM）
- (void)rewindToTime:(NSTimeInterval)targetTime;  // 回退到指定时间（删除之后的段落）
- (void)deleteSegmentAtIndex:(NSInteger)index;  // 删除指定段落
- (void)clearAllSegments;  // 清空所有段落

- (NSString *)getRecordingFilePath;  // 获取最终合成的文件路径
- (NSTimeInterval)getTotalRecordedDuration;  // 获取已录制的总时长

// 耳返控制
- (void)setEarReturnEnabled:(BOOL)enabled;
- (void)setEarReturnVolume:(float)volume;
- (void)setMicrophoneVolume:(float)volume;

// 音效处理
@property (nonatomic, strong, readonly) VoiceEffectProcessor *voiceEffectProcessor;
- (void)setVoiceEffect:(VoiceEffectType)effectType;

// 🆕 实时参数调整（播放中生效）
- (void)updatePreviewParametersIfPlaying;  // 如果正在播放预览，实时更新参数

// 🆕 预览播放状态查询
- (NSTimeInterval)currentPreviewTime;  // 获取预览播放当前时间
- (NSTimeInterval)previewDuration;     // 获取预览音频总时长

@end

NS_ASSUME_NONNULL_END