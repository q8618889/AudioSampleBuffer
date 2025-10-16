//
//  KaraokeRecordingConfig.h
//  AudioSampleBuffer
//
//  Created on 2025/10/15.
//  录音配置：支持全曲/片段模式
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 录音模式
typedef NS_ENUM(NSInteger, KaraokeRecordingMode) {
    KaraokeRecordingModeFull,      // 全曲模式
    KaraokeRecordingModeSegment    // 片段模式（指定起点终点）
};

/// 录音配置
@interface KaraokeRecordingConfig : NSObject

/// 录音模式（默认全曲）
@property (nonatomic, assign) KaraokeRecordingMode mode;

/// 片段起始时间（秒）
@property (nonatomic, assign) NSTimeInterval segmentStartTime;

/// 片段结束时间（秒）
@property (nonatomic, assign) NSTimeInterval segmentEndTime;

/// 是否启用倒计时提示（进入片段前3秒提示）
@property (nonatomic, assign) BOOL enableCountdown;

/// 重置为全曲模式
- (void)resetToFullMode;

/// 设置片段模式
- (void)setSegmentModeWithStart:(NSTimeInterval)start end:(NSTimeInterval)end;

/// 判断指定时间是否在录音范围内
- (BOOL)shouldRecordAtTime:(NSTimeInterval)time;

/// 获取录音时长
- (NSTimeInterval)getRecordingDuration;

@end

NS_ASSUME_NONNULL_END

