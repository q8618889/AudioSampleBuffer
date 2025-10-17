//
//  AudioPlayCell.m
//  AudioSampleBuffer
//
//  Created by gt on 2022/9/7.
//

#import "AudioPlayCell.h"

#define ScreenHeight    [[UIScreen mainScreen] bounds].size.height
#define ScreenWidth     [[UIScreen mainScreen] bounds].size.width

@interface AudioPlayCell ()
@property (nonatomic, strong) MusicItem *currentMusicItem;
@end

@implementation AudioPlayCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        
        self.contentView.backgroundColor = [UIColor clearColor];
        self.backgroundColor = [UIColor clearColor];
        
        // 歌曲名称标签（主标题）
        self.nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 5, ScreenWidth - 180, 22)];
        self.nameLabel.font = [UIFont boldSystemFontOfSize:16];
        self.nameLabel.textColor = [UIColor whiteColor];
        self.nameLabel.numberOfLines = 1;
        [self.contentView addSubview:self.nameLabel];
        
        // 艺术家标签（副标题）
        self.artistLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 28, ScreenWidth - 180, 16)];
        self.artistLabel.font = [UIFont systemFontOfSize:13];
        self.artistLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
        self.artistLabel.numberOfLines = 1;
        [self.contentView addSubview:self.artistLabel];
        
        // 时长标签（右侧第一行）
        self.durationLabel = [[UILabel alloc] initWithFrame:CGRectMake(ScreenWidth - 160, 5, 60, 18)];
        self.durationLabel.font = [UIFont systemFontOfSize:12];
        self.durationLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
        self.durationLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:self.durationLabel];
        
        // 文件大小标签（右侧第二行）
        self.fileSizeLabel = [[UILabel alloc] initWithFrame:CGRectMake(ScreenWidth - 160, 26, 60, 18)];
        self.fileSizeLabel.font = [UIFont systemFontOfSize:11];
        self.fileSizeLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
        self.fileSizeLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:self.fileSizeLabel];
        
        // 收藏按钮
        self.favoriteButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.favoriteButton.frame = CGRectMake(ScreenWidth - 90, 10, 40, 40);
        [self.favoriteButton setTitle:@"♡" forState:UIControlStateNormal];
        [self.favoriteButton setTitle:@"♥" forState:UIControlStateSelected];
        [self.favoriteButton setTitleColor:[UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0] forState:UIControlStateSelected];
        [self.favoriteButton setTitleColor:[UIColor colorWithWhite:0.6 alpha:1.0] forState:UIControlStateNormal];
        self.favoriteButton.titleLabel.font = [UIFont systemFontOfSize:24];
        [self.favoriteButton addTarget:self action:@selector(clickFavoriteButton:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.favoriteButton];
        
        // 播放按钮
        self.playBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        self.playBtn.selected = NO;
        self.playBtn.frame = CGRectMake(ScreenWidth - 45, 10, 40, 40);
        [self.playBtn setTitle:@"▶️" forState:UIControlStateNormal];
        [self.playBtn setTitle:@"⏸" forState:UIControlStateSelected];
        self.playBtn.titleLabel.font = [UIFont systemFontOfSize:20];
        [self.playBtn addTarget:self action:@selector(clickPlayButton:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.playBtn];
        
        // NCM转换按钮（初始隐藏）
        self.convertButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.convertButton.frame = CGRectMake(ScreenWidth - 145, 10, 50, 40);
        [self.convertButton setTitle:@"转换" forState:UIControlStateNormal];
        [self.convertButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.convertButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        self.convertButton.backgroundColor = [UIColor colorWithRed:1.0 green:0.6 blue:0.0 alpha:0.9];
        self.convertButton.layer.cornerRadius = 8;
        self.convertButton.layer.borderWidth = 1.0;
        self.convertButton.layer.borderColor = [UIColor orangeColor].CGColor;
        self.convertButton.hidden = YES; // 默认隐藏
        [self.convertButton addTarget:self action:@selector(clickConvertButton:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.convertButton];
    }
    return self;
}

- (void)clickPlayButton:(UIButton *)button {
    button.selected = !button.selected;
    if (self.playBlock) {
        self.playBlock(!button.selected);
    }
}

- (void)clickFavoriteButton:(UIButton *)button {
    if (self.favoriteBlock) {
        self.favoriteBlock();
    }
    
    // 添加动画效果
    [UIView animateWithDuration:0.2 animations:^{
        button.transform = CGAffineTransformMakeScale(1.3, 1.3);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 animations:^{
            button.transform = CGAffineTransformIdentity;
        }];
    }];
}

- (void)clickConvertButton:(UIButton *)button {
    if (self.convertBlock) {
        // 禁用按钮防止重复点击
        button.enabled = NO;
        [button setTitle:@"转换中..." forState:UIControlStateNormal];
        
        self.convertBlock();
    }
}

// 使用 MusicItem 配置 cell
- (void)configureWithMusicItem:(MusicItem *)musicItem {
    self.currentMusicItem = musicItem;
    
    // 设置歌曲名称
    self.nameLabel.text = musicItem.displayName ?: musicItem.fileName;
    
    // 设置艺术家（如果没有则显示文件类型）
    if (musicItem.artist && musicItem.artist.length > 0) {
        self.artistLabel.text = musicItem.artist;
    } else {
        NSString *ext = [musicItem.fileExtension uppercaseString];
        self.artistLabel.text = [NSString stringWithFormat:@"未知艺术家 · %@", ext];
    }
    
    // 设置时长
    self.durationLabel.text = [musicItem formattedDuration];
    
    // 设置文件大小
    self.fileSizeLabel.text = [musicItem formattedFileSize];
    
    // 设置收藏状态
    self.favoriteButton.selected = musicItem.isFavorite;
    
    // 如果是NCM文件，添加标记并显示转换按钮
    if (musicItem.isNCM) {
        if (musicItem.isDecrypted) {
            // 已解密，显示🔓标记，隐藏转换按钮
            self.nameLabel.text = [NSString stringWithFormat:@"🔓 %@", self.nameLabel.text];
            self.convertButton.hidden = YES;
        } else {
            // 未解密，显示🔒标记，显示转换按钮
            self.nameLabel.text = [NSString stringWithFormat:@"🔒 %@", self.nameLabel.text];
            self.convertButton.hidden = NO;
            self.convertButton.enabled = YES;
            [self.convertButton setTitle:@"转换" forState:UIControlStateNormal];
        }
    } else {
        // 非NCM文件，隐藏转换按钮
        self.convertButton.hidden = YES;
    }
    
    // 如果有播放次数，显示热度标记
    if (musicItem.playCount > 10) {
        self.nameLabel.text = [NSString stringWithFormat:@"🔥 %@", self.nameLabel.text];
    } else if (musicItem.playCount > 5) {
        self.nameLabel.text = [NSString stringWithFormat:@"⭐ %@", self.nameLabel.text];
    }
}

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}
@end
