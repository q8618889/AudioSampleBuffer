#!/usr/bin/env xcrun -sdk macosx clang -framework Foundation -framework Security
//
//  test_ncm_decryptor.m
//  
//  NCM 解密器命令行测试工具
//  编译运行：
//    chmod +x test_ncm_decryptor.m
//    ./test_ncm_decryptor.m /path/to/file.ncm
//
//  或者编译后运行：
//    clang -framework Foundation -framework Security -o ncm_decrypt test_ncm_decryptor.m ../AudioSampleBuffer/AudioFileFormats.m
//    ./ncm_decrypt /path/to/file.ncm
//

#import <Foundation/Foundation.h>

// 直接包含实现（简化编译）
#import <CommonCrypto/CommonCrypto.h>

// ========================================
// NCMDecryptor 精简版实现
// ========================================

static NSString * const NCMDecryptorErrorDomain = @"com.test.ncmdecryptor";

typedef NS_ENUM(NSInteger, NCMDecryptorError) {
    NCMDecryptorErrorInvalidFile = 1000,
    NCMDecryptorErrorInvalidFormat,
    NCMDecryptorErrorDecryptionFailed,
    NCMDecryptorErrorFileIOFailed,
};

@interface NCMDecryptor : NSObject
+ (nullable NSString *)decryptNCMFile:(NSString *)inputPath
                           outputPath:(nullable NSString *)outputPath
                                error:(NSError **)error;
@end

@implementation NCMDecryptor

+ (NSData *)coreKey {
    static NSData *coreKey = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const unsigned char key[] = {
            0x68, 0x7A, 0x48, 0x52, 0x41, 0x6D, 0x73, 0x6F,
            0x35, 0x6B, 0x49, 0x6E, 0x62, 0x61, 0x78, 0x57
        };
        coreKey = [NSData dataWithBytes:key length:sizeof(key)];
    });
    return coreKey;
}

+ (NSData *)metaKey {
    static NSData *metaKey = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const unsigned char key[] = {
            0x23, 0x31, 0x34, 0x6C, 0x6A, 0x6B, 0x5F, 0x21,
            0x5C, 0x5D, 0x26, 0x30, 0x55, 0x3C, 0x27, 0x28
        };
        metaKey = [NSData dataWithBytes:key length:sizeof(key)];
    });
    return metaKey;
}

+ (nullable NSData *)aesECBDecrypt:(NSData *)data key:(NSData *)key {
    if (!data || !key) return nil;
    
    size_t bufferSize = data.length + kCCBlockSizeAES128;
    void *buffer = malloc(bufferSize);
    
    size_t numBytesDecrypted = 0;
    CCCryptorStatus cryptStatus = CCCrypt(
        kCCDecrypt,
        kCCAlgorithmAES,
        kCCOptionECBMode,
        key.bytes,
        key.length,
        NULL,
        data.bytes,
        data.length,
        buffer,
        bufferSize,
        &numBytesDecrypted
    );
    
    if (cryptStatus == kCCSuccess) {
        NSData *result = [NSData dataWithBytes:buffer length:numBytesDecrypted];
        free(buffer);
        return result;
    }
    
    free(buffer);
    return nil;
}

+ (nullable NSData *)base64DecodeModified:(NSData *)data {
    NSString *base64String = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!base64String) return nil;
    
    base64String = [base64String stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    base64String = [base64String stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    
    NSInteger paddingLength = (4 - (base64String.length % 4)) % 4;
    for (NSInteger i = 0; i < paddingLength; i++) {
        base64String = [base64String stringByAppendingString:@"="];
    }
    
    return [[NSData alloc] initWithBase64EncodedString:base64String options:0];
}

+ (nullable NSString *)decryptNCMFile:(NSString *)inputPath
                           outputPath:(nullable NSString *)outputPath
                                error:(NSError **)error {
    
    printf("🔓 开始解密: %s\n", inputPath.lastPathComponent.UTF8String);
    
    NSData *fileData = [NSData dataWithContentsOfFile:inputPath];
    if (!fileData) {
        if (error) {
            *error = [NSError errorWithDomain:NCMDecryptorErrorDomain
                                         code:NCMDecryptorErrorFileIOFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"无法读取文件"}];
        }
        return nil;
    }
    
    const unsigned char *bytes = fileData.bytes;
    NSUInteger length = fileData.length;
    NSUInteger offset = 0;
    
    if (length < 10 || memcmp(bytes, "CTENFDAM", 8) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:NCMDecryptorErrorDomain
                                         code:NCMDecryptorErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"不是有效的 NCM 文件"}];
        }
        return nil;
    }
    offset += 10;
    
    if (offset + 4 > length) goto invalid_format;
    
    uint32_t keyLength = *(uint32_t *)(bytes + offset);
    offset += 4;
    
    if (offset + keyLength > length) goto invalid_format;
    
    NSMutableData *keyData = [NSMutableData dataWithBytes:bytes + offset length:keyLength];
    unsigned char *keyBytes = keyData.mutableBytes;
    for (NSUInteger i = 0; i < keyLength; i++) {
        keyBytes[i] ^= 0x64;
    }
    offset += keyLength;
    
    NSData *decryptedKey = [self aesECBDecrypt:keyData key:[self coreKey]];
    if (!decryptedKey || decryptedKey.length < 17) goto decryption_failed;
    
    decryptedKey = [decryptedKey subdataWithRange:NSMakeRange(17, decryptedKey.length - 17)];
    
    unsigned char keyBox[256];
    for (int i = 0; i < 256; i++) {
        keyBox[i] = i;
    }
    
    const unsigned char *keyDataBytes = decryptedKey.bytes;
    NSUInteger keyDataLength = decryptedKey.length;
    
    unsigned char j = 0;
    for (int i = 0; i < 256; i++) {
        j = (j + keyBox[i] + keyDataBytes[i % keyDataLength]) & 0xFF;
        unsigned char temp = keyBox[i];
        keyBox[i] = keyBox[j];
        keyBox[j] = temp;
    }
    
    if (offset + 4 > length) goto invalid_format;
    
    uint32_t metaLength = *(uint32_t *)(bytes + offset);
    offset += 4;
    
    NSString *detectedFormat = @"mp3";
    
    if (metaLength > 0 && offset + metaLength <= length) {
        NSMutableData *metaData = [NSMutableData dataWithBytes:bytes + offset length:metaLength];
        unsigned char *metaBytes = metaData.mutableBytes;
        for (NSUInteger i = 0; i < metaLength; i++) {
            metaBytes[i] ^= 0x63;
        }
        
        if (metaData.length > 22) {
            metaData = [NSMutableData dataWithData:[metaData subdataWithRange:NSMakeRange(22, metaData.length - 22)]];
            
            NSData *decodedMeta = [self base64DecodeModified:metaData];
            
            if (decodedMeta) {
                NSData *decryptedMeta = [self aesECBDecrypt:decodedMeta key:[self metaKey]];
                
                if (decryptedMeta && decryptedMeta.length > 0) {
                    const unsigned char *metaBytes = decryptedMeta.bytes;
                    NSUInteger metaLen = decryptedMeta.length;
                    unsigned char padding = metaBytes[metaLen - 1];
                    if (padding > 0 && padding <= 16 && metaLen > padding) {
                        decryptedMeta = [decryptedMeta subdataWithRange:NSMakeRange(0, metaLen - padding)];
                    }
                    
                    NSString *jsonString = [[NSString alloc] initWithData:decryptedMeta encoding:NSUTF8StringEncoding];
                    if (jsonString.length > 6 && [jsonString hasPrefix:@"music:"]) {
                        jsonString = [jsonString substringFromIndex:6];
                        NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
                        NSDictionary *metadata = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
                        
                        if (metadata) {
                            NSString *musicName = metadata[@"musicName"] ?: @"未知";
                            NSArray *artists = metadata[@"artist"];
                            NSString *artistNames = @"未知";
                            if (artists && [artists isKindOfClass:[NSArray class]]) {
                                NSMutableArray *names = [NSMutableArray array];
                                for (NSArray *artist in artists) {
                                    if ([artist isKindOfClass:[NSArray class]] && artist.count > 0) {
                                        [names addObject:artist[0]];
                                    }
                                }
                                if (names.count > 0) {
                                    artistNames = [names componentsJoinedByString:@", "];
                                }
                            }
                            printf("   歌曲: %s\n", musicName.UTF8String);
                            printf("   艺术家: %s\n", artistNames.UTF8String);
                            
                            NSString *format = metadata[@"format"];
                            if (format && format.length > 0) {
                                detectedFormat = format;
                            }
                        }
                    }
                }
            }
        }
        
        offset += metaLength;
    }
    
    if (offset + 5 > length) goto invalid_format;
    offset += 5;
    
    if (offset + 4 > length) goto invalid_format;
    uint32_t imageSize = *(uint32_t *)(bytes + offset);
    offset += 4;
    
    if (offset + imageSize > length) goto invalid_format;
    offset += imageSize;
    
    if (offset >= length) goto invalid_format;
    
    NSUInteger audioDataLength = length - offset;
    NSMutableData *audioData = [NSMutableData dataWithCapacity:audioDataLength];
    
    const unsigned char *audioBytes = bytes + offset;
    unsigned char *decryptedBytes = malloc(audioDataLength);
    
    for (NSUInteger i = 0; i < audioDataLength; i++) {
        unsigned char idx1 = (i + 1) & 0xFF;
        unsigned char idx2 = (keyBox[idx1] + keyBox[(keyBox[idx1] + idx1) & 0xFF]) & 0xFF;
        unsigned char k = keyBox[idx2];
        decryptedBytes[i] = audioBytes[i] ^ k;
    }
    
    [audioData appendBytes:decryptedBytes length:audioDataLength];
    free(decryptedBytes);
    
    if ([detectedFormat isEqualToString:@"mp3"] && audioData.length >= 4) {
        const unsigned char *header = audioData.bytes;
        if (memcmp(header, "fLaC", 4) == 0) {
            detectedFormat = @"flac";
        }
    }
    
    if (!outputPath) {
        NSString *baseName = [inputPath stringByDeletingPathExtension];
        outputPath = [baseName stringByAppendingPathExtension:detectedFormat];
    }
    
    BOOL success = [audioData writeToFile:outputPath atomically:YES];
    if (!success) {
        if (error) {
            *error = [NSError errorWithDomain:NCMDecryptorErrorDomain
                                         code:NCMDecryptorErrorFileIOFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"无法写入输出文件"}];
        }
        return nil;
    }
    
    printf("   ✅ 解密成功\n");
    printf("   格式: %s\n", detectedFormat.uppercaseString.UTF8String);
    printf("   输出: %s\n", outputPath.lastPathComponent.UTF8String);
    printf("   大小: %.2f MB\n", audioData.length / 1024.0 / 1024.0);
    
    return outputPath;
    
invalid_format:
    if (error) {
        *error = [NSError errorWithDomain:NCMDecryptorErrorDomain
                                     code:NCMDecryptorErrorInvalidFormat
                                 userInfo:@{NSLocalizedDescriptionKey: @"NCM 文件格式损坏"}];
    }
    return nil;
    
decryption_failed:
    if (error) {
        *error = [NSError errorWithDomain:NCMDecryptorErrorDomain
                                     code:NCMDecryptorErrorDecryptionFailed
                                 userInfo:@{NSLocalizedDescriptionKey: @"解密失败"}];
    }
    return nil;
}

@end

// ========================================
// Main 函数
// ========================================

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        printf("=====================================\n");
        printf("  NCM 解密器 - Objective-C 版本\n");
        printf("=====================================\n\n");
        
        if (argc < 2) {
            printf("用法: %s <ncm文件路径> [输出路径]\n", argv[0]);
            printf("\n示例:\n");
            printf("  %s song.ncm\n", argv[0]);
            printf("  %s song.ncm output.mp3\n", argv[0]);
            printf("  %s /path/to/*.ncm\n", argv[0]);
            return 1;
        }
        
        NSString *inputPath = [NSString stringWithUTF8String:argv[1]];
        NSString *outputPath = nil;
        
        if (argc >= 3) {
            outputPath = [NSString stringWithUTF8String:argv[2]];
        }
        
        // 检查是否是目录或通配符
        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL isDirectory = NO;
        
        if ([fm fileExistsAtPath:inputPath isDirectory:&isDirectory]) {
            if (isDirectory) {
                // 处理目录
                printf("📂 处理目录: %s\n\n", inputPath.UTF8String);
                
                NSArray *files = [fm contentsOfDirectoryAtPath:inputPath error:nil];
                NSMutableArray *ncmFiles = [NSMutableArray array];
                
                for (NSString *file in files) {
                    if ([[file.pathExtension lowercaseString] isEqualToString:@"ncm"]) {
                        [ncmFiles addObject:[inputPath stringByAppendingPathComponent:file]];
                    }
                }
                
                if (ncmFiles.count == 0) {
                    printf("❌ 未找到 NCM 文件\n");
                    return 1;
                }
                
                printf("找到 %lu 个 NCM 文件\n\n", (unsigned long)ncmFiles.count);
                
                NSInteger successCount = 0;
                
                for (NSInteger i = 0; i < ncmFiles.count; i++) {
                    printf("[%ld/%lu] ================\n", (long)(i+1), (unsigned long)ncmFiles.count);
                    
                    NSError *error = nil;
                    NSString *output = [NCMDecryptor decryptNCMFile:ncmFiles[i]
                                                         outputPath:nil
                                                              error:&error];
                    
                    if (output) {
                        successCount++;
                    } else {
                        printf("   ❌ 失败: %s\n", error.localizedDescription.UTF8String);
                    }
                    printf("\n");
                }
                
                printf("=====================================\n");
                printf("📊 统计:\n");
                printf("   成功: %ld 个\n", (long)successCount);
                printf("   失败: %ld 个\n", (long)(ncmFiles.count - successCount));
                printf("   总计: %lu 个\n", (unsigned long)ncmFiles.count);
                
                return 0;
            }
        }
        
        // 处理单个文件
        NSError *error = nil;
        NSString *result = [NCMDecryptor decryptNCMFile:inputPath
                                             outputPath:outputPath
                                                  error:&error];
        
        printf("\n=====================================\n");
        
        if (result) {
            printf("✅ 成功！\n");
            printf("输出文件: %s\n", result.UTF8String);
            return 0;
        } else {
            printf("❌ 失败\n");
            printf("错误: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }
    }
}

