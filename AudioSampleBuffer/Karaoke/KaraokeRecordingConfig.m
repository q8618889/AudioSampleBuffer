//
//  KaraokeRecordingConfig.m
//  AudioSampleBuffer
//
//  Created on 2025/10/15.
//

#import "KaraokeRecordingConfig.h"

@implementation KaraokeRecordingConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _mode = KaraokeRecordingModeFull;  // 默认全曲模式
        _segmentStartTime = 0.0;
        _segmentEndTime = 0.0;
        _enableCountdown = YES;  // 默认启用倒计时
    }
    return self;
}

- (void)resetToFullMode {
    self.mode = KaraokeRecordingModeFull;
    self.segmentStartTime = 0.0;
    self.segmentEndTime = 0.0;
    NSLog(@"🔄 录音模式重置为：全曲");
}

- (void)setSegmentModeWithStart:(NSTimeInterval)start end:(NSTimeInterval)end {
    if (end <= start) {
        NSLog(@"⚠️ 片段结束时间必须大于起始时间");
        return;
    }
    
    self.mode = KaraokeRecordingModeSegment;
    self.segmentStartTime = start;
    self.segmentEndTime = end;
    
    NSLog(@"✅ 录音模式设置为：片段 (%.2fs ~ %.2fs，时长%.2fs)",
          start, end, end - start);
}

- (BOOL)shouldRecordAtTime:(NSTimeInterval)time {
    if (self.mode == KaraokeRecordingModeFull) {
        return YES;  // 全曲模式，所有时间都录
    }
    
    // 片段模式：只在范围内录音
    return (time >= self.segmentStartTime && time < self.segmentEndTime);
}

- (NSTimeInterval)getRecordingDuration {
    if (self.mode == KaraokeRecordingModeFull) {
        return 0;  // 全曲模式返回0（表示录完整曲）
    }
    
    return self.segmentEndTime - self.segmentStartTime;
}

- (NSString *)description {
    if (self.mode == KaraokeRecordingModeFull) {
        return @"全曲模式";
    } else {
        return [NSString stringWithFormat:@"片段模式: %@ ~ %@",
                [self formatTime:self.segmentStartTime],
                [self formatTime:self.segmentEndTime]];
    }
}

- (NSString *)formatTime:(NSTimeInterval)time {
    int minutes = (int)time / 60;
    int seconds = (int)time % 60;
    return [NSString stringWithFormat:@"%d:%02d", minutes, seconds];
}

@end

