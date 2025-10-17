//
//  ViewController+CloudDownload.h
//  AudioSampleBuffer
//
//  云端下载功能扩展
//

#import "ViewController.h"
#import "MusicDownloadManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface ViewController (CloudDownload)

/**
 * 设置云端下载功能（在 viewDidLoad 中调用）
 */
- (void)setupCloudDownloadFeature;

/**
 * 显示云端搜索对话框
 */
- (void)showCloudDownloadDialog;

/**
 * 从搜索栏触发云端搜索（当本地没有结果时）
 */
- (void)searchCloudMusicWithKeyword:(NSString *)keyword;

@end

NS_ASSUME_NONNULL_END
