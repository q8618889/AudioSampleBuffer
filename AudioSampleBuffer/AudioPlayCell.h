//
//  AudioPlayCell.h
//  AudioSampleBuffer
//
//  Created by gt on 2022/9/7.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AudioPlayCell : UITableViewCell

@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIButton *playBtn;

@property (nonatomic, copy) void (^playBlock)(BOOL isPlaying); // 点击播放、暂停
@end

NS_ASSUME_NONNULL_END
