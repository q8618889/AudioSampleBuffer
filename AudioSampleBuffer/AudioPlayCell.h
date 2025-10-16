//
//  AudioPlayCell.h
//  AudioSampleBuffer
//
//  Created by gt on 2022/9/7.
//

#import <UIKit/UIKit.h>
#import "MusicLibraryManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface AudioPlayCell : UITableViewCell

@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *artistLabel;       // 艺术家标签
@property (nonatomic, strong) UILabel *durationLabel;     // 时长标签
@property (nonatomic, strong) UILabel *fileSizeLabel;     // 文件大小标签
@property (nonatomic, strong) UIButton *favoriteButton;   // 收藏按钮
@property (nonatomic, strong) UIButton *playBtn;

@property (nonatomic, copy) void (^playBlock)(BOOL isPlaying); // 点击播放、暂停
@property (nonatomic, copy) void (^favoriteBlock)(void); // 点击收藏

// 使用 MusicItem 配置 cell
- (void)configureWithMusicItem:(MusicItem *)musicItem;

@end

NS_ASSUME_NONNULL_END
