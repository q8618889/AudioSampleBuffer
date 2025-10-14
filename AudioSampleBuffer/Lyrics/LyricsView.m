//
//  LyricsView.m
//  AudioSampleBuffer
//
//  Created for displaying synchronized lyrics
//

#import "LyricsView.h"
#import "LyricsEffectCell.h"

@interface LyricsView () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, strong) UILabel *noLyricsLabel;

@end

@implementation LyricsView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupUI];
        [self setupDefaultStyle];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super initWithCoder:coder]) {
        [self setupUI];
        [self setupDefaultStyle];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [UIColor clearColor];
    
    // TableView
    _tableView = [[UITableView alloc] initWithFrame:self.bounds style:UITableViewStylePlain];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.showsVerticalScrollIndicator = NO;
    _tableView.showsHorizontalScrollIndicator = NO;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    // 设置内容边距，让当前歌词显示在中间
    _tableView.contentInset = UIEdgeInsetsMake(self.bounds.size.height / 2,
                                                0,
                                                self.bounds.size.height / 2,
                                                0);
    
    [self addSubview:_tableView];
    
    // 无歌词提示
    _noLyricsLabel = [[UILabel alloc] initWithFrame:self.bounds];
    _noLyricsLabel.text = @"暂无lrc文件歌词";
    _noLyricsLabel.textAlignment = NSTextAlignmentCenter;
    _noLyricsLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    _noLyricsLabel.font = [UIFont systemFontOfSize:16];
    _noLyricsLabel.hidden = YES;
    _noLyricsLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_noLyricsLabel];
    
    _currentIndex = -1;
    _autoScroll = YES;
}

- (void)setupDefaultStyle {
    _highlightColor = [UIColor whiteColor];
    _normalColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    _lyricsFont = [UIFont systemFontOfSize:15];
    _highlightFont = [UIFont boldSystemFontOfSize:17];
    _lineSpacing = 20;
    _currentEffect = LyricsEffectTypeNone;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    // 更新内容边距
    _tableView.contentInset = UIEdgeInsetsMake(self.bounds.size.height / 2,
                                                0,
                                                self.bounds.size.height / 2,
                                                0);
}

#pragma mark - Public Methods

- (void)setParser:(LRCParser *)parser {
    _parser = parser;
    _currentIndex = -1;
    
    [_tableView reloadData];
    
    if (!parser || parser.lyrics.count == 0) {
        _noLyricsLabel.hidden = NO;
        _tableView.hidden = YES;
    } else {
        _noLyricsLabel.hidden = YES;
        _tableView.hidden = NO;
    }
}

- (void)updateWithTime:(NSTimeInterval)currentTime {
    if (!_parser) {
        return;
    }
    
    NSInteger newIndex = [_parser indexForTime:currentTime];
    
    if (newIndex != _currentIndex && newIndex >= 0) {
        NSInteger oldIndex = _currentIndex;
        _currentIndex = newIndex;
        
        // 🔧 刷新旧的、新的和周围的行（用于更新透明度渐变效果）
        NSMutableArray *indexPaths = [NSMutableArray array];
        
        // 添加旧索引及其周围的行
        if (oldIndex >= 0 && oldIndex < _parser.lyrics.count) {
            for (NSInteger i = oldIndex - 3; i <= oldIndex + 3; i++) {
                if (i >= 0 && i < _parser.lyrics.count) {
                    [indexPaths addObject:[NSIndexPath indexPathForRow:i inSection:0]];
                }
            }
        }
        
        // 添加新索引及其周围的行
        if (newIndex >= 0 && newIndex < _parser.lyrics.count) {
            for (NSInteger i = newIndex - 3; i <= newIndex + 3; i++) {
                if (i >= 0 && i < _parser.lyrics.count) {
                    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:0];
                    if (![indexPaths containsObject:indexPath]) {
                        [indexPaths addObject:indexPath];
                    }
                }
            }
        }
        
        if (indexPaths.count > 0) {
            [_tableView reloadRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationNone];
        }
        
        // 自动滚动到当前歌词
        if (_autoScroll && newIndex >= 0) {
            [self scrollToIndex:newIndex animated:YES];
        }
    }
}

- (void)reset {
    _currentIndex = -1;
    [_tableView reloadData];
    [_tableView setContentOffset:CGPointMake(0, -_tableView.contentInset.top) animated:NO];
}

- (void)scrollToIndex:(NSInteger)index animated:(BOOL)animated {
    if (index < 0 || index >= _parser.lyrics.count) {
        return;
    }
    
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
    [_tableView scrollToRowAtIndexPath:indexPath
                      atScrollPosition:UITableViewScrollPositionMiddle
                              animated:animated];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _parser ? _parser.lyrics.count : 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"LyricsEffectCell";
    
    LyricsEffectCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[LyricsEffectCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    }
    
    LRCLine *line = _parser.lyrics[indexPath.row];
    BOOL isCurrentLine = (indexPath.row == _currentIndex);
    
    cell.lyricsText = line.text;
    cell.isHighlighted = isCurrentLine;
    cell.effectType = _currentEffect;
    cell.highlightColor = _highlightColor;
    cell.normalColor = _normalColor;
    cell.highlightFont = _highlightFont;
    cell.normalFont = _lyricsFont;
    
    // 🎨 计算距离当前行的距离，实现渐进渐出效果
    NSInteger distance = labs(indexPath.row - _currentIndex);
    CGFloat alpha = 1.0;
    
    if (distance == 0) {
        alpha = 1.0; // 当前行完全不透明
    } else if (distance == 1) {
        alpha = 0.8; // 相邻行
    } else if (distance == 2) {
        alpha = 0.6; // 第二行
    } else if (distance == 3) {
        alpha = 0.4; // 第三行
    } else {
        alpha = 0.2; // 更远的行，几乎透明
    }
    
    cell.alpha = alpha;
    
    // 应用特效
    if (isCurrentLine) {
        [cell applyEffect:YES];
    } else {
        [cell resetEffect];
    }
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    LRCLine *line = _parser.lyrics[indexPath.row];
    BOOL isCurrentLine = (indexPath.row == _currentIndex);
    UIFont *font = isCurrentLine ? _highlightFont : _lyricsFont;
    
    CGFloat width = tableView.bounds.size.width - 40; // 左右各20边距
    CGSize size = [line.text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
                                          options:NSStringDrawingUsesLineFragmentOrigin
                                       attributes:@{NSFontAttributeName: font}
                                          context:nil].size;
    
    return MAX(size.height + _lineSpacing, _lineSpacing * 2);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // 点击歌词后暂时禁用自动滚动
    _autoScroll = NO;
    
    // 延迟恢复自动滚动
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.autoScroll = YES;
    });
}

#pragma mark - Public Methods - Effect

- (void)setLyricsEffect:(LyricsEffectType)effectType {
    _currentEffect = effectType;
    [_tableView reloadData];
}

@end

