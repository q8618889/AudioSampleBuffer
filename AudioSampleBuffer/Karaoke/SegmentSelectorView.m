//
//  SegmentSelectorView.m
//  AudioSampleBuffer
//
//  Created on 2025/10/15.
//

#import "SegmentSelectorView.h"
#import "LRCParser.h"

@interface SegmentSelectorView () <UIGestureRecognizerDelegate>

// UI组件
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIView *backgroundView;
@property (nonatomic, strong) UIScrollView *lyricsScrollView;  // 歌词滚动视图
@property (nonatomic, strong) UIView *lyricsContentView;  // 歌词内容容器
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UISegmentedControl *modeControl;

// 🆕 可拖动的分界线
@property (nonatomic, strong) UIView *startMarkerLine;  // 起点标记线（绿色）
@property (nonatomic, strong) UIView *endMarkerLine;    // 终点标记线（红色）
@property (nonatomic, strong) UILabel *startMarkerLabel;  // 起点时间标签
@property (nonatomic, strong) UILabel *endMarkerLabel;    // 终点时间标签

// 歌词行数组
@property (nonatomic, strong) NSMutableArray<UILabel *> *lyricLabels;

// 当前选择的时间
@property (nonatomic, assign) NSTimeInterval currentStartTime;
@property (nonatomic, assign) NSTimeInterval currentEndTime;

// 拖动状态
@property (nonatomic, assign) BOOL isDraggingStartMarker;
@property (nonatomic, assign) BOOL isDraggingEndMarker;

@end

@implementation SegmentSelectorView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    // 初始化数组
    self.lyricLabels = [NSMutableArray array];
    
    // 半透明背景
    self.backgroundView = [[UIView alloc] initWithFrame:self.bounds];
    self.backgroundView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTapped)];
    [self.backgroundView addGestureRecognizer:tapGesture];
    [self addSubview:self.backgroundView];
    
    // 容器视图
    CGFloat containerWidth = self.bounds.size.width - 40;
    CGFloat containerHeight = self.bounds.size.height * 0.8;
    CGFloat containerX = 20;
    CGFloat containerY = (self.bounds.size.height - containerHeight) / 2;
    
    self.containerView = [[UIView alloc] initWithFrame:CGRectMake(containerX, containerY, containerWidth, containerHeight)];
    self.containerView.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.98];
    self.containerView.layer.cornerRadius = 20;
    self.containerView.layer.borderWidth = 2;
    self.containerView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0].CGColor;
    [self addSubview:self.containerView];
    
    CGFloat currentY = 20;
    
    // 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, currentY, containerWidth, 35)];
    titleLabel.text = @"📍 选片段";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:24];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.containerView addSubview:titleLabel];
    currentY += 45;
    
    // 模式切换（全曲/片段）
    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"全曲", @"片段"]];
    self.modeControl.frame = CGRectMake(20, currentY, containerWidth - 40, 36);
    self.modeControl.selectedSegmentIndex = 0;
    self.modeControl.selectedSegmentTintColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    [self.modeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateNormal];
    [self.modeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor blackColor]} forState:UIControlStateSelected];
    [self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.containerView addSubview:self.modeControl];
    currentY += 50;
    
    // 🆕 歌词滚动视图（带可拖动分界线）
    CGFloat lyricsScrollHeight = containerHeight - currentY - 100;  // 预留底部按钮空间
    self.lyricsScrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(20, currentY, containerWidth - 40, lyricsScrollHeight)];
    self.lyricsScrollView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.8];
    self.lyricsScrollView.layer.cornerRadius = 12;
    self.lyricsScrollView.showsVerticalScrollIndicator = YES;
    self.lyricsScrollView.hidden = YES;  // 默认隐藏（全曲模式）
    [self.containerView addSubview:self.lyricsScrollView];
    
    // 歌词内容容器
    self.lyricsContentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.lyricsScrollView.frame.size.width, 0)];
    [self.lyricsScrollView addSubview:self.lyricsContentView];
    
    // 🆕 起点标记线容器（扩大触摸区域）
    CGFloat touchAreaHeight = 44;  // iOS 推荐的最小触摸区域
    self.startMarkerLine = [[UIView alloc] initWithFrame:CGRectMake(0, 50, self.lyricsScrollView.frame.size.width, touchAreaHeight)];
    self.startMarkerLine.backgroundColor = [UIColor clearColor];  // 容器透明
    self.startMarkerLine.hidden = YES;
    [self.lyricsScrollView addSubview:self.startMarkerLine];
    
    // 起点实际线条（2px，居中）
    UIView *startLine = [[UIView alloc] initWithFrame:CGRectMake(0, (touchAreaHeight - 2) / 2, self.lyricsScrollView.frame.size.width, 2)];
    startLine.backgroundColor = [UIColor colorWithRed:0.5 green:1.0 blue:0.5 alpha:0.9];
    startLine.userInteractionEnabled = NO;
    [self.startMarkerLine addSubview:startLine];
    
    // 起点拖动把手（圆形，更容易抓取）
    UIView *startHandle = [[UIView alloc] initWithFrame:CGRectMake(self.lyricsScrollView.frame.size.width - 50, (touchAreaHeight - 30) / 2, 30, 30)];
    startHandle.backgroundColor = [UIColor colorWithRed:0.5 green:1.0 blue:0.5 alpha:1.0];
    startHandle.layer.cornerRadius = 15;
    startHandle.layer.borderWidth = 2;
    startHandle.layer.borderColor = [UIColor whiteColor].CGColor;
    startHandle.userInteractionEnabled = NO;
    [self.startMarkerLine addSubview:startHandle];
    
    // 起点时间标签
    self.startMarkerLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, (touchAreaHeight - 24) / 2, 90, 24)];
    self.startMarkerLabel.text = @"起点 00:01";
    self.startMarkerLabel.textColor = [UIColor colorWithRed:0.5 green:1.0 blue:0.5 alpha:1.0];
    self.startMarkerLabel.font = [UIFont boldSystemFontOfSize:13];
    self.startMarkerLabel.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.95];
    self.startMarkerLabel.textAlignment = NSTextAlignmentCenter;
    self.startMarkerLabel.layer.cornerRadius = 4;
    self.startMarkerLabel.clipsToBounds = YES;
    self.startMarkerLabel.userInteractionEnabled = NO;
    [self.startMarkerLine addSubview:self.startMarkerLabel];
    
    // 添加拖动手势（起点）
    UIPanGestureRecognizer *startPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleStartMarkerPan:)];
    startPan.delegate = self;  // 🔧 设置代理处理手势冲突
    [self.startMarkerLine addGestureRecognizer:startPan];
    
    // 🆕 终点标记线容器（扩大触摸区域）
    self.endMarkerLine = [[UIView alloc] initWithFrame:CGRectMake(0, 200, self.lyricsScrollView.frame.size.width, touchAreaHeight)];
    self.endMarkerLine.backgroundColor = [UIColor clearColor];  // 容器透明
    self.endMarkerLine.hidden = YES;
    [self.lyricsScrollView addSubview:self.endMarkerLine];
    
    // 终点实际线条（2px，居中）
    UIView *endLine = [[UIView alloc] initWithFrame:CGRectMake(0, (touchAreaHeight - 2) / 2, self.lyricsScrollView.frame.size.width, 2)];
    endLine.backgroundColor = [UIColor colorWithRed:1.0 green:0.5 blue:0.5 alpha:0.9];
    endLine.userInteractionEnabled = NO;
    [self.endMarkerLine addSubview:endLine];
    
    // 终点拖动把手（圆形，更容易抓取）
    UIView *endHandle = [[UIView alloc] initWithFrame:CGRectMake(self.lyricsScrollView.frame.size.width - 50, (touchAreaHeight - 30) / 2, 30, 30)];
    endHandle.backgroundColor = [UIColor colorWithRed:1.0 green:0.5 blue:0.5 alpha:1.0];
    endHandle.layer.cornerRadius = 15;
    endHandle.layer.borderWidth = 2;
    endHandle.layer.borderColor = [UIColor whiteColor].CGColor;
    endHandle.userInteractionEnabled = NO;
    [self.endMarkerLine addSubview:endHandle];
    
    // 终点时间标签
    self.endMarkerLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, (touchAreaHeight - 24) / 2, 90, 24)];
    self.endMarkerLabel.text = @"终点 00:50";
    self.endMarkerLabel.textColor = [UIColor colorWithRed:1.0 green:0.5 blue:0.5 alpha:1.0];
    self.endMarkerLabel.font = [UIFont boldSystemFontOfSize:13];
    self.endMarkerLabel.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.95];
    self.endMarkerLabel.textAlignment = NSTextAlignmentCenter;
    self.endMarkerLabel.layer.cornerRadius = 4;
    self.endMarkerLabel.clipsToBounds = YES;
    self.endMarkerLabel.userInteractionEnabled = NO;
    [self.endMarkerLine addSubview:self.endMarkerLabel];
    
    // 添加拖动手势（终点）
    UIPanGestureRecognizer *endPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleEndMarkerPan:)];
    endPan.delegate = self;  // 🔧 设置代理处理手势冲突
    [self.endMarkerLine addGestureRecognizer:endPan];
    
    currentY += lyricsScrollHeight + 10;
    
    // 🆕 时长显示（片段模式时显示）
    self.durationLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, currentY, containerWidth - 40, 25)];
    self.durationLabel.text = @"片段时长: 0:49";
    self.durationLabel.textColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    self.durationLabel.font = [UIFont boldSystemFontOfSize:16];
    self.durationLabel.textAlignment = NSTextAlignmentCenter;
    self.durationLabel.hidden = YES;
    [self.containerView addSubview:self.durationLabel];
    currentY += 30;
    
    // 按钮区域
    CGFloat buttonWidth = (containerWidth - 60) / 2;
    CGFloat buttonHeight = 50;
    
    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    cancelButton.frame = CGRectMake(20, currentY, buttonWidth, buttonHeight);
    [cancelButton setTitle:@"取消" forState:UIControlStateNormal];
    [cancelButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    cancelButton.backgroundColor = [UIColor colorWithWhite:0.4 alpha:0.8];
    cancelButton.layer.cornerRadius = 12;
    cancelButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [cancelButton addTarget:self action:@selector(cancelButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.containerView addSubview:cancelButton];
    
    UIButton *confirmButton = [UIButton buttonWithType:UIButtonTypeSystem];
    confirmButton.frame = CGRectMake(30 + buttonWidth, currentY, buttonWidth, buttonHeight);
    [confirmButton setTitle:@"✅ 确定" forState:UIControlStateNormal];
    [confirmButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    confirmButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.4 alpha:1.0];
    confirmButton.layer.cornerRadius = 12;
    confirmButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [confirmButton addTarget:self action:@selector(confirmButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.containerView addSubview:confirmButton];
}

#pragma mark - 公共方法

- (void)show {
    // 初始化默认值
    if (self.totalDuration > 0) {
        // 设置初始值
        if (self.initialEndTime > 0) {
            self.currentStartTime = self.initialStartTime;
            self.currentEndTime = self.initialEndTime;
            self.modeControl.selectedSegmentIndex = 1;  // 片段模式
        } else {
            self.currentStartTime = 1.0;  // 默认从第1秒开始
            self.currentEndTime = MIN(50.0, self.totalDuration);  // 默认50秒
        }
    }
    
    // 🆕 生成歌词列表
    if (self.lyricsParser) {
        [self buildLyricsList];
    }
    
    // 动画显示
    self.alpha = 0;
    self.containerView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0 options:0 animations:^{
        self.alpha = 1;
        self.containerView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

// 🆕 生成歌词列表
- (void)buildLyricsList {
    // 清空旧的歌词
    for (UILabel *label in self.lyricLabels) {
        [label removeFromSuperview];
    }
    [self.lyricLabels removeAllObjects];
    
    NSArray<LRCLine *> *lyrics = self.lyricsParser.lyrics;
    if (lyrics.count == 0) {
        return;
    }
    
    CGFloat yOffset = 20;
    CGFloat lineHeight = 35;
    CGFloat containerWidth = self.lyricsContentView.frame.size.width;
    
    for (int i = 0; i < lyrics.count; i++) {
        LRCLine *lyric = lyrics[i];
        NSTimeInterval time = lyric.time;
        NSString *text = lyric.text;
        
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(15, yOffset, containerWidth - 30, lineHeight)];
        label.text = [NSString stringWithFormat:@"[%@] %@", [self formatTime:time], text];
        label.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
        label.font = [UIFont systemFontOfSize:14];
        label.numberOfLines = 0;
        label.tag = i;  // 存储歌词索引
        
        [self.lyricsContentView addSubview:label];
        [self.lyricLabels addObject:label];
        
        yOffset += lineHeight;
    }
    
    // 更新内容大小
    self.lyricsContentView.frame = CGRectMake(0, 0, containerWidth, yOffset + 20);
    self.lyricsScrollView.contentSize = CGSizeMake(containerWidth, yOffset + 20);
    
    NSLog(@"✅ 已生成 %lu 行歌词", (unsigned long)lyrics.count);
}

- (void)hide {
    [UIView animateWithDuration:0.25 animations:^{
        self.alpha = 0;
        self.containerView.transform = CGAffineTransformMakeScale(0.85, 0.85);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

#pragma mark - 事件处理

- (void)modeChanged:(UISegmentedControl *)sender {
    BOOL isSegmentMode = (sender.selectedSegmentIndex == 1);
    
    self.lyricsScrollView.hidden = !isSegmentMode;
    self.durationLabel.hidden = !isSegmentMode;
    
    if (isSegmentMode) {
        // 显示标记线
        self.startMarkerLine.hidden = NO;
        self.endMarkerLine.hidden = NO;
        
        // 初始化标记线位置
        [self updateMarkerPositions];
        [self updateDurationLabel];
    } else {
        // 隐藏标记线
        self.startMarkerLine.hidden = YES;
        self.endMarkerLine.hidden = YES;
    }
    
    NSLog(@"📍 模式切换: %@", isSegmentMode ? @"片段" : @"全曲");
}

// 🆕 拖动起点标记线
- (void)handleStartMarkerPan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.lyricsScrollView];
    CGPoint location = [gesture locationInView:self.lyricsScrollView];
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.isDraggingStartMarker = YES;
        // 🔧 禁用ScrollView滚动
        self.lyricsScrollView.scrollEnabled = NO;
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        // 计算新位置
        CGRect frame = self.startMarkerLine.frame;
        frame.origin.y += translation.y;
        
        // 限制范围（不能超过终点线，不能超出边界）
        CGFloat minY = 10;
        CGFloat maxY = self.endMarkerLine.frame.origin.y - 44;  // 考虑触摸区域高度
        frame.origin.y = MAX(minY, MIN(maxY, frame.origin.y));
        
        self.startMarkerLine.frame = frame;
        [gesture setTranslation:CGPointZero inView:self.lyricsScrollView];
        
        // 计算对应的时间
        [self updateTimeFromMarkerPosition];
        [self highlightLyricsBetweenMarkers];
    } else if (gesture.state == UIGestureRecognizerStateEnded ||
               gesture.state == UIGestureRecognizerStateCancelled) {
        self.isDraggingStartMarker = NO;
        // 🔧 恢复ScrollView滚动
        self.lyricsScrollView.scrollEnabled = YES;
        // 吸附到最近的歌词行
        [self snapMarkerToNearestLyric:self.startMarkerLine];
    }
}

// 🆕 拖动终点标记线
- (void)handleEndMarkerPan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.lyricsScrollView];
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.isDraggingEndMarker = YES;
        // 🔧 禁用ScrollView滚动
        self.lyricsScrollView.scrollEnabled = NO;
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        // 计算新位置
        CGRect frame = self.endMarkerLine.frame;
        frame.origin.y += translation.y;
        
        // 限制范围（不能低于起点线，不能超出边界）
        CGFloat minY = self.startMarkerLine.frame.origin.y + 44;  // 考虑触摸区域高度
        CGFloat maxY = self.lyricsContentView.frame.size.height - 44;
        frame.origin.y = MAX(minY, MIN(maxY, frame.origin.y));
        
        self.endMarkerLine.frame = frame;
        [gesture setTranslation:CGPointZero inView:self.lyricsScrollView];
        
        // 计算对应的时间
        [self updateTimeFromMarkerPosition];
        [self highlightLyricsBetweenMarkers];
    } else if (gesture.state == UIGestureRecognizerStateEnded ||
               gesture.state == UIGestureRecognizerStateCancelled) {
        self.isDraggingEndMarker = NO;
        // 🔧 恢复ScrollView滚动
        self.lyricsScrollView.scrollEnabled = YES;
        // 吸附到最近的歌词行
        [self snapMarkerToNearestLyric:self.endMarkerLine];
    }
}

// 🆕 根据标记线位置更新时间
- (void)updateTimeFromMarkerPosition {
    // 根据起点标记线的中心位置找最近的歌词
    CGFloat startCenterY = self.startMarkerLine.frame.origin.y + self.startMarkerLine.frame.size.height / 2;
    CGFloat endCenterY = self.endMarkerLine.frame.origin.y + self.endMarkerLine.frame.size.height / 2;
    
    NSTimeInterval startTime = [self findNearestLyricTime:startCenterY];
    NSTimeInterval endTime = [self findNearestLyricTime:endCenterY];
    
    // 确保最小间隔5秒
    if (endTime - startTime < 5.0) {
        return;
    }
    
    self.currentStartTime = startTime;
    self.currentEndTime = endTime;
    
    // 更新标签
    self.startMarkerLabel.text = [NSString stringWithFormat:@"起点 %@", [self formatTime:startTime]];
    self.endMarkerLabel.text = [NSString stringWithFormat:@"终点 %@", [self formatTime:endTime]];
    
    [self updateDurationLabel];
}

// 🆕 找到Y位置最近的歌词时间
- (NSTimeInterval)findNearestLyricTime:(CGFloat)yPosition {
    NSArray<LRCLine *> *lyrics = self.lyricsParser.lyrics;
    if (lyrics.count == 0) {
        return 0;
    }
    
    // 遍历所有歌词label，找最近的
    CGFloat minDistance = CGFLOAT_MAX;
    NSTimeInterval nearestTime = 0;
    
    for (UILabel *label in self.lyricLabels) {
        CGFloat distance = fabs(label.frame.origin.y - yPosition);
        if (distance < minDistance) {
            minDistance = distance;
            NSInteger index = label.tag;
            if (index < lyrics.count) {
                nearestTime = lyrics[index].time;
            }
        }
    }
    
    return nearestTime;
}

// 🆕 吸附标记线到最近的歌词行
- (void)snapMarkerToNearestLyric:(UIView *)markerLine {
    // 用中心点位置查找最近的歌词
    CGFloat centerY = markerLine.frame.origin.y + markerLine.frame.size.height / 2;
    
    // 找到最近的歌词label
    CGFloat minDistance = CGFLOAT_MAX;
    UILabel *nearestLabel = nil;
    
    for (UILabel *label in self.lyricLabels) {
        CGFloat labelCenterY = label.frame.origin.y + label.frame.size.height / 2;
        CGFloat distance = fabs(labelCenterY - centerY);
        if (distance < minDistance) {
            minDistance = distance;
            nearestLabel = label;
        }
    }
    
    if (nearestLabel) {
        // 动画吸附（让标记线的中心对齐歌词的中心）
        [UIView animateWithDuration:0.2 animations:^{
            CGRect frame = markerLine.frame;
            CGFloat targetCenterY = nearestLabel.frame.origin.y + nearestLabel.frame.size.height / 2;
            frame.origin.y = targetCenterY - markerLine.frame.size.height / 2;
            markerLine.frame = frame;
        } completion:^(BOOL finished) {
            [self updateTimeFromMarkerPosition];
        }];
    }
}

// 🆕 高亮标记线之间的歌词
- (void)highlightLyricsBetweenMarkers {
    // 使用标记线的中心位置
    CGFloat startCenterY = self.startMarkerLine.frame.origin.y + self.startMarkerLine.frame.size.height / 2;
    CGFloat endCenterY = self.endMarkerLine.frame.origin.y + self.endMarkerLine.frame.size.height / 2;
    
    for (UILabel *label in self.lyricLabels) {
        CGFloat labelCenterY = label.frame.origin.y + label.frame.size.height / 2;
        
        if (labelCenterY >= startCenterY && labelCenterY <= endCenterY) {
            // 在选中范围内，高亮
            label.textColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
            label.font = [UIFont boldSystemFontOfSize:14];
        } else {
            // 不在范围内，正常显示
            label.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
            label.font = [UIFont systemFontOfSize:14];
        }
    }
}

// 🆕 更新标记线位置（初始化时）
- (void)updateMarkerPositions {
    // 找到起点和终点对应的歌词行
    NSInteger startIndex = [self findLyricIndexForTime:self.currentStartTime];
    NSInteger endIndex = [self findLyricIndexForTime:self.currentEndTime];
    
    if (startIndex < self.lyricLabels.count) {
        UILabel *startLabel = self.lyricLabels[startIndex];
        CGRect frame = self.startMarkerLine.frame;
        // 让标记线的中心对齐歌词的中心
        CGFloat targetCenterY = startLabel.frame.origin.y + startLabel.frame.size.height / 2;
        frame.origin.y = targetCenterY - self.startMarkerLine.frame.size.height / 2;
        self.startMarkerLine.frame = frame;
    }
    
    if (endIndex < self.lyricLabels.count) {
        UILabel *endLabel = self.lyricLabels[endIndex];
        CGRect frame = self.endMarkerLine.frame;
        // 让标记线的中心对齐歌词的中心
        CGFloat targetCenterY = endLabel.frame.origin.y + endLabel.frame.size.height / 2;
        frame.origin.y = targetCenterY - self.endMarkerLine.frame.size.height / 2;
        self.endMarkerLine.frame = frame;
    }
    
    // 更新标签
    self.startMarkerLabel.text = [NSString stringWithFormat:@"起点 %@", [self formatTime:self.currentStartTime]];
    self.endMarkerLabel.text = [NSString stringWithFormat:@"终点 %@", [self formatTime:self.currentEndTime]];
    
    [self highlightLyricsBetweenMarkers];
}

// 🆕 找到时间对应的歌词索引
- (NSInteger)findLyricIndexForTime:(NSTimeInterval)time {
    NSArray<LRCLine *> *lyrics = self.lyricsParser.lyrics;
    for (NSInteger i = 0; i < lyrics.count; i++) {
        NSTimeInterval lyricTime = lyrics[i].time;
        if (lyricTime >= time) {
            return i;
        }
    }
    return lyrics.count - 1;
}

- (void)updateDurationLabel {
    NSTimeInterval duration = self.currentEndTime - self.currentStartTime;
    self.durationLabel.text = [NSString stringWithFormat:@"片段时长: %@", [self formatTime:duration]];
}

- (NSString *)formatTime:(NSTimeInterval)time {
    int minutes = (int)time / 60;
    int seconds = (int)time % 60;
    return [NSString stringWithFormat:@"%d:%02d", minutes, seconds];
}

- (void)backgroundTapped {
    [self cancelButtonTapped];
}

- (void)cancelButtonTapped {
    NSLog(@"❌ 取消选择片段");
    if (self.onCancel) {
        self.onCancel();
    }
    [self hide];
}

- (void)confirmButtonTapped {
    if (self.modeControl.selectedSegmentIndex == 0) {
        // 全曲模式
        NSLog(@"✅ 选择：全曲模式");
        if (self.onSelectFull) {
            self.onSelectFull();
        }
    } else {
        // 片段模式
        NSLog(@"✅ 选择片段: %.2fs ~ %.2fs", self.currentStartTime, self.currentEndTime);
        if (self.onConfirm) {
            self.onConfirm(self.currentStartTime, self.currentEndTime);
        }
    }
    [self hide];
}

#pragma mark - UIGestureRecognizerDelegate

// 🔧 关键：允许标记线的拖动手势和ScrollView的滚动手势同时存在
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // 如果是我们的拖动手势，允许与ScrollView的手势同时工作
    if ([gestureRecognizer.view isEqual:self.startMarkerLine] || 
        [gestureRecognizer.view isEqual:self.endMarkerLine]) {
        return NO;  // 不同时识别，优先标记线拖动
    }
    return YES;
}

// 🔧 关键：当开始拖动标记线时，禁用ScrollView滚动
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gestureRecognizer;
        CGPoint velocity = [pan velocityInView:self.lyricsScrollView];
        
        // 如果是标记线的拖动手势
        if ([gestureRecognizer.view isEqual:self.startMarkerLine] || 
            [gestureRecognizer.view isEqual:self.endMarkerLine]) {
            // 垂直方向的拖动才允许（区分ScrollView的滚动）
            return fabs(velocity.y) > fabs(velocity.x);
        }
    }
    return YES;
}

@end

