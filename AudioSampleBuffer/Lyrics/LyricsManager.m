//
//  LyricsManager.m
//  AudioSampleBuffer
//
//  Created for managing lyrics download and storage
//

#import "LyricsManager.h"
#import <AVFoundation/AVFoundation.h>

@interface LyricsManager ()

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSCache *lyricsCache;

@end

@implementation LyricsManager

+ (instancetype)sharedManager {
    static LyricsManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[LyricsManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 30;
        _session = [NSURLSession sessionWithConfiguration:config];
        _lyricsCache = [[NSCache alloc] init];
        _lyricsCache.countLimit = 50;
        
        // 确保歌词沙盒目录存在
        NSString *lyricsDir = [self lyricsSandboxDirectory];
        if (![[NSFileManager defaultManager] fileExistsAtPath:lyricsDir]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:lyricsDir
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];
        }
    }
    return self;
}

- (void)fetchLyricsForAudioFile:(NSString *)audioPath
                     completion:(LyricsCompletionBlock)completion {
    
    // 检查缓存
    LRCParser *cached = [_lyricsCache objectForKey:audioPath];
    if (cached) {
        NSLog(@"📖 [歌词] 从缓存加载: %@", [audioPath lastPathComponent]);
        if (completion) {
            completion(cached, nil);
        }
        return;
    }
    
    NSString *audioFileName = [[audioPath lastPathComponent] stringByDeletingPathExtension];
    
    // 优先级1: Bundle中的LRC文件（随应用打包）
    NSString *bundleLrcPath = [[audioPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"lrc"];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:bundleLrcPath]) {
        NSLog(@"📖 [歌词] 从Bundle加载: %@.lrc", audioFileName);
        [self loadLocalLyrics:bundleLrcPath completion:^(LRCParser *parser, NSError *error) {
            if (parser) {
                [self.lyricsCache setObject:parser forKey:audioPath];
            }
            if (completion) {
                completion(parser, error);
            }
        }];
        return;
    }
    
    // 优先级2: 沙盒Documents中的LRC文件（动态下载）
    NSString *sandboxLrcPath = [[self lyricsSandboxDirectory] stringByAppendingPathComponent:
                                [NSString stringWithFormat:@"%@.lrc", audioFileName]];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:sandboxLrcPath]) {
        NSLog(@"📖 [歌词] 从沙盒加载: %@.lrc", audioFileName);
        [self loadLocalLyrics:sandboxLrcPath completion:^(LRCParser *parser, NSError *error) {
            if (parser) {
                [self.lyricsCache setObject:parser forKey:audioPath];
            }
            if (completion) {
                completion(parser, error);
            }
        }];
        return;
    }
    
    // 优先级3: MP3的ID3歌词标签
    NSString *id3Lyrics = [self extractLyricsFromID3:audioPath];
    if (id3Lyrics && id3Lyrics.length > 0) {
        NSLog(@"📖 [歌词] 从ID3标签提取: %@", audioFileName);
        LRCParser *parser = [[LRCParser alloc] init];
        BOOL success = [parser parseFromString:id3Lyrics];
        
        if (success) {
            [self.lyricsCache setObject:parser forKey:audioPath];
            
            // 保存到沙盒以便下次快速加载
            [self saveLyrics:id3Lyrics forAudioFile:audioPath];
            
            if (completion) {
                completion(parser, nil);
            }
            return;
        }
    }
    
    // 优先级4: 从网易云API动态获取
    NSString *musicId = [self extractNeteaseIdFromAudio:audioPath];
    
    if (musicId) {
        NSLog(@"📖 [歌词] 从网易云API获取: %@ (ID: %@)", audioFileName, musicId);
        [self fetchLyricsFromNetease:musicId completion:^(LRCParser *parser, NSError *error) {
            if (parser) {
                [self.lyricsCache setObject:parser forKey:audioPath];
                
                // 保存到沙盒
                NSString *lrcContent = [self convertParserToLRCString:parser];
                [self saveLyrics:lrcContent forAudioFile:audioPath];
            }
            
            if (completion) {
                completion(parser, error);
            }
        }];
    } else {
        // 没有找到歌词
        NSLog(@"⚠️ [歌词] 未找到歌词: %@", audioFileName);
        NSError *error = [NSError errorWithDomain:@"LyricsManager"
                                             code:404
                                         userInfo:@{NSLocalizedDescriptionKey: @"未找到歌词文件"}];
        if (completion) {
            completion(nil, error);
        }
    }
}

- (void)fetchLyricsFromNetease:(NSString *)musicId
                    completion:(LyricsCompletionBlock)completion {
    
    // 网易云音乐歌词API
    NSString *urlString = [NSString stringWithFormat:@"https://music.163.com/api/song/lyric?id=%@&lv=1&tv=-1", musicId];
    NSURL *url = [NSURL URLWithString:urlString];
    
    if (!url) {
        NSError *error = [NSError errorWithDomain:@"LyricsManager"
                                             code:400
                                         userInfo:@{NSLocalizedDescriptionKey: @"无效的URL"}];
        if (completion) {
            completion(nil, error);
        }
        return;
    }
    
    NSURLSessionDataTask *task = [_session dataTaskWithURL:url
                                         completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(nil, error);
                }
            });
            return;
        }
        
        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                             options:0
                                                               error:&jsonError];
        
        if (jsonError || !json) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(nil, jsonError);
                }
            });
            return;
        }
        
        NSString *lrcContent = json[@"lrc"][@"lyric"];
        
        if (!lrcContent || lrcContent.length == 0) {
            NSError *noLyricsError = [NSError errorWithDomain:@"LyricsManager"
                                                         code:404
                                                     userInfo:@{NSLocalizedDescriptionKey: @"该歌曲暂无歌词"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(nil, noLyricsError);
                }
            });
            return;
        }
        
        LRCParser *parser = [[LRCParser alloc] init];
        BOOL success = [parser parseFromString:lrcContent];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                if (success) {
                    completion(parser, nil);
                } else {
                    NSError *parseError = [NSError errorWithDomain:@"LyricsManager"
                                                              code:500
                                                          userInfo:@{NSLocalizedDescriptionKey: @"歌词解析失败"}];
                    completion(nil, parseError);
                }
            }
        });
    }];
    
    [task resume];
}

- (void)loadLocalLyrics:(NSString *)lrcPath
             completion:(LyricsCompletionBlock)completion {
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        LRCParser *parser = [[LRCParser alloc] init];
        BOOL success = [parser parseFromFile:lrcPath];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                if (success) {
                    completion(parser, nil);
                } else {
                    NSError *error = [NSError errorWithDomain:@"LyricsManager"
                                                         code:500
                                                     userInfo:@{NSLocalizedDescriptionKey: @"LRC文件解析失败"}];
                    completion(nil, error);
                }
            }
        });
    });
}

- (nullable NSString *)extractNeteaseIdFromAudio:(NSString *)audioPath {
    NSURL *audioURL = [NSURL fileURLWithPath:audioPath];
    AVAsset *asset = [AVAsset assetWithURL:audioURL];
    
    NSArray *metadata = [asset commonMetadata];
    
    for (AVMetadataItem *item in metadata) {
        if ([item.commonKey.lowercaseString isEqualToString:@"comment"]) {
            NSString *comment = (NSString *)item.value;
            
            // 查找 "163 key(Don't modify):" 标记
            if ([comment containsString:@"163 key"]) {
                // 尝试解密163 key获取音乐ID
                // 注意：这需要实现AES解密，这里先返回nil
                // 实际应用中可以使用CommonCrypto框架解密
                NSLog(@"发现163 key，但需要解密: %@", [comment substringToIndex:MIN(50, comment.length)]);
                
                // TODO: 实现163 key解密
                // 目前返回nil，让应用使用其他方式获取歌词
                return nil;
            }
        }
        
        // 有些应用可能直接存储musicId
        if ([item.commonKey.lowercaseString isEqualToString:@"musicid"]) {
            return (NSString *)item.value;
        }
    }
    
    return nil;
}

- (BOOL)saveLyrics:(NSString *)lrcContent forAudioFile:(NSString *)audioPath {
    // 保存到沙盒Documents/Lyrics目录
    NSString *audioFileName = [[audioPath lastPathComponent] stringByDeletingPathExtension];
    NSString *lrcPath = [[self lyricsSandboxDirectory] stringByAppendingPathComponent:
                        [NSString stringWithFormat:@"%@.lrc", audioFileName]];
    
    NSError *error = nil;
    BOOL success = [lrcContent writeToFile:lrcPath
                                atomically:YES
                                  encoding:NSUTF8StringEncoding
                                     error:&error];
    
    if (error) {
        NSLog(@"❌ [歌词] 保存失败: %@ - %@", audioFileName, error);
    } else {
        NSLog(@"✅ [歌词] 已保存到沙盒: %@.lrc", audioFileName);
    }
    
    return success;
}

- (NSString *)convertParserToLRCString:(LRCParser *)parser {
    NSMutableString *lrcString = [NSMutableString string];
    
    if (parser.title) {
        [lrcString appendFormat:@"[ti:%@]\n", parser.title];
    }
    if (parser.artist) {
        [lrcString appendFormat:@"[ar:%@]\n", parser.artist];
    }
    if (parser.album) {
        [lrcString appendFormat:@"[al:%@]\n", parser.album];
    }
    if (parser.by) {
        [lrcString appendFormat:@"[by:%@]\n", parser.by];
    }
    
    [lrcString appendString:@"\n"];
    
    for (LRCLine *line in parser.lyrics) {
        int minutes = (int)(line.time / 60);
        int seconds = (int)line.time % 60;
        int centiseconds = (int)((line.time - (int)line.time) * 100);
        
        [lrcString appendFormat:@"[%02d:%02d.%02d]%@\n", minutes, seconds, centiseconds, line.text];
    }
    
    return lrcString;
}

- (nullable NSString *)extractLyricsFromID3:(NSString *)audioPath {
    NSURL *audioURL = [NSURL fileURLWithPath:audioPath];
    AVAsset *asset = [AVAsset assetWithURL:audioURL];
    
    // 获取所有元数据
    NSArray *metadata = [asset metadata];
    
    // 查找USLT (Unsynchronized Lyrics/Text) frame
    for (AVMetadataItem *item in metadata) {
        // ID3标签中的歌词
        if ([item.commonKey isEqualToString:AVMetadataCommonKeyDescription] ||
            [item.key isEqual:@"USLT"] ||
            [item.key isEqual:@"©lyr"] ||
            [item.identifier.description containsString:@"lyrics"]) {
            
            NSString *value = (NSString *)[item.value copyWithZone:nil];
            if (value && value.length > 0) {
                NSLog(@"🎵 [ID3] 发现歌词标签: %@ (key: %@)", 
                      [audioPath lastPathComponent], item.key);
                return value;
            }
        }
    }
    
    // 尝试从iTunes格式的metadata
    NSArray *iTunesMetadata = [AVMetadataItem metadataItemsFromArray:metadata
                                                             withKey:AVMetadataID3MetadataKeyUnsynchronizedLyric
                                                            keySpace:AVMetadataKeySpaceID3];
    
    if (iTunesMetadata.count > 0) {
        AVMetadataItem *lyricsItem = iTunesMetadata.firstObject;
        NSString *value = (NSString *)[lyricsItem.value copyWithZone:nil];
        if (value && value.length > 0) {
            NSLog(@"🎵 [ID3] 发现iTunes歌词: %@", [audioPath lastPathComponent]);
            return value;
        }
    }
    
    return nil;
}

- (NSString *)lyricsSandboxDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, 
                                                         NSUserDomainMask, 
                                                         YES);
    NSString *documentsDirectory = paths.firstObject;
    NSString *lyricsDirectory = [documentsDirectory stringByAppendingPathComponent:@"Lyrics"];
    
    return lyricsDirectory;
}

@end

