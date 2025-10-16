#import <Foundation/Foundation.h>
#import "AudioFileFormats.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            printf("用法: %s <ncm文件>\n", argv[0]);
            return 1;
        }
        
        NSString *inputPath = [NSString stringWithUTF8String:argv[1]];
        
        printf("========================================\n");
        printf("NCM 完整解密测试（解密 + 封面 + 歌词）\n");
        printf("========================================\n\n");
        
        printf("输入文件: %s\n\n", inputPath.UTF8String);
        
        // 1. 解密文件
        printf("步骤 1: 解密 NCM 文件...\n");
        NSError *error = nil;
        NSString *mp3Path = [NCMDecryptor decryptNCMFile:inputPath
                                              outputPath:nil
                                                   error:&error];
        
        if (!mp3Path) {
            printf("❌ 解密失败: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }
        
        printf("✅ 解密成功: %s\n\n", mp3Path.UTF8String);
        
        // 2. 检查封面
        printf("步骤 2: 检查封面...\n");
        NSData *mp3Data = [NSData dataWithContentsOfFile:mp3Path];
        if (mp3Data.length >= 10 && memcmp(mp3Data.bytes, "ID3", 3) == 0) {
            printf("✅ 文件包含 ID3 标签\n");
            
            // 简单检查是否有 APIC 帧
            NSString *mp3String = [[NSString alloc] initWithData:mp3Data encoding:NSISOLatin1StringEncoding];
            if ([mp3String containsString:@"APIC"]) {
                printf("✅ 检测到封面数据 (APIC 帧)\n");
            }
        }
        printf("\n");
        
        // 3. 检查歌词
        printf("步骤 3: 检查歌词...\n");
        NSString *lrcPath = [[mp3Path stringByDeletingPathExtension] stringByAppendingPathExtension:@"lrc"];
        
        // 等待几秒让歌词下载完成
        printf("等待歌词下载...\n");
        for (int i = 0; i < 30; i++) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:lrcPath]) {
                break;
            }
            [NSThread sleepForTimeInterval:0.5];
        }
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:lrcPath]) {
            NSString *lyrics = [NSString stringWithContentsOfFile:lrcPath
                                                         encoding:NSUTF8StringEncoding
                                                            error:nil];
            if (lyrics && lyrics.length > 0) {
                printf("✅ 歌词文件: %s\n", lrcPath.lastPathComponent.UTF8String);
                
                // 统计歌词行数
                NSArray *lines = [lyrics componentsSeparatedByString:@"\n"];
                NSInteger lrcLines = 0;
                for (NSString *line in lines) {
                    if ([line hasPrefix:@"["]) {
                        lrcLines++;
                    }
                }
                printf("   歌词行数: %ld 行\n", (long)lrcLines);
                
                // 打印前3行
                printf("   前3行预览:\n");
                NSInteger count = 0;
                for (NSString *line in lines) {
                    if ([line hasPrefix:@"["] && line.length > 0) {
                        printf("   %s\n", line.UTF8String);
                        count++;
                        if (count >= 3) break;
                    }
                }
            }
        } else {
            printf("⚠️  未找到歌词文件（可能该歌曲无歌词或下载失败）\n");
        }
        
        printf("\n========================================\n");
        printf("测试完成！\n");
        printf("========================================\n");
        
        // 4. 文件信息汇总
        printf("\n生成的文件:\n");
        printf("  音频: %s\n", mp3Path.lastPathComponent.UTF8String);
        
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:mp3Path error:nil];
        printf("  大小: %.2f MB\n", [attrs[NSFileSize] doubleValue] / 1024.0 / 1024.0);
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:lrcPath]) {
            printf("  歌词: %s\n", lrcPath.lastPathComponent.UTF8String);
        }
        
        return 0;
    }
}

