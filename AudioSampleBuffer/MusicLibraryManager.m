//
//  MusicLibraryManager.m
//  AudioSampleBuffer
//
//  音乐库管理器实现
//

#import "MusicLibraryManager.h"
#import "AudioFileFormats.h"
#import <AVFoundation/AVFoundation.h>

#pragma mark - MusicItem 实现

@implementation MusicItem

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)itemWithFileName:(NSString *)fileName {
    return [[self alloc] initWithFileName:fileName filePath:nil];
}

+ (instancetype)itemWithFileName:(NSString *)fileName filePath:(NSString *)filePath {
    return [[self alloc] initWithFileName:fileName filePath:filePath];
}

- (instancetype)initWithFileName:(NSString *)fileName filePath:(nullable NSString *)filePath {
    if (self = [super init]) {
        _fileName = [fileName copy];
        _filePath = filePath ? [filePath copy] : [self resolveFilePath:fileName];
        _fileExtension = [[fileName pathExtension] lowercaseString];
        _displayName = [self extractDisplayName:fileName];
        _addedDate = [NSDate date];
        _playCount = 0;
        _isFavorite = NO;
        _isNCM = [_fileExtension isEqualToString:@"ncm"];
        _isDecrypted = NO;
        _categories = @[];
        
        // 提取文件信息
        [self extractFileInfo];
    }
    return self;
}

- (NSString *)resolveFilePath:(NSString *)fileName {
    // 尝试从 Bundle 查找
    NSURL *url = [[NSBundle mainBundle] URLForResource:fileName withExtension:nil];
    if (url) {
        return url.path;
    }
    
    // 尝试从 Audio 目录查找
    NSString *audioPath = [[NSBundle mainBundle] pathForResource:@"Audio" ofType:nil];
    if (audioPath) {
        NSString *fullPath = [audioPath stringByAppendingPathComponent:fileName];
        if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
            return fullPath;
        }
    }
    
    return fileName;
}

- (void)extractFileInfo {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // 获取文件大小
    if ([fm fileExistsAtPath:self.filePath]) {
        NSDictionary *attrs = [fm attributesOfItemAtPath:self.filePath error:nil];
        _fileSize = [attrs[NSFileSize] longLongValue];
    }
    
    // 尝试提取艺术家和专辑信息
    [self extractMetadata];
}

- (void)extractMetadata {
    // 从文件名提取艺术家（格式：艺术家 - 歌名.mp3）
    NSArray *components = [self.fileName componentsSeparatedByString:@" - "];
    if (components.count >= 2) {
        _artist = components[0];
        _displayName = components[1];
        
        // 移除扩展名
        _displayName = [_displayName stringByDeletingPathExtension];
    }
    
    // TODO: 使用 AVAsset 提取更详细的元数据
}

- (NSString *)extractDisplayName:(NSString *)fileName {
    // 移除扩展名
    NSString *name = [fileName stringByDeletingPathExtension];
    
    // 移除艺术家部分（如果有）
    NSArray *components = [name componentsSeparatedByString:@" - "];
    if (components.count >= 2) {
        return components[1];
    }
    
    return name;
}

- (NSString *)playableFilePath {
    if (self.isNCM) {
        if (self.isDecrypted && self.decryptedPath) {
            return self.decryptedPath;
        }
        
        // 尝试自动解密
        NSString *path = [AudioFileFormats prepareAudioFileForPlayback:self.fileName];
        if ([path hasPrefix:@"/"]) {
            self.isDecrypted = YES;
            self.decryptedPath = path;
            return path;
        }
    }
    
    return self.filePath;
}

- (NSString *)formattedDuration {
    if (self.duration <= 0) return @"--:--";
    
    NSInteger minutes = (NSInteger)self.duration / 60;
    NSInteger seconds = (NSInteger)self.duration % 60;
    return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)seconds];
}

- (NSString *)formattedFileSize {
    if (self.fileSize <= 0) return @"--";
    
    double mb = self.fileSize / 1024.0 / 1024.0;
    if (mb >= 1.0) {
        return [NSString stringWithFormat:@"%.1f MB", mb];
    }
    
    double kb = self.fileSize / 1024.0;
    return [NSString stringWithFormat:@"%.0f KB", kb];
}

- (NSString *)formattedArtistAndAlbum {
    NSMutableArray *parts = [NSMutableArray array];
    if (self.artist.length > 0) {
        [parts addObject:self.artist];
    }
    if (self.album.length > 0) {
        [parts addObject:self.album];
    }
    return parts.count > 0 ? [parts componentsJoinedByString:@" - "] : @"未知";
}

#pragma mark - NSCoding (用于持久化)

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.fileName forKey:@"fileName"];
    [coder encodeObject:self.displayName forKey:@"displayName"];
    [coder encodeObject:self.filePath forKey:@"filePath"];
    [coder encodeObject:self.fileExtension forKey:@"fileExtension"];
    [coder encodeObject:self.artist forKey:@"artist"];
    [coder encodeObject:self.album forKey:@"album"];
    [coder encodeDouble:self.duration forKey:@"duration"];
    [coder encodeInt64:self.fileSize forKey:@"fileSize"];
    [coder encodeObject:self.addedDate forKey:@"addedDate"];
    [coder encodeInteger:self.playCount forKey:@"playCount"];
    [coder encodeObject:self.lastPlayDate forKey:@"lastPlayDate"];
    [coder encodeBool:self.isFavorite forKey:@"isFavorite"];
    [coder encodeBool:self.isNCM forKey:@"isNCM"];
    [coder encodeBool:self.isDecrypted forKey:@"isDecrypted"];
    [coder encodeObject:self.decryptedPath forKey:@"decryptedPath"];
    [coder encodeObject:self.categories forKey:@"categories"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _fileName = [coder decodeObjectOfClass:[NSString class] forKey:@"fileName"];
        _displayName = [coder decodeObjectOfClass:[NSString class] forKey:@"displayName"];
        _filePath = [coder decodeObjectOfClass:[NSString class] forKey:@"filePath"];
        _fileExtension = [coder decodeObjectOfClass:[NSString class] forKey:@"fileExtension"];
        _artist = [coder decodeObjectOfClass:[NSString class] forKey:@"artist"];
        _album = [coder decodeObjectOfClass:[NSString class] forKey:@"album"];
        _duration = [coder decodeDoubleForKey:@"duration"];
        _fileSize = [coder decodeInt64ForKey:@"fileSize"];
        _addedDate = [coder decodeObjectOfClass:[NSDate class] forKey:@"addedDate"];
        _playCount = [coder decodeIntegerForKey:@"playCount"];
        _lastPlayDate = [coder decodeObjectOfClass:[NSDate class] forKey:@"lastPlayDate"];
        _isFavorite = [coder decodeBoolForKey:@"isFavorite"];
        _isNCM = [coder decodeBoolForKey:@"isNCM"];
        _isDecrypted = [coder decodeBoolForKey:@"isDecrypted"];
        _decryptedPath = [coder decodeObjectOfClass:[NSString class] forKey:@"decryptedPath"];
        _categories = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [NSString class], nil] forKey:@"categories"];
    }
    return self;
}

@end

#pragma mark - MusicLibraryManager 实现

@interface MusicLibraryManager ()

@property (nonatomic, strong) NSMutableArray<MusicItem *> *musicLibrary;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<MusicItem *> *> *customCategories;
@property (nonatomic, strong) NSString *cacheFilePath;

@end

@implementation MusicLibraryManager

#pragma mark - 单例

+ (instancetype)sharedManager {
    static MusicLibraryManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _musicLibrary = [NSMutableArray array];
        _customCategories = [NSMutableDictionary dictionary];
        
        // 设置缓存路径
        NSString *cachesDir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        _cacheFilePath = [cachesDir stringByAppendingPathComponent:@"MusicLibrary.cache"];
        
        // 尝试从缓存加载
        [self loadFromCache];
        
        // 如果缓存为空，加载音乐库
        if (self.musicLibrary.count == 0) {
            [self loadMusicLibrary];
        }
    }
    return self;
}

#pragma mark - 基础操作

- (void)loadMusicLibrary {
    NSLog(@"📚 开始加载音乐库...");
    
    [self.musicLibrary removeAllObjects];
    
    // 从 AudioFileFormats 加载所有音频文件
    NSArray<NSString *> *fileNames = [AudioFileFormats loadAudioFilesFromBundle];
    
    for (NSString *fileName in fileNames) {
        MusicItem *item = [MusicItem itemWithFileName:fileName];
        [self.musicLibrary addObject:item];
    }
    
    NSLog(@"📚 音乐库加载完成: %ld 首歌曲", (long)self.musicLibrary.count);
    
    // 保存到缓存
    [self saveToCache];
}

- (void)reloadMusicLibrary {
    [self loadMusicLibrary];
}

- (NSArray<MusicItem *> *)allMusic {
    return [self.musicLibrary copy];
}

- (NSInteger)totalMusicCount {
    return self.musicLibrary.count;
}

#pragma mark - 分类管理

- (NSArray<MusicItem *> *)musicForCategory:(MusicCategory)category {
    switch (category) {
        case MusicCategoryAll:
            return [self allMusic];
            
        case MusicCategoryRecent:
            return [self recentPlayedMusic:50];
            
        case MusicCategoryFavorite:
            return [self favoriteMusic];
            
        case MusicCategoryMP3:
            return [self musicWithExtension:@"mp3"];
            
        case MusicCategoryNCM:
            return [self allNCMFiles];
            
        case MusicCategoryFLAC:
            return [self musicWithExtension:@"flac"];
            
        case MusicCategoryOther:
            return [self musicWithOtherExtensions];
            
        case MusicCategoryChinese:
            return [self musicWithLanguage:@"Chinese"];
            
        case MusicCategoryEnglish:
            return [self musicWithLanguage:@"English"];
            
        default:
            return @[];
    }
}

- (NSInteger)countForCategory:(MusicCategory)category {
    return [[self musicForCategory:category] count];
}

+ (NSString *)nameForCategory:(MusicCategory)category {
    static NSDictionary *names = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @{
            @(MusicCategoryAll): @"全部歌曲",
            @(MusicCategoryRecent): @"最近播放",
            @(MusicCategoryFavorite): @"我的最爱",
            @(MusicCategoryMP3): @"MP3",
            @(MusicCategoryNCM): @"NCM加密",
            @(MusicCategoryFLAC): @"FLAC无损",
            @(MusicCategoryOther): @"其他格式",
            @(MusicCategoryChinese): @"华语歌曲",
            @(MusicCategoryEnglish): @"英文歌曲",
            @(MusicCategoryJapanese): @"日文歌曲",
            @(MusicCategoryKorean): @"韩文歌曲",
            @(MusicCategoryClassical): @"古典音乐",
            @(MusicCategoryPop): @"流行音乐",
            @(MusicCategoryRock): @"摇滚",
            @(MusicCategoryJazz): @"爵士",
        };
    });
    return names[@(category)] ?: @"未知分类";
}

- (NSArray<NSNumber *> *)availableCategories {
    NSMutableArray *categories = [NSMutableArray array];
    
    // 总是显示的分类
    [categories addObject:@(MusicCategoryAll)];
    
    // 根据内容动态添加
    if ([self countForCategory:MusicCategoryFavorite] > 0) {
        [categories addObject:@(MusicCategoryFavorite)];
    }
    if ([self countForCategory:MusicCategoryRecent] > 0) {
        [categories addObject:@(MusicCategoryRecent)];
    }
    if ([self countForCategory:MusicCategoryMP3] > 0) {
        [categories addObject:@(MusicCategoryMP3)];
    }
    if ([self countForCategory:MusicCategoryNCM] > 0) {
        [categories addObject:@(MusicCategoryNCM)];
    }
    if ([self countForCategory:MusicCategoryFLAC] > 0) {
        [categories addObject:@(MusicCategoryFLAC)];
    }
    
    return categories;
}

- (void)addCustomCategory:(NSString *)categoryName forMusic:(NSArray<MusicItem *> *)musicItems {
    self.customCategories[categoryName] = musicItems;
    [self saveToCache];
}

#pragma mark - 搜索功能

- (NSArray<MusicItem *> *)searchMusic:(NSString *)keyword {
    if (keyword.length == 0) {
        return [self allMusic];
    }
    
    NSString *lowercaseKeyword = [keyword lowercaseString];
    
    return [self.musicLibrary filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MusicItem *item, NSDictionary *bindings) {
        return [[item.displayName lowercaseString] containsString:lowercaseKeyword] ||
               [[item.artist lowercaseString] containsString:lowercaseKeyword] ||
               [[item.album lowercaseString] containsString:lowercaseKeyword] ||
               [[item.fileName lowercaseString] containsString:lowercaseKeyword];
    }]];
}

- (NSArray<MusicItem *> *)searchMusic:(NSString *)keyword inCategory:(MusicCategory)category {
    NSArray *categoryMusic = [self musicForCategory:category];
    
    if (keyword.length == 0) {
        return categoryMusic;
    }
    
    NSString *lowercaseKeyword = [keyword lowercaseString];
    
    return [categoryMusic filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MusicItem *item, NSDictionary *bindings) {
        return [[item.displayName lowercaseString] containsString:lowercaseKeyword] ||
               [[item.artist lowercaseString] containsString:lowercaseKeyword];
    }]];
}

#pragma mark - 排序功能

- (NSArray<MusicItem *> *)sortMusic:(NSArray<MusicItem *> *)musicList
                             byType:(MusicSortType)sortType
                         ascending:(BOOL)ascending {
    
    NSArray *sorted = nil;
    
    switch (sortType) {
        case MusicSortByName:
            sorted = [musicList sortedArrayUsingComparator:^NSComparisonResult(MusicItem *a, MusicItem *b) {
                return [a.displayName compare:b.displayName options:NSCaseInsensitiveSearch];
            }];
            break;
            
        case MusicSortByArtist:
            sorted = [musicList sortedArrayUsingComparator:^NSComparisonResult(MusicItem *a, MusicItem *b) {
                return [a.artist compare:b.artist options:NSCaseInsensitiveSearch];
            }];
            break;
            
        case MusicSortByDate:
            sorted = [musicList sortedArrayUsingComparator:^NSComparisonResult(MusicItem *a, MusicItem *b) {
                return [a.addedDate compare:b.addedDate];
            }];
            break;
            
        case MusicSortByPlayCount:
            sorted = [musicList sortedArrayUsingComparator:^NSComparisonResult(MusicItem *a, MusicItem *b) {
                return [@(a.playCount) compare:@(b.playCount)];
            }];
            break;
            
        case MusicSortByDuration:
            sorted = [musicList sortedArrayUsingComparator:^NSComparisonResult(MusicItem *a, MusicItem *b) {
                return [@(a.duration) compare:@(b.duration)];
            }];
            break;
            
        case MusicSortByFileSize:
            sorted = [musicList sortedArrayUsingComparator:^NSComparisonResult(MusicItem *a, MusicItem *b) {
                return [@(a.fileSize) compare:@(b.fileSize)];
            }];
            break;
    }
    
    return ascending ? sorted : [[sorted reverseObjectEnumerator] allObjects];
}

#pragma mark - 播放记录

- (void)recordPlayForMusic:(MusicItem *)music {
    music.playCount++;
    music.lastPlayDate = [NSDate date];
    [self saveToCache];
}

- (NSArray<MusicItem *> *)recentPlayedMusic:(NSInteger)limit {
    NSArray *played = [self.musicLibrary filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MusicItem *item, NSDictionary *bindings) {
        return item.lastPlayDate != nil;
    }]];
    
    NSArray *sorted = [played sortedArrayUsingComparator:^NSComparisonResult(MusicItem *a, MusicItem *b) {
        return [b.lastPlayDate compare:a.lastPlayDate];
    }];
    
    if (limit > 0 && sorted.count > limit) {
        return [sorted subarrayWithRange:NSMakeRange(0, limit)];
    }
    
    return sorted;
}

- (NSArray<MusicItem *> *)mostPlayedMusic:(NSInteger)limit {
    NSArray *sorted = [self sortMusic:self.musicLibrary byType:MusicSortByPlayCount ascending:NO];
    
    if (limit > 0 && sorted.count > limit) {
        return [sorted subarrayWithRange:NSMakeRange(0, limit)];
    }
    
    return sorted;
}

#pragma mark - 收藏管理

- (void)toggleFavoriteForMusic:(MusicItem *)music {
    music.isFavorite = !music.isFavorite;
    [self saveToCache];
}

- (NSArray<MusicItem *> *)favoriteMusic {
    return [self.musicLibrary filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MusicItem *item, NSDictionary *bindings) {
        return item.isFavorite;
    }]];
}

#pragma mark - NCM 文件管理

- (NSArray<MusicItem *> *)allNCMFiles {
    return [self.musicLibrary filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MusicItem *item, NSDictionary *bindings) {
        return item.isNCM;
    }]];
}

- (NSArray<MusicItem *> *)unDecryptedNCMFiles {
    return [self.musicLibrary filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MusicItem *item, NSDictionary *bindings) {
        return item.isNCM && !item.isDecrypted;
    }]];
}

- (void)updateNCMDecryptionStatus:(MusicItem *)music decryptedPath:(NSString *)path {
    music.isDecrypted = YES;
    music.decryptedPath = path;
    [self saveToCache];
}

#pragma mark - 统计信息

- (NSDictionary *)statistics {
    NSInteger totalCount = self.musicLibrary.count;
    NSInteger mp3Count = [self countForCategory:MusicCategoryMP3];
    NSInteger ncmCount = [self countForCategory:MusicCategoryNCM];
    NSInteger flacCount = [self countForCategory:MusicCategoryFLAC];
    NSInteger favoriteCount = [self countForCategory:MusicCategoryFavorite];
    
    long long totalSize = 0;
    for (MusicItem *item in self.musicLibrary) {
        totalSize += item.fileSize;
    }
    
    return @{
        @"totalCount": @(totalCount),
        @"mp3Count": @(mp3Count),
        @"ncmCount": @(ncmCount),
        @"flacCount": @(flacCount),
        @"favoriteCount": @(favoriteCount),
        @"totalSize": @(totalSize),
    };
}

#pragma mark - 辅助方法

- (NSArray<MusicItem *> *)musicWithExtension:(NSString *)extension {
    return [self.musicLibrary filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MusicItem *item, NSDictionary *bindings) {
        return [item.fileExtension isEqualToString:extension];
    }]];
}

- (NSArray<MusicItem *> *)musicWithOtherExtensions {
    return [self.musicLibrary filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MusicItem *item, NSDictionary *bindings) {
        return ![item.fileExtension isEqualToString:@"mp3"] &&
               ![item.fileExtension isEqualToString:@"ncm"] &&
               ![item.fileExtension isEqualToString:@"flac"];
    }]];
}

- (NSArray<MusicItem *> *)musicWithLanguage:(NSString *)language {
    // TODO: 实现语言检测
    return @[];
}

#pragma mark - 持久化

- (void)saveToCache {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.musicLibrary requiringSecureCoding:NO error:nil];
    [data writeToFile:self.cacheFilePath atomically:YES];
}

- (void)loadFromCache {
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.cacheFilePath]) {
        NSData *data = [NSData dataWithContentsOfFile:self.cacheFilePath];
        NSArray *cached = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSSet setWithObjects:[NSArray class], [MusicItem class], nil]
                                                               fromData:data
                                                                  error:nil];
        if (cached) {
            [self.musicLibrary addObjectsFromArray:cached];
            NSLog(@"📚 从缓存加载了 %ld 首歌曲", (long)cached.count);
        }
    }
}

@end

