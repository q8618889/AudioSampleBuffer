//
//  AudioFileFormats.m
//  AudioSampleBuffer
//
//  Created by AudioSampleBuffer on 2025.
//
//  NCM 解密算法基于 taurusxin/ncmdump (https://github.com/taurusxin/ncmdump)
//  最新更新：2025-10
//

#import "AudioFileFormats.h"
#import <CommonCrypto/CommonCrypto.h>

// 错误域
static NSString * const NCMDecryptorErrorDomain = @"com.audiosamplebuffer.ncmdecryptor";

// 错误码
typedef NS_ENUM(NSInteger, NCMDecryptorError) {
    NCMDecryptorErrorInvalidFile = 1000,
    NCMDecryptorErrorInvalidFormat,
    NCMDecryptorErrorDecryptionFailed,
    NCMDecryptorErrorFileIOFailed,
};

@implementation NCMDecryptor

#pragma mark - ID3v2 标签写入

/**
 * 将封面嵌入到 MP3 文件
 * 简化版 ID3v2.3 写入器
 */
+ (BOOL)embedCoverToMP3:(NSString *)mp3Path 
              coverData:(NSData *)coverData 
               mimeType:(NSString *)mimeType {
    
    if (!mp3Path || !coverData || coverData.length == 0) {
        return NO;
    }
    
    // 读取原始 MP3 数据
    NSData *originalData = [NSData dataWithContentsOfFile:mp3Path];
    if (!originalData) {
        return NO;
    }
    
    const unsigned char *bytes = originalData.bytes;
    NSUInteger length = originalData.length;
    NSUInteger audioDataOffset = 0;
    
    // 检查是否已有 ID3v2 标签
    if (length >= 10 && memcmp(bytes, "ID3", 3) == 0) {
        // 跳过现有的 ID3v2 标签
        uint32_t tagSize = ((bytes[6] & 0x7F) << 21) |
                           ((bytes[7] & 0x7F) << 14) |
                           ((bytes[8] & 0x7F) << 7) |
                           (bytes[9] & 0x7F);
        audioDataOffset = 10 + tagSize;
        
        // 检查是否有扩展头
        if (bytes[5] & 0x40) {
            if (audioDataOffset + 4 <= length) {
                uint32_t extSize = (bytes[audioDataOffset] << 24) |
                                   (bytes[audioDataOffset + 1] << 16) |
                                   (bytes[audioDataOffset + 2] << 8) |
                                   bytes[audioDataOffset + 3];
                audioDataOffset += extSize;
            }
        }
    }
    
    // 提取音频数据
    NSData *audioData = [originalData subdataWithRange:NSMakeRange(audioDataOffset, length - audioDataOffset)];
    
    // 构建 APIC 帧 (Attached Picture)
    NSMutableData *apicFrame = [NSMutableData data];
    
    // 帧 ID: "APIC"
    [apicFrame appendBytes:"APIC" length:4];
    
    // 帧内容
    NSMutableData *frameContent = [NSMutableData data];
    
    // Text encoding (0 = ISO-8859-1)
    unsigned char encoding = 0x00;
    [frameContent appendBytes:&encoding length:1];
    
    // MIME type
    const char *mime = [mimeType UTF8String];
    [frameContent appendBytes:mime length:strlen(mime) + 1]; // 包含 null terminator
    
    // Picture type (3 = Cover (front))
    unsigned char pictureType = 0x03;
    [frameContent appendBytes:&pictureType length:1];
    
    // Description (empty)
    unsigned char nullByte = 0x00;
    [frameContent appendBytes:&nullByte length:1];
    
    // Picture data
    [frameContent appendData:coverData];
    
    // 帧大小 (不包含帧头的10字节)
    uint32_t frameSize = (uint32_t)frameContent.length;
    unsigned char sizeBytes[4] = {
        (frameSize >> 24) & 0xFF,
        (frameSize >> 16) & 0xFF,
        (frameSize >> 8) & 0xFF,
        frameSize & 0xFF
    };
    [apicFrame appendBytes:sizeBytes length:4];
    
    // 帧标志 (2字节，都设为0)
    unsigned char flags[2] = {0x00, 0x00};
    [apicFrame appendBytes:flags length:2];
    
    // 添加帧内容
    [apicFrame appendData:frameContent];
    
    // 构建完整的 ID3v2 标签
    NSMutableData *id3Tag = [NSMutableData data];
    
    // ID3v2 头部
    [id3Tag appendBytes:"ID3" length:3];  // 文件标识符
    [id3Tag appendBytes:"\x03\x00" length:2];  // 版本号 (v2.3.0)
    [id3Tag appendBytes:"\x00" length:1];  // 标志
    
    // 标签大小 (使用 synchsafe integer)
    uint32_t tagSize = (uint32_t)apicFrame.length;
    unsigned char synchsafeSize[4] = {
        (tagSize >> 21) & 0x7F,
        (tagSize >> 14) & 0x7F,
        (tagSize >> 7) & 0x7F,
        tagSize & 0x7F
    };
    [id3Tag appendBytes:synchsafeSize length:4];
    
    // 添加 APIC 帧
    [id3Tag appendData:apicFrame];
    
    // 合并 ID3 标签和音频数据
    NSMutableData *finalData = [NSMutableData dataWithData:id3Tag];
    [finalData appendData:audioData];
    
    // 写入文件
    return [finalData writeToFile:mp3Path atomically:YES];
}

#pragma mark - 核心密钥

// 核心密钥（用于解密嵌入的密钥）
+ (NSData *)coreKey {
    static NSData *coreKey = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // "687A4852416D736F356B496E62617857"
        const unsigned char key[] = {
            0x68, 0x7A, 0x48, 0x52, 0x41, 0x6D, 0x73, 0x6F,
            0x35, 0x6B, 0x49, 0x6E, 0x62, 0x61, 0x78, 0x57
        };
        coreKey = [NSData dataWithBytes:key length:sizeof(key)];
    });
    return coreKey;
}

// 元数据密钥（用于解密元数据）
+ (NSData *)metaKey {
    static NSData *metaKey = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // "2331346C6A6B5F215C5D2630553C2728"
        const unsigned char key[] = {
            0x23, 0x31, 0x34, 0x6C, 0x6A, 0x6B, 0x5F, 0x21,
            0x5C, 0x5D, 0x26, 0x30, 0x55, 0x3C, 0x27, 0x28
        };
        metaKey = [NSData dataWithBytes:key length:sizeof(key)];
    });
    return metaKey;
}

#pragma mark - AES 解密

+ (nullable NSData *)aesECBDecrypt:(NSData *)data key:(NSData *)key {
    if (!data || !key) return nil;
    
    size_t bufferSize = data.length + kCCBlockSizeAES128;
    void *buffer = malloc(bufferSize);
    
    size_t numBytesDecrypted = 0;
    CCCryptorStatus cryptStatus = CCCrypt(
        kCCDecrypt,
        kCCAlgorithmAES,
        kCCOptionECBMode,  // ECB 模式
        key.bytes,
        key.length,
        NULL,  // ECB 不需要 IV
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

#pragma mark - Base64 解码（去除填充的变体）

+ (nullable NSData *)base64DecodeModified:(NSData *)data {
    // NCM 使用的 Base64 可能不标准，需要处理
    NSString *base64String = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!base64String) return nil;
    
    // 修复 Base64 字符串（如果需要）
    base64String = [base64String stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    base64String = [base64String stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    
    // 添加填充
    NSInteger paddingLength = (4 - (base64String.length % 4)) % 4;
    for (NSInteger i = 0; i < paddingLength; i++) {
        base64String = [base64String stringByAppendingString:@"="];
    }
    
    return [[NSData alloc] initWithBase64EncodedString:base64String options:0];
}

#pragma mark - 核心解密逻辑

+ (nullable NSString *)decryptNCMFile:(NSString *)inputPath
                           outputPath:(nullable NSString *)outputPath
                                error:(NSError **)error {
    
    NSLog(@"🔓 开始解密: %@", inputPath.lastPathComponent);
    
    // 1. 读取文件
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
    
    // 2. 检查文件头 "CTENFDAM"
    if (length < 10 || memcmp(bytes, "CTENFDAM", 8) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:NCMDecryptorErrorDomain
                                         code:NCMDecryptorErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"不是有效的 NCM 文件"}];
        }
        return nil;
    }
    offset += 10;  // 跳过 "CTENFDAM" + 2字节
    
    // 3. 解密密钥
    if (offset + 4 > length) {
        if (error) {
            *error = [NSError errorWithDomain:NCMDecryptorErrorDomain
                                         code:NCMDecryptorErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"NCM 文件格式损坏"}];
        }
        return nil;
    }
    
    uint32_t keyLength = *(uint32_t *)(bytes + offset);
    offset += 4;
    
    if (offset + keyLength > length) {
        if (error) {
            *error = [NSError errorWithDomain:NCMDecryptorErrorDomain
                                         code:NCMDecryptorErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"NCM 文件格式损坏"}];
        }
        return nil;
    }
    
    // XOR 0x64
    NSMutableData *keyData = [NSMutableData dataWithBytes:bytes + offset length:keyLength];
    unsigned char *keyBytes = keyData.mutableBytes;
    for (NSUInteger i = 0; i < keyLength; i++) {
        keyBytes[i] ^= 0x64;
    }
    offset += keyLength;
    
    // AES 解密密钥
    NSData *decryptedKey = [self aesECBDecrypt:keyData key:[self coreKey]];
    if (!decryptedKey || decryptedKey.length < 17) {
        if (error) {
            *error = [NSError errorWithDomain:NCMDecryptorErrorDomain
                                         code:NCMDecryptorErrorDecryptionFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"解密失败"}];
        }
        return nil;
    }
    
    // 去除 PKCS7 填充
    const unsigned char *keyBytes2 = decryptedKey.bytes;
    NSUInteger decryptedLength = decryptedKey.length;
    unsigned char padding = keyBytes2[decryptedLength - 1];
    if (padding > 0 && padding <= 16 && decryptedLength > padding) {
        decryptedKey = [decryptedKey subdataWithRange:NSMakeRange(0, decryptedLength - padding)];
    }
    
    // 去掉 "neteasecloudmusic" 前缀
    decryptedKey = [decryptedKey subdataWithRange:NSMakeRange(17, decryptedKey.length - 17)];
    
    // 生成 RC4 密钥盒（KSA - Key Scheduling Algorithm）
    unsigned char keyBox[256];
    for (int i = 0; i < 256; i++) {
        keyBox[i] = i;
    }
    
    const unsigned char *keyDataBytes = decryptedKey.bytes;
    NSUInteger keyDataLength = decryptedKey.length;
    
    // KSA 阶段：初始化密钥盒
    unsigned char j = 0;
    for (int i = 0; i < 256; i++) {
        j = (j + keyBox[i] + keyDataBytes[i % keyDataLength]) & 0xFF;
        // 交换
        unsigned char temp = keyBox[i];
        keyBox[i] = keyBox[j];
        keyBox[j] = temp;
    }
    
    // 4. 解密元数据（可选）
    if (offset + 4 > length) {
        if (error) {
            *error = [NSError errorWithDomain:NCMDecryptorErrorDomain
                                         code:NCMDecryptorErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"NCM 文件格式损坏"}];
        }
        return nil;
    }
    
    uint32_t metaLength = *(uint32_t *)(bytes + offset);
    offset += 4;
    
    NSDictionary *metadata = nil;
    NSString *detectedFormat = @"mp3";  // 默认
    
    if (metaLength > 0 && offset + metaLength <= length) {
        // XOR 0x63
        NSMutableData *metaData = [NSMutableData dataWithBytes:bytes + offset length:metaLength];
        unsigned char *metaBytes = metaData.mutableBytes;
        for (NSUInteger i = 0; i < metaLength; i++) {
            metaBytes[i] ^= 0x63;
        }
        
        // 去掉 "163 key(Don't modify):" 前缀（22字节）
        if (metaData.length > 22) {
            metaData = [NSMutableData dataWithData:[metaData subdataWithRange:NSMakeRange(22, metaData.length - 22)]];
            
            // Base64 解码
            NSData *decodedMeta = [self base64DecodeModified:metaData];
            
            if (decodedMeta) {
                // AES 解密
                NSData *decryptedMeta = [self aesECBDecrypt:decodedMeta key:[self metaKey]];
                
                if (decryptedMeta && decryptedMeta.length > 0) {
                    // 去除 PKCS7 填充
                    const unsigned char *metaBytes = decryptedMeta.bytes;
                    NSUInteger metaLen = decryptedMeta.length;
                    unsigned char padding = metaBytes[metaLen - 1];
                    if (padding > 0 && padding <= 16 && metaLen > padding) {
                        decryptedMeta = [decryptedMeta subdataWithRange:NSMakeRange(0, metaLen - padding)];
                    }
                    
                    // 解析 JSON (去掉 "music:" 前缀)
                    NSString *jsonString = [[NSString alloc] initWithData:decryptedMeta encoding:NSUTF8StringEncoding];
                    if (jsonString.length > 6 && [jsonString hasPrefix:@"music:"]) {
                        jsonString = [jsonString substringFromIndex:6];
                        NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
                        metadata = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
                        
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
                            NSLog(@"   歌曲: %@", musicName);
                            NSLog(@"   艺术家: %@", artistNames);
                            
                            // 获取格式
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
    
    // 5. 跳过 CRC (5 字节)
    if (offset + 5 > length) {
        if (error) {
            *error = [NSError errorWithDomain:NCMDecryptorErrorDomain
                                         code:NCMDecryptorErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"NCM 文件格式损坏"}];
        }
        return nil;
    }
    offset += 5;
    
    // 6. 提取封面图片
    // 🔧 修复：NCM 格式有 imageSpace 和 imageSize 两个字段
    if (offset + 8 > length) {
        if (error) {
            *error = [NSError errorWithDomain:NCMDecryptorErrorDomain
                                         code:NCMDecryptorErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"NCM 文件格式损坏"}];
        }
        return nil;
    }
    uint32_t imageSpace = *(uint32_t *)(bytes + offset);
    offset += 4;
    uint32_t imageSize = *(uint32_t *)(bytes + offset);
    offset += 4;
    
    // 提取封面数据
    NSData *imageData = nil;
    if (imageSize > 0 && offset + imageSize <= length) {
        imageData = [NSData dataWithBytes:bytes + offset length:imageSize];
        
        if (imageData.length >= 4) {
            const unsigned char *imgBytes = imageData.bytes;
            if (memcmp(imgBytes, "\x89PNG", 4) == 0) {
                NSLog(@"   📷 封面: PNG 格式, %.2f KB", imageSize / 1024.0);
            } else if (imgBytes[0] == 0xFF && imgBytes[1] == 0xD8) {
                NSLog(@"   📷 封面: JPEG 格式, %.2f KB", imageSize / 1024.0);
            } else {
                NSLog(@"   📷 封面: 未知格式, %.2f KB", imageSize / 1024.0);
            }
        }
        
        offset += imageSize;
    }
    
    // 跳过 imageSpace - imageSize 的剩余空间
    if (imageSpace > imageSize) {
        offset += (imageSpace - imageSize);
    }
    
    // 7. 解密音频数据
    if (offset >= length) {
        if (error) {
            *error = [NSError errorWithDomain:NCMDecryptorErrorDomain
                                         code:NCMDecryptorErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"NCM 文件格式损坏"}];
        }
        return nil;
    }
    
    NSUInteger audioDataLength = length - offset;
    NSMutableData *audioData = [NSMutableData dataWithCapacity:audioDataLength];
    
    const unsigned char *audioBytes = bytes + offset;
    unsigned char *decryptedBytes = malloc(audioDataLength);
    
    // 🔧 使用正确的 RC4 流密码算法
    // 参考：Python ncmdump 库 (https://pypi.org/project/ncmdump/)
    // 步骤：
    // 1. 生成 256 字节的密钥流：stream[i] = S[(S[i] + S[(i + S[i]) & 0xFF]) & 0xFF]
    // 2. 重复密钥流并从第2个字节开始使用（跳过第1个字节）
    // 3. XOR 解密
    
    // 步骤1：生成基础密钥流（256字节）
    // stream[i] = S[(S[i] + S[(i + S[i]) & 0xFF]) & 0xFF]
    unsigned char stream[256];
    for (int i = 0; i < 256; i++) {
        unsigned char si = keyBox[i];
        unsigned char sj = keyBox[(i + si) & 0xFF];
        stream[i] = keyBox[(si + sj) & 0xFF];
    }
    
    // 步骤2 & 3：使用密钥流解密（从第2个字节开始）
    for (NSUInteger i = 0; i < audioDataLength; i++) {
        // 注意：stream 索引从 1 开始（跳过第0个字节）
        unsigned char k = stream[(i + 1) % 256];
        decryptedBytes[i] = audioBytes[i] ^ k;
    }
    
    [audioData appendBytes:decryptedBytes length:audioDataLength];
    free(decryptedBytes);
    
    // 8. 检测输出格式（如果元数据中没有，从文件头检测）
    // 参考 taurusxin/ncmdump 的格式检测逻辑
    if (audioData.length >= 4) {
        const unsigned char *header = audioData.bytes;
        
        // 检测 FLAC（优先，因为元数据可能不准）
        if (memcmp(header, "fLaC", 4) == 0) {
            detectedFormat = @"flac";
        }
        // 检测 MP3 (ID3v2 标签)
        else if (memcmp(header, "ID3", 3) == 0) {
            detectedFormat = @"mp3";
        }
        // 检测 MP3 (帧同步)
        else if (header[0] == 0xFF && (header[1] & 0xE0) == 0xE0) {
            detectedFormat = @"mp3";
        }
    }
    
    // 9. 确定输出路径
    if (!outputPath) {
        NSString *baseName = [inputPath stringByDeletingPathExtension];
        outputPath = [baseName stringByAppendingPathExtension:detectedFormat];
    }
    
    // 10. 写入文件
    BOOL success = [audioData writeToFile:outputPath atomically:YES];
    if (!success) {
        if (error) {
            *error = [NSError errorWithDomain:NCMDecryptorErrorDomain
                                         code:NCMDecryptorErrorFileIOFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"无法写入输出文件"}];
        }
        return nil;
    }
    
    NSLog(@"   ✅ 解密成功: %@ (%@, %.2f MB)", 
          outputPath.lastPathComponent, 
          detectedFormat.uppercaseString, 
          audioData.length / 1024.0 / 1024.0);
    
    // 下载歌词（如果有 musicId）
    if (metadata && metadata[@"musicId"]) {
        NSString *lrcPath = [[outputPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"lrc"];
        
        // 检查歌词文件是否已存在
        if (![[NSFileManager defaultManager] fileExistsAtPath:lrcPath]) {
            // 异步下载歌词，不阻塞主流程
            id musicIdObj = metadata[@"musicId"];
            NSString *musicId = [musicIdObj isKindOfClass:[NSString class]] ? musicIdObj : [musicIdObj stringValue];
            [self downloadLyricsFromNetease:musicId completion:^(NSString *lyrics, NSError *lyricsError) {
                if (lyrics) {
                    [lyrics writeToFile:lrcPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
                    NSLog(@"   📝 歌词已下载: %@", lrcPath.lastPathComponent);
                }
            }];
        }
    }
    
    // 如果有封面数据，嵌入到 MP3 文件中
    if (imageData && imageData.length > 0 && [detectedFormat isEqualToString:@"mp3"]) {
        // 检测 MIME 类型
        const unsigned char *imgBytes = imageData.bytes;
        NSString *mimeType = @"image/jpeg";
        if (imageData.length >= 4 && memcmp(imgBytes, "\x89PNG", 4) == 0) {
            mimeType = @"image/png";
        }
        
        // 嵌入封面
        if ([self embedCoverToMP3:outputPath coverData:imageData mimeType:mimeType]) {
            NSLog(@"   🖼️  封面已嵌入 MP3");
        } else {
            NSLog(@"   ⚠️  封面嵌入失败，保存为单独文件");
            NSString *coverPath = [[outputPath stringByDeletingPathExtension] stringByAppendingString:@"_cover.jpg"];
            if ([imageData writeToFile:coverPath atomically:YES]) {
                NSLog(@"   💾 封面已保存: %@", coverPath.lastPathComponent);
            }
        }
    } else if (imageData && imageData.length > 0) {
        // FLAC 或其他格式，保存为单独文件
        NSString *extension = @"jpg";
        const unsigned char *imgBytes = imageData.bytes;
        if (imageData.length >= 4 && memcmp(imgBytes, "\x89PNG", 4) == 0) {
            extension = @"png";
        }
        NSString *coverPath = [[[outputPath stringByDeletingPathExtension] stringByAppendingString:@"_cover"] stringByAppendingPathExtension:extension];
        if ([imageData writeToFile:coverPath atomically:YES]) {
            NSLog(@"   💾 封面已保存: %@", coverPath.lastPathComponent);
        }
    }
    
    return outputPath;
}

#pragma mark - 批量解密

+ (NSInteger)decryptNCMFilesInDirectory:(NSString *)directoryPath
                              recursive:(BOOL)recursive
                          progressBlock:(nullable void(^)(NSInteger current, NSInteger total, NSString *filename, BOOL success))progressBlock {
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *ncmFiles = [NSMutableArray array];
    
    // 查找所有 NCM 文件
    if (recursive) {
        NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtPath:directoryPath];
        for (NSString *filename in enumerator) {
            if ([[filename.pathExtension lowercaseString] isEqualToString:@"ncm"]) {
                NSString *fullPath = [directoryPath stringByAppendingPathComponent:filename];
                [ncmFiles addObject:fullPath];
            }
        }
    } else {
        NSArray *contents = [fileManager contentsOfDirectoryAtPath:directoryPath error:nil];
        for (NSString *filename in contents) {
            if ([[filename.pathExtension lowercaseString] isEqualToString:@"ncm"]) {
                NSString *fullPath = [directoryPath stringByAppendingPathComponent:filename];
                BOOL isDirectory;
                if ([fileManager fileExistsAtPath:fullPath isDirectory:&isDirectory] && !isDirectory) {
                    [ncmFiles addObject:fullPath];
                }
            }
        }
    }
    
    if (ncmFiles.count == 0) {
        NSLog(@"❌ 未找到 NCM 文件");
        return 0;
    }
    
    NSLog(@"📂 找到 %ld 个 NCM 文件", (long)ncmFiles.count);
    
    NSInteger successCount = 0;
    
    for (NSInteger i = 0; i < ncmFiles.count; i++) {
        NSString *filePath = ncmFiles[i];
        NSLog(@"\n[%ld/%ld] %@", (long)(i+1), (long)ncmFiles.count, [NSString stringWithFormat:@"%@", @"="]);
        
        NSError *error = nil;
        NSString *output = [self decryptNCMFile:filePath outputPath:nil error:&error];
        
        BOOL success = (output != nil);
        if (success) {
            successCount++;
        } else {
            NSLog(@"   ❌ 失败: %@", error.localizedDescription);
        }
        
        if (progressBlock) {
            progressBlock(i + 1, ncmFiles.count, filePath.lastPathComponent, success);
        }
    }
    
    NSLog(@"\n%@", [@"=" stringByPaddingToLength:60 withString:@"=" startingAtIndex:0]);
    NSLog(@"📊 统计:");
    NSLog(@"   成功: %ld 个", (long)successCount);
    NSLog(@"   失败: %ld 个", (long)(ncmFiles.count - successCount));
    NSLog(@"   总计: %ld 个", (long)ncmFiles.count);
    
    return successCount;
}

#pragma mark - 辅助方法

+ (BOOL)isNCMFile:(NSString *)filePath {
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:filePath];
    if (!fileHandle) return NO;
    
    NSData *header = [fileHandle readDataOfLength:8];
    [fileHandle closeFile];
    
    if (header.length < 8) return NO;
    
    return memcmp(header.bytes, "CTENFDAM", 8) == 0;
}

+ (nullable NSDictionary *)extractMetadataFromNCM:(NSString *)filePath error:(NSError **)error {
    NSData *fileData = [NSData dataWithContentsOfFile:filePath];
    if (!fileData) {
        return nil;
    }
    
    const unsigned char *bytes = fileData.bytes;
    NSUInteger length = fileData.length;
    NSUInteger offset = 0;
    
    // 检查文件头
    if (length < 10 || memcmp(bytes, "CTENFDAM", 8) != 0) {
        return nil;
    }
    offset += 10;
    
    // 跳过密钥
    if (offset + 4 > length) return nil;
    uint32_t keyLength = *(uint32_t *)(bytes + offset);
    offset += 4 + keyLength;
    
    // 解密元数据
    if (offset + 4 > length) return nil;
    uint32_t metaLength = *(uint32_t *)(bytes + offset);
    offset += 4;
    
    if (metaLength == 0 || offset + metaLength > length) {
        return nil;
    }
    
    NSMutableData *metaData = [NSMutableData dataWithBytes:bytes + offset length:metaLength];
    unsigned char *metaBytes = metaData.mutableBytes;
    for (NSUInteger i = 0; i < metaLength; i++) {
        metaBytes[i] ^= 0x63;
    }
    
    if (metaData.length <= 22) return nil;
    metaData = [NSMutableData dataWithData:[metaData subdataWithRange:NSMakeRange(22, metaData.length - 22)]];
    
    NSData *decodedMeta = [self base64DecodeModified:metaData];
    if (!decodedMeta) return nil;
    
    NSData *decryptedMeta = [self aesECBDecrypt:decodedMeta key:[self metaKey]];
    if (!decryptedMeta || decryptedMeta.length == 0) return nil;
    
    // 去除 PKCS7 填充
    const unsigned char *decMetaBytes = decryptedMeta.bytes;
    NSUInteger metaLen = decryptedMeta.length;
    unsigned char padding = decMetaBytes[metaLen - 1];
    if (padding > 0 && padding <= 16 && metaLen > padding) {
        decryptedMeta = [decryptedMeta subdataWithRange:NSMakeRange(0, metaLen - padding)];
    }
    
    NSString *jsonString = [[NSString alloc] initWithData:decryptedMeta encoding:NSUTF8StringEncoding];
    if (!jsonString || jsonString.length <= 6 || ![jsonString hasPrefix:@"music:"]) {
        return nil;
    }
    
    jsonString = [jsonString substringFromIndex:6];
    NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    return [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:error];
}

+ (void)downloadLyricsFromNetease:(NSString *)musicId
                       completion:(void(^)(NSString * _Nullable lyrics, NSError * _Nullable error))completion {
    if (!musicId || musicId.length == 0) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:NCMDecryptorErrorDomain
                                                 code:NCMDecryptorErrorInvalidFile
                                             userInfo:@{NSLocalizedDescriptionKey: @"无效的音乐ID"}];
            completion(nil, error);
        }
        return;
    }
    
    // 网易云音乐歌词API
    NSString *urlString = [NSString stringWithFormat:@"https://music.163.com/api/song/lyric?id=%@&lv=1&tv=-1", musicId];
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"https://music.163.com/" forHTTPHeaderField:@"Referer"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            if (completion) {
                NSError *httpError = [NSError errorWithDomain:NCMDecryptorErrorDomain
                                                         code:NCMDecryptorErrorFileIOFailed
                                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode]}];
                completion(nil, httpError);
            }
            return;
        }
        
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (!json) {
            if (completion) {
                NSError *parseError = [NSError errorWithDomain:NCMDecryptorErrorDomain
                                                          code:NCMDecryptorErrorDecryptionFailed
                                                      userInfo:@{NSLocalizedDescriptionKey: @"解析响应失败"}];
                completion(nil, parseError);
            }
            return;
        }
        
        NSDictionary *lrcDict = json[@"lrc"];
        NSString *lyrics = lrcDict[@"lyric"];
        
        if (lyrics && lyrics.length > 0) {
            if (completion) {
                completion(lyrics, nil);
            }
        } else {
            if (completion) {
                NSError *noLyricsError = [NSError errorWithDomain:NCMDecryptorErrorDomain
                                                             code:NCMDecryptorErrorFileIOFailed
                                                         userInfo:@{NSLocalizedDescriptionKey: @"该歌曲暂无歌词"}];
                completion(nil, noLyricsError);
            }
        }
    }];
    
    [task resume];
}

+ (nullable NSString *)downloadLyricsForNCM:(NSString *)ncmPath
                                 outputPath:(nullable NSString *)outputPath
                                      error:(NSError **)error {
    // 提取元数据
    NSDictionary *metadata = [self extractMetadataFromNCM:ncmPath error:error];
    if (!metadata) {
        NSLog(@"   ⚠️  无法提取 NCM 元数据");
        return nil;
    }
    
    id musicIdObj = metadata[@"musicId"];
    NSString *musicId = [musicIdObj isKindOfClass:[NSString class]] ? musicIdObj : [musicIdObj stringValue];
    if (!musicId || musicId.length == 0) {
        NSLog(@"   ⚠️  未找到音乐ID");
        return nil;
    }
    
    NSLog(@"   🎵 音乐ID: %@", musicId);
    
    // 确定输出路径
    if (!outputPath) {
        NSString *baseName = [ncmPath stringByDeletingPathExtension];
        outputPath = [baseName stringByAppendingPathExtension:@"lrc"];
    }
    
    // 使用信号量实现同步下载
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSString *resultPath = nil;
    
    [self downloadLyricsFromNetease:musicId completion:^(NSString *lyrics, NSError *downloadError) {
        if (lyrics) {
            BOOL success = [lyrics writeToFile:outputPath atomically:YES encoding:NSUTF8StringEncoding error:error];
            if (success) {
                NSLog(@"   📝 歌词已保存: %@", outputPath.lastPathComponent);
                resultPath = outputPath;
            }
        } else {
            NSLog(@"   ⚠️  下载歌词失败: %@", downloadError.localizedDescription);
            if (error) *error = downloadError;
        }
        dispatch_semaphore_signal(semaphore);
    }];
    
    // 等待下载完成（最多10秒）
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    
    return resultPath;
}

@end

#pragma mark - AudioFileFormats 实现

@implementation AudioFileFormats

+ (NSArray<NSString *> *)loadAudioFilesFromBundle {
    NSMutableArray *audioFiles = [NSMutableArray array];
    
    // 支持的音频格式
    NSArray *audioExtensions = @[@"mp3", @"m4a", @"wav", @"flac", @"ncm"];
    
    NSString *audioDirectory = [[NSBundle mainBundle] pathForResource:@"Audio" ofType:nil];
    if (!audioDirectory) {
        audioDirectory = [[NSBundle mainBundle] resourcePath];
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *contents = [fileManager contentsOfDirectoryAtPath:audioDirectory error:&error];
    
    if (error) {
        NSLog(@"❌ 读取音频目录失败: %@", error.localizedDescription);
        return audioFiles;
    }
    
    NSLog(@"📂 扫描音频目录: %@", audioDirectory);
    NSLog(@"   找到 %lu 个文件", (unsigned long)contents.count);
    
    // 统计文件类型
    NSInteger ncmCount = 0;
    NSInteger mp3Count = 0;
    NSInteger otherCount = 0;
    
    for (NSString *filename in contents) {
        NSString *extension = [[filename pathExtension] lowercaseString];
        
        // 跳过 .lrc 文件
        if ([extension isEqualToString:@"lrc"]) {
            continue;
        }
        
        if ([audioExtensions containsObject:extension]) {
            if ([extension isEqualToString:@"ncm"]) {
                ncmCount++;
                NSLog(@"🔐 发现 NCM 文件: %@", filename);
            } else if ([extension isEqualToString:@"mp3"]) {
                mp3Count++;
            } else {
                otherCount++;
            }
            
            [audioFiles addObject:filename];
        }
    }
    
    NSLog(@"📊 音频文件统计:");
    NSLog(@"   MP3: %ld 个", (long)mp3Count);
    NSLog(@"   NCM: %ld 个 %@", (long)ncmCount, ncmCount > 0 ? @"(需要解密)" : @"");
    NSLog(@"   其他: %ld 个", (long)otherCount);
    NSLog(@"   总计: %lu 个", (unsigned long)audioFiles.count);
    
    // 如果有 NCM 文件，自动启动后台解密
    if (ncmCount > 0) {
        [self decryptNCMFilesInBackgroundFromDirectory:audioDirectory];
    }
    
    return [audioFiles copy];
}

+ (void)decryptNCMFilesInBackgroundFromDirectory:(NSString *)directory {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSLog(@"🔓 开始后台解密 NCM 文件...");
        NSLog(@"   源目录（只读）: %@", directory);
        
        // 获取可写的 Documents 目录
        NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSLog(@"   目标目录（可写）: %@", documentsPath);
        
        // 查找所有 NCM 文件
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSArray *files = [fileManager contentsOfDirectoryAtPath:directory error:nil];
        NSMutableArray *ncmFiles = [NSMutableArray array];
        
        for (NSString *filename in files) {
            if ([[filename.pathExtension lowercaseString] isEqualToString:@"ncm"]) {
                NSString *fullPath = [directory stringByAppendingPathComponent:filename];
                [ncmFiles addObject:fullPath];
            }
        }
        
        if (ncmFiles.count == 0) {
            NSLog(@"   未找到 NCM 文件");
            return;
        }
        
        NSLog(@"   找到 %lu 个 NCM 文件", (unsigned long)ncmFiles.count);
        
        NSInteger successCount = 0;
        
        for (NSInteger i = 0; i < ncmFiles.count; i++) {
            NSString *inputPath = ncmFiles[i];
            NSString *filename = [inputPath lastPathComponent];
            
            // 生成输出路径（在 Documents 目录）
            NSString *outputFilename = [[filename stringByDeletingPathExtension] stringByAppendingPathExtension:@"mp3"];
            NSString *outputPath = [documentsPath stringByAppendingPathComponent:outputFilename];
            
            // 检查是否已经解密过
            if ([fileManager fileExistsAtPath:outputPath]) {
                NSLog(@"   [%ld/%lu] ⏭ %@ (已存在)", (long)(i+1), (unsigned long)ncmFiles.count, filename);
                successCount++;
                continue;
            }
            
            // 解密
            NSError *error = nil;
            NSString *result = [NCMDecryptor decryptNCMFile:inputPath
                                                 outputPath:outputPath
                                                      error:&error];
            
            if (result) {
                successCount++;
                NSLog(@"   [%ld/%lu] ✅ %@", (long)(i+1), (unsigned long)ncmFiles.count, filename);
            } else {
                NSLog(@"   [%ld/%lu] ❌ %@ - %@", (long)(i+1), (unsigned long)ncmFiles.count, filename, error.localizedDescription);
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"🎉 NCM 解密完成: 成功 %ld/%lu 个文件", (long)successCount, (unsigned long)ncmFiles.count);
            
            // 发送通知，告诉 UI 更新
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NCMDecryptionCompleted" 
                                                                object:nil 
                                                              userInfo:@{@"count": @(successCount)}];
        });
    });
}

+ (NSString *)prepareAudioFileForPlayback:(NSString *)fileName {
    // 检查是否是 NCM 文件
    if ([[fileName.pathExtension lowercaseString] isEqualToString:@"ncm"]) {
        NSLog(@"🔓 准备播放 NCM 文件: %@", fileName);
        
        // 获取 NCM 文件完整路径（Bundle 中）
        NSURL *fileURL = [[NSBundle mainBundle] URLForResource:fileName withExtension:nil];
        if (!fileURL) {
            // 尝试在 Audio 目录中查找
            NSString *audioPath = [[NSBundle mainBundle] pathForResource:@"Audio" ofType:nil];
            NSString *fullPath = [audioPath stringByAppendingPathComponent:fileName];
            fileURL = [NSURL fileURLWithPath:fullPath];
        }
        
        if (!fileURL) {
            NSLog(@"❌ 找不到文件: %@", fileName);
            return fileName;
        }
        
        // 🔧 关键修复：解密后的文件保存到 Documents 目录（可写）
        NSString *decryptedFileName = [[fileName stringByDeletingPathExtension] stringByAppendingPathExtension:@"mp3"];
        NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *decryptedPath = [documentsPath stringByAppendingPathComponent:decryptedFileName];
        
        // 检查是否已经解密过
        if ([[NSFileManager defaultManager] fileExistsAtPath:decryptedPath]) {
            NSLog(@"✅ 使用已解密的文件: %@", decryptedPath);
            return decryptedPath;  // 返回完整路径
        }
        
        // 执行解密
        NSError *error = nil;
        NSString *outputPath = [NCMDecryptor decryptNCMFile:fileURL.path
                                                 outputPath:decryptedPath
                                                      error:&error];
        
        if (outputPath) {
            NSLog(@"✅ NCM 解密成功: %@", outputPath);
            return outputPath;  // 返回完整路径
        } else {
            NSLog(@"❌ NCM 解密失败: %@，尝试播放原文件", error.localizedDescription);
            return fileName;
        }
    }
    
    // 不是 NCM 文件，直接返回
    return fileName;
}

+ (BOOL)needsDecryption:(NSString *)fileName {
    return [[fileName.pathExtension lowercaseString] isEqualToString:@"ncm"];
}

@end
