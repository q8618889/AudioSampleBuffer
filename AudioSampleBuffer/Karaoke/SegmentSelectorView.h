//
//  SegmentSelectorView.h
//  AudioSampleBuffer
//
//  Created on 2025/10/15.
//  片段选择器：歌词+起点终点滑块
//

#import <UIKit/UIKit.h>
#import "LyricsView.h"
#import "LRCParser.h"

NS_ASSUME_NONNULL_BEGIN

/// 片段选择器
@interface SegmentSelectorView : UIView

/// 歌词解析器
@property (nonatomic, strong) LRCParser *lyricsParser;

/// 歌曲总时长
@property (nonatomic, assign) NSTimeInterval totalDuration;

/// 初始起点时间（用于恢复上次选择）
@property (nonatomic, assign) NSTimeInterval initialStartTime;

/// 初始终点时间
@property (nonatomic, assign) NSTimeInterval initialEndTime;

/// 确认回调：返回起点和终点时间
@property (nonatomic, copy) void (^onConfirm)(NSTimeInterval startTime, NSTimeInterval endTime);

/// 取消回调
@property (nonatomic, copy) void (^onCancel)(void);

/// 全曲回调
@property (nonatomic, copy) void (^onSelectFull)(void);

/// 显示选择器
- (void)show;

/// 隐藏选择器
- (void)hide;

@end

NS_ASSUME_NONNULL_END

