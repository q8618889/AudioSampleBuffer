//
//  RecordingListViewController.m
//  AudioSampleBuffer
//
//  Created on 2025/10/14.
//

#import "RecordingListViewController.h"
#import "RecordingPlaybackView.h"

@interface RecordingListViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *recordings;
@property (nonatomic, strong) RecordingPlaybackView *playbackView;

@end

@implementation RecordingListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"录音列表";
    self.view.backgroundColor = [UIColor blackColor];
    
    // 添加刷新按钮
    UIBarButtonItem *refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh 
                                                                                   target:self 
                                                                                   action:@selector(loadRecordings)];
    self.navigationItem.rightBarButtonItem = refreshButton;
    
    // 创建TableView
    [self setupTableView];
    
    // 加载录音列表
    [self loadRecordings];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"RecordingCell"];
    [self.view addSubview:self.tableView];
}

- (void)loadRecordings {
    NSLog(@"🔍 开始扫描录音文件...");
    
    // 获取Documents目录
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    NSArray *files = [fileManager contentsOfDirectoryAtPath:documentsDirectory error:&error];
    
    if (error) {
        NSLog(@"❌ 读取目录失败: %@", error.localizedDescription);
        return;
    }
    
    // 筛选.pcm文件
    self.recordings = [NSMutableArray array];
    for (NSString *file in files) {
        if ([file.pathExtension.lowercaseString isEqualToString:@"pcm"]) {
            NSString *filePath = [documentsDirectory stringByAppendingPathComponent:file];
            
            // 获取文件属性
            NSDictionary *attributes = [fileManager attributesOfItemAtPath:filePath error:nil];
            NSDate *creationDate = attributes[NSFileCreationDate];
            unsigned long long fileSize = [attributes fileSize];
            
            NSDictionary *recordingInfo = @{
                @"name": file,
                @"path": filePath,
                @"date": creationDate ?: [NSDate date],
                @"size": @(fileSize)
            };
            
            [self.recordings addObject:recordingInfo];
        }
    }
    
    // 按日期排序（最新的在前）
    [self.recordings sortUsingComparator:^NSComparisonResult(NSDictionary *obj1, NSDictionary *obj2) {
        NSDate *date1 = obj1[@"date"];
        NSDate *date2 = obj2[@"date"];
        return [date2 compare:date1];
    }];
    
    NSLog(@"✅ 找到 %lu 个录音文件", (unsigned long)self.recordings.count);
    
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.recordings.count == 0) {
        // 显示空状态提示
        UILabel *emptyLabel = [[UILabel alloc] initWithFrame:self.view.bounds];
        emptyLabel.text = @"暂无录音\n开始录制你的第一首歌吧！🎤";
        emptyLabel.textColor = [UIColor grayColor];
        emptyLabel.textAlignment = NSTextAlignmentCenter;
        emptyLabel.numberOfLines = 2;
        emptyLabel.font = [UIFont systemFontOfSize:18];
        self.tableView.backgroundView = emptyLabel;
    } else {
        self.tableView.backgroundView = nil;
    }
    
    return self.recordings.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RecordingCell" forIndexPath:indexPath];
    
    NSDictionary *recording = self.recordings[indexPath.row];
    
    // 配置cell
    cell.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.textLabel.numberOfLines = 2;
    
    // 格式化信息
    NSString *fileName = recording[@"name"];
    NSDate *date = recording[@"date"];
    unsigned long long size = [recording[@"size"] unsignedLongLongValue];
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *dateString = [formatter stringFromDate:date];
    
    NSString *sizeString = [self formatFileSize:size];
    
    cell.textLabel.text = [NSString stringWithFormat:@"🎵 %@\n📅 %@ | 💾 %@", fileName, dateString, sizeString];
    cell.textLabel.font = [UIFont systemFontOfSize:14];
    
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSDictionary *recording = self.recordings[indexPath.row];
    NSString *filePath = recording[@"path"];
    
    [self showPlaybackViewForFile:filePath];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 70;
}

// 支持左滑删除
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSDictionary *recording = self.recordings[indexPath.row];
        NSString *filePath = recording[@"path"];
        
        // 删除文件
        NSError *error;
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
        
        if (error) {
            [self showAlertWithTitle:@"删除失败" message:error.localizedDescription];
        } else {
            // 从数组中移除
            [self.recordings removeObjectAtIndex:indexPath.row];
            // 从TableView中删除
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
            
            NSLog(@"🗑️ 已删除: %@", recording[@"name"]);
        }
    }
}

#pragma mark - 显示回放视图

- (void)showPlaybackViewForFile:(NSString *)filePath {
    // 移除旧的回放视图
    if (self.playbackView) {
        [self.playbackView removeFromSuperview];
        self.playbackView = nil;
    }
    
    // 创建回放视图
    CGFloat viewHeight = 300;
    CGFloat viewY = (self.view.bounds.size.height - viewHeight) / 2;
    
    self.playbackView = [[RecordingPlaybackView alloc] initWithFrame:CGRectMake(20, viewY, self.view.bounds.size.width - 40, viewHeight)];
    self.playbackView.filePath = filePath;
    
    // 设置关闭回调
    __weak typeof(self) weakSelf = self;
    self.playbackView.onClose = ^{
        [weakSelf.playbackView removeFromSuperview];
        weakSelf.playbackView = nil;
    };
    
    self.playbackView.onDelete = ^(NSString *path) {
        [weakSelf loadRecordings]; // 刷新列表
        [weakSelf.playbackView removeFromSuperview];
        weakSelf.playbackView = nil;
    };
    
    [self.view addSubview:self.playbackView];
}

#pragma mark - Helper Methods

- (NSString *)formatFileSize:(unsigned long long)size {
    if (size < 1024) {
        return [NSString stringWithFormat:@"%llu B", size];
    } else if (size < 1024 * 1024) {
        return [NSString stringWithFormat:@"%.2f KB", size / 1024.0];
    } else {
        return [NSString stringWithFormat:@"%.2f MB", size / (1024.0 * 1024.0)];
    }
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title 
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

