//
//  RecordingPlaybackView.h
//  AudioSampleBuffer
//
//  Created on 2025/10/14.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RecordingPlaybackView : UIView

// 录音文件路径
@property (nonatomic, copy) NSString *filePath;

// 回调
@property (nonatomic, copy) void (^onClose)(void);
@property (nonatomic, copy) void (^onDelete)(NSString *filePath);
@property (nonatomic, copy) void (^onExport)(NSString *filePath);

@end

NS_ASSUME_NONNULL_END

