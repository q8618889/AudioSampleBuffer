//
//  TestDownload.m
//  AudioSampleBuffer
//
//  快速测试下载功能
//  用法：在 ViewController.m 的 viewDidLoad 或任意按钮点击事件中调用
//

#import <Foundation/Foundation.h>
#import "KugouMusicDownloader.h"
#import "MusicDownloadManager.h"

@interface TestDownload : NSObject
+ (void)runTest;
@end

@implementation TestDownload

+ (void)runTest {
    NSLog(@"🧪 ============ 开始测试下载功能 ============");
    
    // 测试1：搜索音乐
    [self testSearch];
    
    // 测试2：直接下载（3秒后）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self testDirectDownload];
    });
}

#pragma mark - 测试1：搜索

+ (void)testSearch {
    NSLog(@"\n📝 测试1: 搜索音乐");
    NSLog(@"关键词: 周杰伦");
    
    [KugouMusicDownloader searchMusic:@"周杰伦"
                                limit:3
                           completion:^(NSArray<KugouSongInfo *> *songs, NSError *error) {
        if (error) {
            NSLog(@"❌ 搜索失败: %@", error.localizedDescription);
            return;
        }
        
        NSLog(@"✅ 搜索成功，找到 %lu 首歌曲:", (unsigned long)songs.count);
        
        for (NSInteger i = 0; i < songs.count; i++) {
            KugouSongInfo *song = songs[i];
            NSLog(@"  %ld. %@ - %@ (%.1fMB)",
                  (long)i+1,
                  song.artistName,
                  song.songName,
                  song.fileSize / 1024.0 / 1024.0);
        }
    }];
}

#pragma mark - 测试2：直接下载

+ (void)testDirectDownload {
    NSLog(@"\n📥 测试2: 直接下载音乐");
    
    // 先搜索，然后下载第一首
    [KugouMusicDownloader searchMusic:@"告白气球"
                                limit:1
                           completion:^(NSArray<KugouSongInfo *> *songs, NSError *error) {
        if (error || songs.count == 0) {
            NSLog(@"❌ 搜索失败");
            return;
        }
        
        KugouSongInfo *firstSong = songs.firstObject;
        NSLog(@"准备下载: %@ - %@", firstSong.artistName, firstSong.songName);
        
        // 下载目录
        NSString *downloadDir = [[MusicDownloadManager sharedManager] downloadDirectory];
        NSLog(@"下载目录: %@", downloadDir);
        
        // 开始下载
        [KugouMusicDownloader downloadMusic:firstSong
                                toDirectory:downloadDir
                                   progress:^(float progress) {
            // 下载进度
            static NSInteger lastPercent = -1;
            NSInteger currentPercent = (NSInteger)(progress * 100);
            
            if (currentPercent != lastPercent && currentPercent % 10 == 0) {
                NSLog(@"⬇️ 下载进度: %ld%%", (long)currentPercent);
                lastPercent = currentPercent;
            }
            
        } completion:^(NSString *filePath, NSError *downloadError) {
            if (downloadError) {
                NSLog(@"❌ 下载失败: %@", downloadError.localizedDescription);
                return;
            }
            
            NSLog(@"✅ 下载完成!");
            NSLog(@"   文件路径: %@", filePath);
            NSLog(@"   文件大小: %.2f MB", [self fileSizeAtPath:filePath] / 1024.0 / 1024.0);
            
            // 检查歌词文件
            NSString *lyricsPath = [[filePath stringByDeletingPathExtension] stringByAppendingPathExtension:@"lrc"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:lyricsPath]) {
                NSLog(@"   ✅ 歌词文件已保存: %@", lyricsPath.lastPathComponent);
            }
            
            NSLog(@"\n🎉 测试完成! 你现在可以在音乐库中找到这首歌。");
        }];
    }];
}

#pragma mark - 辅助方法

+ (unsigned long long)fileSizeAtPath:(NSString *)filePath {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
    return [attributes fileSize];
}

@end

#pragma mark - 使用说明

/*
 
 📖 如何使用这个测试文件：
 
 方法1：在 ViewController.m 中测试
 
 1. 在 ViewController.m 顶部添加：
    #import "TestDownload.m"
 
 2. 在 viewDidLoad 最后添加：
    [TestDownload runTest];
 
 3. 运行项目，查看控制台输出
 
 
 方法2：创建一个测试按钮
 
 - (void)createTestButton {
     UIButton *testButton = [UIButton buttonWithType:UIButtonTypeSystem];
     [testButton setTitle:@"🧪 测试下载" forState:UIControlStateNormal];
     testButton.frame = CGRectMake(20, 100, 100, 40);
     [testButton addTarget:self action:@selector(testButtonTapped) forControlEvents:UIControlEventTouchUpInside];
     [self.view addSubview:testButton];
 }
 
 - (void)testButtonTapped {
     [TestDownload runTest];
 }
 
 
 预期输出：
 
 🧪 ============ 开始测试下载功能 ============
 
 📝 测试1: 搜索音乐
 关键词: 周杰伦
 ✅ 搜索成功，找到 3 首歌曲:
   1. 周杰伦 - 告白气球 (8.5MB)
   2. 周杰伦 - 七里香 (9.2MB)
   3. 周杰伦 - 稻香 (8.8MB)
 
 📥 测试2: 直接下载音乐
 准备下载: 周杰伦 - 告白气球
 下载目录: /Users/.../Documents/Downloads
 🔍 [酷狗] 获取下载链接: abc123
 ✅ [酷狗] 获取到下载链接（方式1）
 ⬇️ [酷狗] 开始下载: 告白气球
 ⬇️ 下载进度: 10%
 ⬇️ 下载进度: 20%
 ⬇️ 下载进度: 30%
 ...
 ⬇️ 下载进度: 100%
 ✅ [酷狗] 下载完成: 周杰伦 - 告白气球.mp3
 ✅ [酷狗] 歌词已保存
 ✅ 下载完成!
    文件路径: /Users/.../Downloads/周杰伦 - 告白气球.mp3
    文件大小: 8.50 MB
    ✅ 歌词文件已保存: 周杰伦 - 告白气球.lrc
 
 🎉 测试完成! 你现在可以在音乐库中找到这首歌。
 
 */
