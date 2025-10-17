//
//  KaraokeViewController.h
//  AudioSampleBuffer
//
//  Created on 2025/10/14.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface KaraokeViewController : UIViewController

// 当前播放的歌曲名称
@property (nonatomic, strong) NSString *currentSongName;

// 🔧 当前歌曲的完整文件路径（优先使用，支持 ncm 解密后的路径）
@property (nonatomic, strong) NSString *currentSongPath;

@end

NS_ASSUME_NONNULL_END

