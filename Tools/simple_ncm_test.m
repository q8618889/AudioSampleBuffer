#import <Foundation/Foundation.h>
#import "AudioFileFormats.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            printf("用法: %s <ncm文件>\n", argv[0]);
            return 1;
        }
        
        NSString *inputPath = [NSString stringWithUTF8String:argv[1]];
        NSString *outputPath = [inputPath.stringByDeletingPathExtension stringByAppendingString:@"_decrypted.mp3"];
        
        printf("输入: %s\n", inputPath.UTF8String);
        printf("输出: %s\n", outputPath.UTF8String);
        printf("\n");
        
        NSError *error = nil;
        NSString *result = [NCMDecryptor decryptNCMFile:inputPath
                                             outputPath:outputPath
                                                  error:&error];
        
        if (result) {
            printf("\n✅ 成功！\n");
            printf("输出文件: %s\n", result.UTF8String);
            
            // 检查文件头
            NSData *data = [NSData dataWithContentsOfFile:result];
            if (data.length >= 16) {
                const unsigned char *bytes = data.bytes;
                printf("\n文件头（前16字节）:\n");
                for (int i = 0; i < 16; i++) {
                    printf("%02X ", bytes[i]);
                    if ((i + 1) % 8 == 0) printf("\n");
                }
                printf("\n");
                
                // 检查是否是有效的 MP3
                if (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
                    printf("✅ 有效的 MP3 文件（帧同步）\n");
                } else if (memcmp(bytes, "ID3", 3) == 0) {
                    printf("✅ 有效的 MP3 文件（ID3v2）\n");
                } else if (memcmp(bytes, "fLaC", 4) == 0) {
                    printf("✅ 有效的 FLAC 文件\n");
                } else {
                    printf("⚠️  文件头不匹配标准格式\n");
                }
            }
            
            return 0;
        } else {
            printf("\n❌ 失败\n");
            printf("错误: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }
    }
}

