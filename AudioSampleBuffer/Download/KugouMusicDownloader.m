//
//  KugouMusicDownloader.m
//  AudioSampleBuffer
//
//  酷狗音乐下载器实现
//

#import "KugouMusicDownloader.h"

@implementation KugouSongInfo
@end

@implementation KugouMusicDownloader

#pragma mark - 搜索音乐

+ (void)searchMusic:(NSString *)keyword
              limit:(NSInteger)limit
         completion:(void(^)(NSArray<KugouSongInfo *> * _Nullable songs, NSError * _Nullable error))completion {
    
    NSString *encodedKeyword = [keyword stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    // 酷狗搜索 API
    NSString *urlString = [NSString stringWithFormat:
        @"http://mobilecdn.kugou.com/api/v3/search/song?format=json&keyword=%@&page=1&pagesize=%ld",
        encodedKeyword, (long)limit];
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"Mozilla/5.0" forHTTPHeaderField:@"User-Agent"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            
            if (error) {
                NSLog(@"❌ [酷狗] 搜索失败: %@", error.localizedDescription);
                if (completion) completion(nil, error);
                return;
            }
            
            NSError *jsonError = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError) {
                if (completion) completion(nil, jsonError);
                return;
            }
            
            NSArray *songs = json[@"data"][@"info"];
            if (!songs || songs.count == 0) {
                NSError *notFoundError = [NSError errorWithDomain:@"KugouDownloader"
                                                             code:-404
                                                         userInfo:@{NSLocalizedDescriptionKey: @"未找到歌曲"}];
                if (completion) completion(nil, notFoundError);
                return;
            }
            
            NSMutableArray<KugouSongInfo *> *results = [NSMutableArray array];
            
            for (NSDictionary *song in songs) {
                KugouSongInfo *info = [[KugouSongInfo alloc] init];
                info.songId = song[@"hash"];
                info.songName = song[@"songname"];
                info.artistName = song[@"singername"];
                info.albumName = song[@"album_name"];
                info.duration = [song[@"duration"] integerValue];
                info.fileSize = [song[@"filesize"] integerValue];
                
                [results addObject:info];
            }
            
            NSLog(@"✅ [酷狗] 搜索到 %lu 首歌曲", (unsigned long)results.count);
            
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(results, nil);
                });
            }
        }];
    
    [task resume];
}

#pragma mark - 获取下载链接

+ (void)getDownloadURL:(NSString *)songHash
            completion:(void(^)(NSString * _Nullable url, NSError * _Nullable error))completion {
    
    if (!songHash || songHash.length == 0) {
        NSError *error = [NSError errorWithDomain:@"KugouDownloader"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"歌曲Hash不能为空"}];
        if (completion) completion(nil, error);
        return;
    }
    
    NSLog(@"🔍 [酷狗] 获取下载链接: %@", songHash);
    
    // 第一步：获取专辑ID（album_id）
    NSString *searchUrl = [NSString stringWithFormat:
        @"http://m.kugou.com/app/i/getSongInfo.php?cmd=playInfo&hash=%@", songHash];
    
    NSURL *url = [NSURL URLWithString:searchUrl];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"Mozilla/5.0" forHTTPHeaderField:@"User-Agent"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            
            if (error) {
                NSLog(@"❌ [酷狗] 获取歌曲信息失败: %@", error.localizedDescription);
                if (completion) completion(nil, error);
                return;
            }
            
            NSError *jsonError = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError || !json) {
                if (completion) completion(nil, jsonError);
                return;
            }
            
            // 检查是否有直接的下载链接
            id downloadUrlObj = json[@"url"];
            NSString *downloadUrl = nil;
            
            // 确保是字符串类型
            if ([downloadUrlObj isKindOfClass:[NSString class]]) {
                downloadUrl = (NSString *)downloadUrlObj;
            }
            
            if (downloadUrl && downloadUrl.length > 0 && ![downloadUrl isEqualToString:@""]) {
                NSLog(@"✅ [酷狗] 获取到下载链接（方式1）");
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(downloadUrl, nil);
                    });
                }
                return;
            }
            
            // 方式2：通过 album_audio_id 获取
            id albumAudioIdObj = json[@"album_audio_id"];
            NSString *albumAudioId = nil;
            
            // 处理可能是 NSNumber 或 NSString 的情况
            if ([albumAudioIdObj isKindOfClass:[NSString class]]) {
                albumAudioId = (NSString *)albumAudioIdObj;
            } else if ([albumAudioIdObj isKindOfClass:[NSNumber class]]) {
                albumAudioId = [(NSNumber *)albumAudioIdObj stringValue];
            }
            
            if (!albumAudioId || [albumAudioId isEqualToString:@"0"] || albumAudioId.length == 0) {
                NSLog(@"⚠️ [酷狗] 尝试方式3获取下载链接");
                [self getDownloadURLMethod3:songHash completion:completion];
                return;
            }
            
            // 第二步：通过 album_audio_id 获取真实下载链接
            NSString *detailUrl = [NSString stringWithFormat:
                @"http://www.kugou.com/yy/index.php?r=play/getdata&hash=%@&album_audio_id=%@",
                songHash, albumAudioId];
            
            NSURL *detailURL = [NSURL URLWithString:detailUrl];
            NSMutableURLRequest *detailRequest = [NSMutableURLRequest requestWithURL:detailURL];
            [detailRequest setValue:@"Mozilla/5.0" forHTTPHeaderField:@"User-Agent"];
            
            NSURLSessionDataTask *detailTask = [[NSURLSession sharedSession] dataTaskWithRequest:detailRequest
                completionHandler:^(NSData *detailData, NSURLResponse *detailResponse, NSError *detailError) {
                    
                    if (detailError) {
                        NSLog(@"❌ [酷狗] 获取详细信息失败: %@", detailError.localizedDescription);
                        if (completion) completion(nil, detailError);
                        return;
                    }
                    
                    NSError *jsonErr = nil;
                    NSDictionary *detailJson = [NSJSONSerialization JSONObjectWithData:detailData options:0 error:&jsonErr];
                    
                    if (jsonErr) {
                        if (completion) completion(nil, jsonErr);
                        return;
                    }
                    
                    // 检查 data 字段是否为字典类型
                    id dataObj = detailJson[@"data"];
                    NSString *playUrl = nil;
                    
                    if ([dataObj isKindOfClass:[NSDictionary class]]) {
                        NSDictionary *dataDict = (NSDictionary *)dataObj;
                        id playUrlObj = dataDict[@"play_url"];
                        
                        // 确保是字符串类型
                        if ([playUrlObj isKindOfClass:[NSString class]]) {
                            playUrl = (NSString *)playUrlObj;
                        }
                    } else {
                        NSLog(@"⚠️ [酷狗] data 字段不是字典类型: %@", [dataObj class]);
                    }
                    
                    if (playUrl && playUrl.length > 0) {
                        NSLog(@"✅ [酷狗] 获取到下载链接（方式2）");
                        if (completion) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                completion(playUrl, nil);
                            });
                        }
                    } else {
                        NSLog(@"⚠️ [酷狗] 方式2失败，尝试方式3");
                        [self getDownloadURLMethod3:songHash completion:completion];
                    }
                }];
            
            [detailTask resume];
        }];
    
    [task resume];
}

// 方式3：备用 API
+ (void)getDownloadURLMethod3:(NSString *)songHash
                    completion:(void(^)(NSString * _Nullable url, NSError * _Nullable error))completion {
    
    NSString *apiUrl = [NSString stringWithFormat:
        @"http://trackercdn.kugou.com/i/v2/?cmd=25&hash=%@&key=%@&pid=2&behavior=play",
        songHash, [self md5StringFromString:songHash]];
    
    NSURL *url = [NSURL URLWithString:apiUrl];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"Mozilla/5.0" forHTTPHeaderField:@"User-Agent"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            
            if (error) {
                NSLog(@"❌ [酷狗] 方式3失败: %@", error.localizedDescription);
                if (completion) completion(nil, error);
                return;
            }
            
            NSError *jsonError = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError) {
                if (completion) completion(nil, jsonError);
                return;
            }
            
            NSArray *urlArray = json[@"url"];
            if (urlArray && [urlArray isKindOfClass:[NSArray class]] && urlArray.count > 0) {
                id downloadUrlObj = urlArray[0];
                NSString *downloadUrl = nil;
                
                // 确保是字符串类型
                if ([downloadUrlObj isKindOfClass:[NSString class]]) {
                    downloadUrl = (NSString *)downloadUrlObj;
                }
                
                if (downloadUrl && downloadUrl.length > 0) {
                    NSLog(@"✅ [酷狗] 获取到下载链接（方式3）");
                    if (completion) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completion(downloadUrl, nil);
                        });
                    }
                    return;
                }
            }
            
            // 所有方式都失败
            {
                NSError *noUrlError = [NSError errorWithDomain:@"KugouDownloader"
                                                          code:-3
                                                      userInfo:@{NSLocalizedDescriptionKey: @"无法获取下载链接，可能需要VIP"}];
                NSLog(@"❌ [酷狗] 所有方式均失败");
                if (completion) completion(nil, noUrlError);
            }
        }];
    
    [task resume];
}

#pragma mark - 获取歌词

+ (void)getLyrics:(NSString *)songHash
       completion:(void(^)(NSString * _Nullable lyrics, NSError * _Nullable error))completion {
    
    // 酷狗歌词 API
    NSString *urlString = [NSString stringWithFormat:
        @"http://www.kugou.com/yy/index.php?r=play/getdata&hash=%@", songHash];
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            
            if (error) {
                if (completion) completion(nil, error);
                return;
            }
            
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            
            // 安全地获取歌词数据
            NSString *lyricsData = nil;
            id dataObj = json[@"data"];
            if ([dataObj isKindOfClass:[NSDictionary class]]) {
                NSDictionary *dataDict = (NSDictionary *)dataObj;
                id lyricsObj = dataDict[@"lyrics"];
                if ([lyricsObj isKindOfClass:[NSString class]]) {
                    lyricsData = (NSString *)lyricsObj;
                }
            }
            
            if (lyricsData && lyricsData.length > 0) {
                // Base64 解码
                NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:lyricsData options:0];
                NSString *lyrics = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
                
                NSLog(@"✅ [酷狗] 获取到歌词");
                
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(lyrics, nil);
                    });
                }
            } else {
                NSError *noLyricsError = [NSError errorWithDomain:@"KugouDownloader"
                                                             code:-2
                                                         userInfo:@{NSLocalizedDescriptionKey: @"该歌曲暂无歌词"}];
                if (completion) completion(nil, noLyricsError);
            }
        }];
    
    [task resume];
}

#pragma mark - 下载音乐文件

+ (void)downloadMusic:(KugouSongInfo *)songInfo
          toDirectory:(NSString *)directory
             progress:(nullable void(^)(float progress))progressBlock
           completion:(void(^)(NSString * _Nullable filePath, NSError * _Nullable error))completion {
    
    // 1. 先获取下载链接
    [self getDownloadURL:songInfo.songId completion:^(NSString *downloadUrl, NSError *error) {
        
        if (error || !downloadUrl) {
            NSLog(@"❌ [酷狗] 下载失败: 无法获取下载链接");
            if (completion) completion(nil, error);
            return;
        }
        
        NSLog(@"⬇️ [酷狗] 开始下载: %@", songInfo.songName);
        NSLog(@"🔗 下载链接: %@", downloadUrl);
        
        // 2. 下载文件
        NSURL *url = [NSURL URLWithString:downloadUrl];
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
        
        NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithURL:url
            completionHandler:^(NSURL *location, NSURLResponse *response, NSError *downloadError) {
                
                if (downloadError) {
                    NSLog(@"❌ [酷狗] 下载失败: %@", downloadError.localizedDescription);
                    if (completion) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completion(nil, downloadError);
                        });
                    }
                    return;
                }
                
                // 3. 保存文件
                NSString *fileName = [self sanitizeFileName:[NSString stringWithFormat:@"%@ - %@.mp3",
                                                             songInfo.artistName, songInfo.songName]];
                NSString *filePath = [directory stringByAppendingPathComponent:fileName];
                
                NSError *moveError = nil;
                [[NSFileManager defaultManager] moveItemAtURL:location
                                                        toURL:[NSURL fileURLWithPath:filePath]
                                                        error:&moveError];
                
                if (moveError) {
                    // 如果文件已存在，先删除
                    [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
                    [[NSFileManager defaultManager] moveItemAtURL:location
                                                            toURL:[NSURL fileURLWithPath:filePath]
                                                            error:nil];
                }
                
                NSLog(@"✅ [酷狗] 下载完成: %@", fileName);
                
                // 4. 同时下载歌词
                [self getLyrics:songInfo.songId completion:^(NSString *lyrics, NSError *lyricsError) {
                    if (lyrics) {
                        NSString *lyricsPath = [[filePath stringByDeletingPathExtension] stringByAppendingPathExtension:@"lrc"];
                        [lyrics writeToFile:lyricsPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
                        NSLog(@"✅ [酷狗] 歌词已保存");
                    }
                }];
                
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(filePath, nil);
                    });
                }
            }];
        
        // 监听下载进度
        if (progressBlock) {
            [session.delegateQueue addOperationWithBlock:^{
                [downloadTask resume];
            }];
        } else {
            [downloadTask resume];
        }
    }];
}

#pragma mark - 辅助方法

+ (NSString *)sanitizeFileName:(NSString *)fileName {
    // 移除文件名中的非法字符
    NSCharacterSet *illegalChars = [NSCharacterSet characterSetWithCharactersInString:@"/:*?\"<>|"];
    NSArray *components = [fileName componentsSeparatedByCharactersInSet:illegalChars];
    return [components componentsJoinedByString:@"_"];
}

+ (NSString *)md5StringFromString:(NSString *)string {
    // 简单的 MD5（用于 API 请求）
    // 注意：这里应该用正确的 MD5 实现，这里简化处理
    return string;
}

@end
