//
//  MusicDownloadManager.m
//  AudioSampleBuffer
//
//  音乐下载管理器 - 实现
//

#import "MusicDownloadManager.h"
#import "KugouMusicDownloader.h"
#import <objc/runtime.h>

@implementation MusicSearchResult
@end

@interface MusicDownloadManager () <NSURLSessionDownloadDelegate>

@property (nonatomic, strong) NSString *downloadDir;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, MusicDownloadProgressBlock> *progressBlocks;

@end

@implementation MusicDownloadManager

+ (instancetype)sharedManager {
    static MusicDownloadManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[MusicDownloadManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // 默认下载目录
        NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        _downloadDir = [documentsPath stringByAppendingPathComponent:@"Downloads"];
        
        // 创建目录
        [[NSFileManager defaultManager] createDirectoryAtPath:_downloadDir 
                                  withIntermediateDirectories:YES 
                                                   attributes:nil 
                                                        error:nil];
        
        // 配置 URLSession
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 30.0;
        _session = [NSURLSession sessionWithConfiguration:config 
                                                 delegate:self 
                                            delegateQueue:[NSOperationQueue mainQueue]];
        
        _progressBlocks = [NSMutableDictionary dictionary];
        
        NSLog(@"🎵 [下载管理器] 初始化完成，下载目录: %@", _downloadDir);
    }
    return self;
}

#pragma mark - Public API - 搜索

- (void)searchMusic:(NSString *)keyword
          platforms:(nullable NSArray<NSNumber *> *)platforms
         maxResults:(NSInteger)maxResults
         completion:(void(^)(NSArray<MusicSearchResult *> * _Nullable results, NSError * _Nullable error))completion {
    
    if (!keyword || keyword.length == 0) {
        NSError *error = [NSError errorWithDomain:@"MusicDownloadManager" 
                                             code:-1 
                                         userInfo:@{NSLocalizedDescriptionKey: @"搜索关键词不能为空"}];
        if (completion) completion(nil, error);
        return;
    }
    
    NSLog(@"🔍 [音乐搜索] 关键词: %@", keyword);
    
    // 如果未指定平台，搜索所有平台
    NSArray *targetPlatforms = platforms ?: @[
        @(MusicSourcePlatformQQMusic),
        @(MusicSourcePlatformNetease),
        @(MusicSourcePlatformKugou),
        @(MusicSourcePlatformBaidu)
    ];
    
    NSInteger limit = maxResults > 0 ? maxResults : 5;
    
    // 创建搜索任务组
    dispatch_group_t group = dispatch_group_create();
    NSMutableArray<MusicSearchResult *> *allResults = [NSMutableArray array];
    
    for (NSNumber *platformNumber in targetPlatforms) {
        dispatch_group_enter(group);
        
        MusicSourcePlatform platform = [platformNumber integerValue];
        
        [self searchOnPlatform:platform 
                       keyword:keyword 
                         limit:limit 
                    completion:^(NSArray<MusicSearchResult *> *results, NSError *error) {
            if (results) {
                @synchronized (allResults) {
                    [allResults addObjectsFromArray:results];
                }
            }
            dispatch_group_leave(group);
        }];
    }
    
    // 等待所有搜索完成
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        // 排序和去重
        NSArray *sortedResults = [self sortAndDeduplicateResults:allResults];
        
        NSLog(@"✅ [音乐搜索] 完成，共找到 %lu 个结果", (unsigned long)sortedResults.count);
        
        if (completion) {
            completion(sortedResults, nil);
        }
    });
}

- (void)searchOnPlatform:(MusicSourcePlatform)platform
                 keyword:(NSString *)keyword
                   limit:(NSInteger)limit
              completion:(void(^)(NSArray<MusicSearchResult *> * _Nullable results, NSError * _Nullable error))completion {
    
    switch (platform) {
        case MusicSourcePlatformQQMusic:
            [self searchQQMusic:keyword limit:limit completion:completion];
            break;
            
        case MusicSourcePlatformNetease:
            [self searchNeteaseMusic:keyword limit:limit completion:completion];
            break;
            
        case MusicSourcePlatformKugou:
            [self searchKugouMusic:keyword limit:limit completion:completion];
            break;
            
        case MusicSourcePlatformBaidu:
            [self searchBaiduMusic:keyword limit:limit completion:completion];
            break;
            
        default:
            if (completion) completion(nil, nil);
            break;
    }
}

#pragma mark - Platform Specific Search - QQ音乐

- (void)searchQQMusic:(NSString *)keyword
                limit:(NSInteger)limit
           completion:(void(^)(NSArray<MusicSearchResult *> * _Nullable results, NSError * _Nullable error))completion {
    
    NSString *encodedKeyword = [keyword stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    // QQ音乐搜索API
    NSString *urlString = [NSString stringWithFormat:
        @"https://c.y.qq.com/soso/fcgi-bin/client_search_cp?p=1&n=%ld&w=%@&format=json",
        (long)limit, encodedKeyword];
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"https://y.qq.com/" forHTTPHeaderField:@"Referer"];
    [request setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" forHTTPHeaderField:@"User-Agent"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request 
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            
            if (error) {
                NSLog(@"❌ [QQ音乐] 搜索失败: %@", error.localizedDescription);
                if (completion) completion(nil, error);
                return;
            }
            
            NSArray<MusicSearchResult *> *results = [self parseQQMusicSearchResults:data];
            
            NSLog(@"✅ [QQ音乐] 搜索到 %lu 首歌曲", (unsigned long)results.count);
            
            if (completion) completion(results, nil);
        }];
    [task resume];
}

- (NSArray<MusicSearchResult *> *)parseQQMusicSearchResults:(NSData *)data {
    NSMutableArray<MusicSearchResult *> *results = [NSMutableArray array];
    
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *songs = json[@"data"][@"song"][@"list"];
    
    if (!songs) return results;
    
    for (NSDictionary *song in songs) {
        MusicSearchResult *result = [[MusicSearchResult alloc] init];
        
        result.songId = song[@"songmid"] ?: song[@"songid"];
        result.songName = song[@"songname"];
        
        // 解析艺术家
        NSArray *singers = song[@"singer"];
        if (singers.count > 0) {
            NSMutableArray *artistNames = [NSMutableArray array];
            for (NSDictionary *singer in singers) {
                [artistNames addObject:singer[@"name"]];
            }
            result.artistName = [artistNames componentsJoinedByString:@"/"];
        }
        
        result.albumName = song[@"albumname"];
        result.duration = [song[@"interval"] integerValue];
        result.fileSize = [song[@"size320"] integerValue]; // 320K文件大小
        result.quality = MusicQuality320K;
        result.platform = MusicSourcePlatformQQMusic;
        
        // 封面URL
        NSString *albumMid = song[@"albummid"];
        if (albumMid) {
            result.coverUrl = [NSString stringWithFormat:
                @"https://y.gtimg.cn/music/photo_new/T002R300x300M000%@.jpg", albumMid];
        }
        
        [results addObject:result];
    }
    
    return results;
}

#pragma mark - Platform Specific Search - 网易云音乐

- (void)searchNeteaseMusic:(NSString *)keyword
                     limit:(NSInteger)limit
                completion:(void(^)(NSArray<MusicSearchResult *> * _Nullable results, NSError * _Nullable error))completion {
    
    // 网易云音乐API需要加密参数，这里提供基本框架
    // 完整实现需要参考: https://github.com/Binaryify/NeteaseCloudMusicApi
    
    NSLog(@"⚠️ [网易云] 搜索功能待实现（需要加密参数）");
    
    // 暂时返回空结果
    if (completion) completion(@[], nil);
}

#pragma mark - Platform Specific Search - 酷狗音乐

- (void)searchKugouMusic:(NSString *)keyword
                   limit:(NSInteger)limit
              completion:(void(^)(NSArray<MusicSearchResult *> * _Nullable results, NSError * _Nullable error))completion {
    
    NSString *encodedKeyword = [keyword stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    // 酷狗搜索API
    NSString *urlString = [NSString stringWithFormat:
        @"http://mobilecdn.kugou.com/api/v3/search/song?format=json&keyword=%@&page=1&pagesize=%ld",
        encodedKeyword, (long)limit];
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request 
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            
            if (error) {
                NSLog(@"❌ [酷狗音乐] 搜索失败: %@", error.localizedDescription);
                if (completion) completion(nil, error);
                return;
            }
            
            NSArray<MusicSearchResult *> *results = [self parseKugouSearchResults:data];
            
            NSLog(@"✅ [酷狗音乐] 搜索到 %lu 首歌曲", (unsigned long)results.count);
            
            if (completion) completion(results, nil);
        }];
    [task resume];
}

- (NSArray<MusicSearchResult *> *)parseKugouSearchResults:(NSData *)data {
    NSMutableArray<MusicSearchResult *> *results = [NSMutableArray array];
    
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *songs = json[@"data"][@"info"];
    
    if (!songs) return results;
    
    for (NSDictionary *song in songs) {
        MusicSearchResult *result = [[MusicSearchResult alloc] init];
        
        result.songId = song[@"hash"];
        result.songName = song[@"songname"];
        result.artistName = song[@"singername"];
        result.albumName = song[@"album_name"];
        result.duration = [song[@"duration"] integerValue];
        result.fileSize = [song[@"filesize"] integerValue];
        result.quality = MusicQuality320K;
        result.platform = MusicSourcePlatformKugou;
        
        [results addObject:result];
    }
    
    return results;
}

#pragma mark - Platform Specific Search - 百度音乐

- (void)searchBaiduMusic:(NSString *)keyword
                   limit:(NSInteger)limit
              completion:(void(^)(NSArray<MusicSearchResult *> * _Nullable results, NSError * _Nullable error))completion {
    
    NSLog(@"⚠️ [百度音乐] 搜索功能待实现");
    
    // 暂时返回空结果
    if (completion) completion(@[], nil);
}

#pragma mark - Download

- (void)downloadMusic:(MusicSearchResult *)searchResult
              quality:(MusicQuality)quality
      downloadLyrics:(BOOL)downloadLyrics
       downloadCover:(BOOL)downloadCover
             progress:(nullable MusicDownloadProgressBlock)progressBlock
           completion:(void(^)(NSString * _Nullable filePath, NSError * _Nullable error))completion {
    
    NSLog(@"⬇️ [下载] %@ - %@ (平台: %ld)", 
          searchResult.artistName, 
          searchResult.songName, 
          (long)searchResult.platform);
    
    // 1. 获取真实下载链接
    [self getDownloadURL:searchResult 
                 quality:quality 
              completion:^(NSString *downloadUrl, NSError *error) {
        
        if (error || !downloadUrl) {
            NSLog(@"❌ [下载] 获取下载链接失败: %@", error.localizedDescription);
            if (completion) completion(nil, error);
            return;
        }
        
        // 2. 开始下载
        [self downloadFileFromURL:downloadUrl 
                         fileName:[self generateFileName:searchResult] 
                         progress:progressBlock 
                       completion:^(NSString *filePath, NSError *downloadError) {
            
            if (downloadError) {
                if (completion) completion(nil, downloadError);
                return;
            }
            
            // 3. 下载歌词和封面（可选）
            if (downloadLyrics) {
                [self downloadLyricsForResult:searchResult completion:nil];
            }
            
            if (downloadCover) {
                [self downloadCoverForResult:searchResult completion:nil];
            }
            
            if (completion) completion(filePath, nil);
        }];
    }];
}

- (void)searchAndDownloadMusic:(NSString *)keyword
                        quality:(MusicQuality)quality
                       progress:(nullable MusicDownloadProgressBlock)progressBlock
                     completion:(void(^)(NSString * _Nullable filePath, NSError * _Nullable error))completion {
    
    // 1. 先搜索（只搜索酷狗，因为其他平台暂不支持下载）
    [self searchMusic:keyword 
            platforms:@[@(MusicSourcePlatformKugou)]  // 只搜索酷狗
           maxResults:5 
           completion:^(NSArray<MusicSearchResult *> *results, NSError *error) {
        
        if (error || results.count == 0) {
            NSError *notFoundError = [NSError errorWithDomain:@"MusicDownloadManager" 
                                                         code:-404 
                                                     userInfo:@{NSLocalizedDescriptionKey: @"未找到匹配的音乐"}];
            if (completion) completion(nil, notFoundError);
            return;
        }
        
        // 2. 下载第一个结果
        MusicSearchResult *firstResult = results.firstObject;
        
        [self downloadMusic:firstResult 
                    quality:quality 
            downloadLyrics:YES 
             downloadCover:YES 
                   progress:progressBlock 
                 completion:completion];
    }];
}

#pragma mark - Helper Methods

- (void)getDownloadURL:(MusicSearchResult *)result
               quality:(MusicQuality)quality
            completion:(void(^)(NSString * _Nullable url, NSError * _Nullable error))completion {
    
    // 根据平台获取真实下载链接
    // 注意：音乐平台的下载链接API经常变化，需要持续维护
    
    switch (result.platform) {
        case MusicSourcePlatformQQMusic:
            [self getQQMusicDownloadURL:result quality:quality completion:completion];
            break;
            
        case MusicSourcePlatformKugou:
            [self getKugouDownloadURL:result quality:quality completion:completion];
            break;
            
        default:
            {
                NSError *error = [NSError errorWithDomain:@"MusicDownloadManager" 
                                                     code:-2 
                                                 userInfo:@{NSLocalizedDescriptionKey: @"暂不支持该平台下载"}];
                if (completion) completion(nil, error);
            }
            break;
    }
}

- (void)getQQMusicDownloadURL:(MusicSearchResult *)result
                      quality:(MusicQuality)quality
                   completion:(void(^)(NSString * _Nullable url, NSError * _Nullable error))completion {
    
    // QQ音乐的下载链接获取较复杂，需要 vkey
    // 这里提供简化版本，实际使用需要完善
    
    NSLog(@"⚠️ [QQ音乐] 下载链接获取需要 vkey 验证，暂未完全实现");
    
    NSError *error = [NSError errorWithDomain:@"MusicDownloadManager" 
                                         code:-3 
                                     userInfo:@{NSLocalizedDescriptionKey: @"QQ音乐下载需要进一步开发"}];
    if (completion) completion(nil, error);
}

- (void)getKugouDownloadURL:(MusicSearchResult *)result
                    quality:(MusicQuality)quality
                 completion:(void(^)(NSString * _Nullable url, NSError * _Nullable error))completion {
    
    // 使用新的酷狗音乐下载器（多种方式尝试）
    [KugouMusicDownloader getDownloadURL:result.songId completion:completion];
}

- (void)downloadFileFromURL:(NSString *)urlString
                   fileName:(NSString *)fileName
                   progress:(nullable MusicDownloadProgressBlock)progressBlock
                 completion:(void(^)(NSString * _Nullable filePath, NSError * _Nullable error))completion {
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLSessionDownloadTask *task = [self.session downloadTaskWithURL:url];
    
    // 保存进度回调
    if (progressBlock) {
        self.progressBlocks[@(task.taskIdentifier)] = progressBlock;
    }
    
    // 暂存完成回调（简化处理，实际应该用更好的方式）
    objc_setAssociatedObject(task, "completion", completion, OBJC_ASSOCIATION_COPY);
    objc_setAssociatedObject(task, "fileName", fileName, OBJC_ASSOCIATION_COPY);
    
    [task resume];
}

- (void)downloadLyricsForResult:(MusicSearchResult *)result
                     completion:(nullable void(^)(NSString * _Nullable lyricsPath))completion {
    // 根据平台下载歌词
    NSLog(@"📝 [歌词] 下载歌词: %@", result.songName);
    
    // TODO: 实现歌词下载
    if (completion) completion(nil);
}

- (void)downloadCoverForResult:(MusicSearchResult *)result
                    completion:(nullable void(^)(NSString * _Nullable coverPath))completion {
    
    if (!result.coverUrl) {
        if (completion) completion(nil);
        return;
    }
    
    NSLog(@"🖼️ [封面] 下载封面: %@", result.songName);
    
    // TODO: 实现封面下载
    if (completion) completion(nil);
}

- (NSString *)generateFileName:(MusicSearchResult *)result {
    // 生成文件名：艺术家 - 歌曲名.mp3
    NSString *cleanArtist = [[result.artistName componentsSeparatedByCharactersInSet:
                              [NSCharacterSet characterSetWithCharactersInString:@"/:*?\"<>|"]] componentsJoinedByString:@"_"];
    NSString *cleanSong = [[result.songName componentsSeparatedByCharactersInSet:
                            [NSCharacterSet characterSetWithCharactersInString:@"/:*?\"<>|"]] componentsJoinedByString:@"_"];
    
    return [NSString stringWithFormat:@"%@ - %@.mp3", cleanArtist, cleanSong];
}

- (NSArray<MusicSearchResult *> *)sortAndDeduplicateResults:(NSArray<MusicSearchResult *> *)results {
    // 按照歌手和歌名排序，去重保留文件最大的
    
    NSSortDescriptor *artistSort = [NSSortDescriptor sortDescriptorWithKey:@"artistName" ascending:YES];
    NSSortDescriptor *songSort = [NSSortDescriptor sortDescriptorWithKey:@"songName" ascending:YES];
    NSSortDescriptor *sizeSort = [NSSortDescriptor sortDescriptorWithKey:@"fileSize" ascending:NO];
    
    return [results sortedArrayUsingDescriptors:@[artistSort, songSort, sizeSort]];
}

#pragma mark - Configuration

- (void)setDownloadDirectory:(NSString *)path {
    _downloadDir = path;
    [[NSFileManager defaultManager] createDirectoryAtPath:_downloadDir 
                              withIntermediateDirectories:YES 
                                               attributes:nil 
                                                    error:nil];
}

- (NSString *)downloadDirectory {
    return _downloadDir;
}

- (void)cancelAllDownloads {
    [self.session invalidateAndCancel];
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session 
      downloadTask:(NSURLSessionDownloadTask *)downloadTask 
didFinishDownloadingToURL:(NSURL *)location {
    
    NSString *fileName = objc_getAssociatedObject(downloadTask, "fileName");
    NSString *destPath = [self.downloadDir stringByAppendingPathComponent:fileName];
    
    NSError *error = nil;
    [[NSFileManager defaultManager] moveItemAtURL:location 
                                            toURL:[NSURL fileURLWithPath:destPath] 
                                            error:&error];
    
    void(^completion)(NSString *, NSError *) = objc_getAssociatedObject(downloadTask, "completion");
    
    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(error ? nil : destPath, error);
        });
    }
    
    [self.progressBlocks removeObjectForKey:@(downloadTask.taskIdentifier)];
}

- (void)URLSession:(NSURLSession *)session 
      downloadTask:(NSURLSessionDownloadTask *)downloadTask 
      didWriteData:(int64_t)bytesWritten 
 totalBytesWritten:(int64_t)totalBytesWritten 
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    
    float progress = (float)totalBytesWritten / (float)totalBytesExpectedToWrite;
    
    MusicDownloadProgressBlock progressBlock = self.progressBlocks[@(downloadTask.taskIdentifier)];
    if (progressBlock) {
        dispatch_async(dispatch_get_main_queue(), ^{
            progressBlock(progress, [NSString stringWithFormat:@"下载中: %.0f%%", progress * 100]);
        });
    }
}

@end
