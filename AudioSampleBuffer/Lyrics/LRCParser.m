//
//  LRCParser.m
//  AudioSampleBuffer
//
//  Created for parsing LRC lyrics files
//

#import "LRCParser.h"

#pragma mark - LRCLine Implementation

@implementation LRCLine

- (instancetype)initWithTime:(NSTimeInterval)time text:(NSString *)text {
    if (self = [super init]) {
        _time = time;
        _text = text ?: @"";
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"[%02d:%02d.%02d] %@",
            (int)(_time / 60),
            (int)((int)_time % 60),
            (int)((_time - (int)_time) * 100),
            _text];
}

@end

#pragma mark - LRCParser Implementation

@interface LRCParser ()

@property (nonatomic, strong) NSMutableArray<LRCLine *> *mutableLyrics;

@end

@implementation LRCParser

- (instancetype)init {
    if (self = [super init]) {
        _mutableLyrics = [NSMutableArray array];
        _offset = 0;
    }
    return self;
}

- (NSArray<LRCLine *> *)lyrics {
    return [_mutableLyrics copy];
}

- (BOOL)parseFromFile:(NSString *)filePath {
    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:filePath
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    
    if (error) {
        NSLog(@"读取LRC文件失败: %@", error);
        return NO;
    }
    
    return [self parseFromString:content];
}

- (BOOL)parseFromString:(NSString *)lrcString {
    if (!lrcString || lrcString.length == 0) {
        return NO;
    }
    
    [_mutableLyrics removeAllObjects];
    
    // 按行分割
    NSArray *lines = [lrcString componentsSeparatedByString:@"\n"];
    
    for (NSString *line in lines) {
        NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if (trimmedLine.length == 0) {
            continue;
        }
        
        // 解析元数据标签 [ti:标题] [ar:艺术家] [al:专辑] [by:作者] [offset:偏移]
        if ([self parseMetadata:trimmedLine]) {
            continue;
        }
        
        // 解析时间标签 [mm:ss.xx] 或 [mm:ss]
        [self parseTimestampLine:trimmedLine];
    }
    
    // 按时间排序
    [_mutableLyrics sortUsingComparator:^NSComparisonResult(LRCLine *obj1, LRCLine *obj2) {
        if (obj1.time < obj2.time) return NSOrderedAscending;
        if (obj1.time > obj2.time) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    
    return _mutableLyrics.count > 0;
}

- (BOOL)parseMetadata:(NSString *)line {
    // 元数据格式: [tag:value]
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\[([a-z]+):([^\\]]+)\\]"
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:nil];
    
    NSTextCheckingResult *match = [regex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
    
    if (match && match.numberOfRanges >= 3) {
        NSString *tag = [line substringWithRange:[match rangeAtIndex:1]];
        NSString *value = [line substringWithRange:[match rangeAtIndex:2]];
        
        tag = [tag lowercaseString];
        
        if ([tag isEqualToString:@"ti"]) {
            self.title = value;
        } else if ([tag isEqualToString:@"ar"]) {
            self.artist = value;
        } else if ([tag isEqualToString:@"al"]) {
            self.album = value;
        } else if ([tag isEqualToString:@"by"]) {
            self.by = value;
        } else if ([tag isEqualToString:@"offset"]) {
            self.offset = [value doubleValue];
        }
        
        return YES;
    }
    
    return NO;
}

- (void)parseTimestampLine:(NSString *)line {
    // 时间戳格式: [mm:ss.xx]文本 或 [mm:ss]文本
    // 支持一行多个时间戳: [00:12.00][00:17.20]歌词文本
    
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\[(\\d+):(\\d+)(?:\\.(\\d+))?\\]"
                                                                           options:0
                                                                             error:nil];
    
    NSArray *matches = [regex matchesInString:line options:0 range:NSMakeRange(0, line.length)];
    
    if (matches.count == 0) {
        return;
    }
    
    // 提取文本部分（去除所有时间标签）
    NSString *text = line;
    for (NSTextCheckingResult *match in matches.reverseObjectEnumerator) {
        text = [text stringByReplacingCharactersInRange:match.range withString:@""];
    }
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    // 为每个时间戳创建歌词行
    for (NSTextCheckingResult *match in matches) {
        NSString *minutes = [line substringWithRange:[match rangeAtIndex:1]];
        NSString *seconds = [line substringWithRange:[match rangeAtIndex:2]];
        NSString *milliseconds = @"0";
        
        if (match.numberOfRanges >= 4 && [match rangeAtIndex:3].location != NSNotFound) {
            milliseconds = [line substringWithRange:[match rangeAtIndex:3]];
        }
        
        NSTimeInterval time = [minutes intValue] * 60.0 +
                              [seconds intValue] +
                              [milliseconds intValue] / 100.0;
        
        // 应用偏移
        time += self.offset / 1000.0;
        
        LRCLine *lrcLine = [[LRCLine alloc] initWithTime:time text:text];
        [_mutableLyrics addObject:lrcLine];
    }
}

- (nullable LRCLine *)lyricLineForTime:(NSTimeInterval)currentTime {
    NSInteger index = [self indexForTime:currentTime];
    
    if (index >= 0 && index < _mutableLyrics.count) {
        return _mutableLyrics[index];
    }
    
    return nil;
}

- (NSInteger)indexForTime:(NSTimeInterval)currentTime {
    if (_mutableLyrics.count == 0) {
        return -1;
    }
    
    // 二分查找
    NSInteger left = 0;
    NSInteger right = _mutableLyrics.count - 1;
    NSInteger result = -1;
    
    while (left <= right) {
        NSInteger mid = (left + right) / 2;
        LRCLine *line = _mutableLyrics[mid];
        
        if (line.time <= currentTime) {
            result = mid;
            left = mid + 1;
        } else {
            right = mid - 1;
        }
    }
    
    return result;
}

@end

