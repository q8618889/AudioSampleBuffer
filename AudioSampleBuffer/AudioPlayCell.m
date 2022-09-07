//
//  AudioPlayCell.m
//  AudioSampleBuffer
//
//  Created by gt on 2022/9/7.
//

#import "AudioPlayCell.h"

#define ScreenHeight    [[UIScreen mainScreen] bounds].size.height
#define ScreenWidth     [[UIScreen mainScreen] bounds].size.width

@implementation AudioPlayCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        
        self.nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, ScreenWidth - 110, 40)];
        self.nameLabel.numberOfLines = 2;
        [self.contentView addSubview:self.nameLabel];
        
        self.playBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        self.playBtn.selected = NO;
        self.playBtn.frame = CGRectMake([UIScreen mainScreen].bounds.size.width-100, 10, 65, 40);
        [self.playBtn setTitle:@"Play" forState:UIControlStateNormal];
        [self.playBtn setTitle:@"Stop" forState:UIControlStateSelected];
        [self.playBtn addTarget:self action:@selector(clickPlayButton:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.playBtn];
        
    }
    return self;
}

- (void)clickPlayButton:(UIButton *)button {
    button.selected = !button.selected;
    if (self.playBlock) {
        self.playBlock(!button.selected);
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
