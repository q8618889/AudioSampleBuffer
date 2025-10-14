//
//  AudioMixer.m
//  AudioSampleBuffer
//
//  Created on 2025/10/14.
//

#import "AudioMixer.h"
#import <AVFoundation/AVFoundation.h>

@implementation AudioMixer

+ (void)mixVocalFile:(NSString *)vocalPath
         withBGMFile:(NSString *)bgmPath
        outputToFile:(NSString *)outputPath
         vocalVolume:(float)vocalVolume
           bgmVolume:(float)bgmVolume
          completion:(void(^)(BOOL success, NSError * _Nullable error))completion {
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSLog(@"🎵 开始混音 (使用AVAssetExportSession - 无损格式):");
        NSLog(@"   人声: %@", vocalPath);
        NSLog(@"   BGM: %@", bgmPath);
        NSLog(@"   输出: %@", outputPath);
        NSLog(@"   人声音量: %.0f%%", vocalVolume * 100);
        NSLog(@"   BGM音量: %.0f%%", bgmVolume * 100);
        
        // 🆕 使用 AVAssetExportSession 进行原生格式混音（不转换，精确时长）
        NSError *error = nil;
        
        // 1. 将人声PCM转换为临时M4A文件（只转换人声，BGM保持原格式）
        NSString *tempVocalM4A = [NSTemporaryDirectory() stringByAppendingPathComponent:@"temp_vocal.m4a"];
        BOOL vocalConverted = [self convertPCMToM4A:vocalPath outputPath:tempVocalM4A error:&error];
        
        if (!vocalConverted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, error);
            });
            return;
        }
        
        // 2. 创建AVAsset
        AVURLAsset *vocalAsset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:tempVocalM4A] options:nil];
        AVURLAsset *bgmAsset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:bgmPath] options:nil];
        
        // 3. 创建AVMutableComposition
        AVMutableComposition *composition = [AVMutableComposition composition];
        
        // 4. 添加人声轨道
        AVMutableCompositionTrack *vocalTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio
                                                                        preferredTrackID:kCMPersistentTrackID_Invalid];
        AVAssetTrack *vocalAssetTrack = [[vocalAsset tracksWithMediaType:AVMediaTypeAudio] firstObject];
        
        if (vocalAssetTrack) {
            [vocalTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, vocalAsset.duration)
                                ofTrack:vocalAssetTrack
                                 atTime:kCMTimeZero
                                  error:&error];
        }
        
        // 5. 添加BGM轨道
        AVMutableCompositionTrack *bgmTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio
                                                                      preferredTrackID:kCMPersistentTrackID_Invalid];
        AVAssetTrack *bgmAssetTrack = [[bgmAsset tracksWithMediaType:AVMediaTypeAudio] firstObject];
        
        if (bgmAssetTrack) {
            [bgmTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, bgmAsset.duration)
                              ofTrack:bgmAssetTrack
                               atTime:kCMTimeZero
                                error:&error];
        }
        
        // 6. 设置音量参数
        AVMutableAudioMixInputParameters *vocalMixParams = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:vocalTrack];
        [vocalMixParams setVolume:vocalVolume atTime:kCMTimeZero];
        
        AVMutableAudioMixInputParameters *bgmMixParams = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:bgmTrack];
        [bgmMixParams setVolume:bgmVolume atTime:kCMTimeZero];
        
        AVMutableAudioMix *audioMix = [AVMutableAudioMix audioMix];
        audioMix.inputParameters = @[vocalMixParams, bgmMixParams];
        
        // 7. 导出混音结果
        // 先导出为M4A，然后转换为PCM
        NSString *tempM4APath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"temp_mixed.m4a"];
        [[NSFileManager defaultManager] removeItemAtPath:tempM4APath error:nil];
        
        AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:composition
                                                                               presetName:AVAssetExportPresetAppleM4A];
        exportSession.audioMix = audioMix;
        exportSession.outputURL = [NSURL fileURLWithPath:tempM4APath];
        exportSession.outputFileType = AVFileTypeAppleM4A;
        
        NSLog(@"🔄 开始导出混音文件...");
        [exportSession exportAsynchronouslyWithCompletionHandler:^{
            if (exportSession.status == AVAssetExportSessionStatusCompleted) {
                NSLog(@"✅ 混音导出成功，转换为PCM格式");
                
                // 将M4A转换为PCM格式（用于播放器）
                NSData *pcmData = [self convertAudioFileToPCM:tempM4APath];
                
                if (pcmData) {
                    BOOL success = [pcmData writeToFile:outputPath atomically:YES];
                    
                    // 清理临时文件
                    [[NSFileManager defaultManager] removeItemAtPath:tempVocalM4A error:nil];
                    [[NSFileManager defaultManager] removeItemAtPath:tempM4APath error:nil];
                    
                    if (success) {
                        NSLog(@"✅ 混音完成! 文件大小: %.2f MB", pcmData.length / (1024.0 * 1024.0));
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (completion) completion(YES, nil);
                        });
                    } else {
                        NSError *writeError = [NSError errorWithDomain:@"AudioMixer" code:3 userInfo:@{NSLocalizedDescriptionKey: @"写入混音文件失败"}];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (completion) completion(NO, writeError);
                        });
                    }
                } else {
                    NSError *convError = [NSError errorWithDomain:@"AudioMixer" code:4 userInfo:@{NSLocalizedDescriptionKey: @"转换PCM失败"}];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completion) completion(NO, convError);
                    });
                }
                
            } else {
                NSLog(@"❌ 混音导出失败: %@", exportSession.error);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(NO, exportSession.error);
                });
            }
        }];
    });
}

+ (NSData *)convertAudioFileToPCM:(NSString *)audioFilePath {
    NSURL *audioURL = [NSURL fileURLWithPath:audioFilePath];
    
    // 打开音频文件
    AVAudioFile *audioFile = [[AVAudioFile alloc] initForReading:audioURL error:nil];
    if (!audioFile) {
        NSLog(@"❌ 无法打开音频文件: %@", audioFilePath);
        return nil;
    }
    
    // 设置PCM格式 (44.1kHz, 单声道, 16bit)
    AVAudioFormat *pcmFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16
                                                                sampleRate:44100.0
                                                                  channels:1
                                                               interleaved:YES];
    
    // 创建音频转换器
    AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:audioFile.processingFormat
                                                                   toFormat:pcmFormat];
    if (!converter) {
        NSLog(@"❌ 无法创建音频转换器");
        return nil;
    }
    
    // 准备输出缓冲区
    NSMutableData *pcmData = [NSMutableData data];
    AVAudioFrameCount frameCapacity = 4096;
    
    // 读取并转换
    while (audioFile.framePosition < audioFile.length) {
        AVAudioPCMBuffer *inputBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:audioFile.processingFormat
                                                                       frameCapacity:frameCapacity];
        
        // 读取音频数据
        NSError *readError = nil;
        [audioFile readIntoBuffer:inputBuffer error:&readError];
        
        if (readError || inputBuffer.frameLength == 0) {
            break;
        }
        
        // 转换为PCM
        AVAudioPCMBuffer *outputBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:pcmFormat
                                                                        frameCapacity:frameCapacity];
        
        // 🔧 修复：使用__block变量确保可以被多次访问
        __block BOOL inputProvided = NO;
        AVAudioConverterInputBlock inputBlock = ^AVAudioBuffer *(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus *outStatus) {
            if (!inputProvided) {
                inputProvided = YES;
                *outStatus = AVAudioConverterInputStatus_HaveData;
                return inputBuffer;
            } else {
                *outStatus = AVAudioConverterInputStatus_NoDataNow;
                return nil;
            }
        };
        
        NSError *error;
        AVAudioConverterOutputStatus status = [converter convertToBuffer:outputBuffer
                                                                    error:&error
                                                   withInputFromBlock:inputBlock];
        
        // 🔧 关键修复：只要有输出数据就保存，不管状态
        if (outputBuffer.frameLength > 0) {
            const int16_t *samples = (const int16_t *)outputBuffer.audioBufferList->mBuffers[0].mData;
            NSUInteger length = outputBuffer.frameLength * sizeof(int16_t);
            if (samples && length > 0) {
                [pcmData appendBytes:samples length:length];
            }
        }
        
        if (status == AVAudioConverterOutputStatus_Error) {
            NSLog(@"❌ 转换错误: %@", error);
        }
    }
    
    NSLog(@"✅ BGM转换完成: %.2f MB", pcmData.length / (1024.0 * 1024.0));
    return pcmData;
}

+ (NSData *)mixVocalData:(NSData *)vocalData
             withBGMData:(NSData *)bgmData
             vocalVolume:(float)vocalVolume
               bgmVolume:(float)bgmVolume {
    
    // 获取样本数
    NSUInteger vocalSampleCount = vocalData.length / sizeof(int16_t);
    NSUInteger bgmSampleCount = bgmData.length / sizeof(int16_t);
    NSUInteger maxSampleCount = MAX(vocalSampleCount, bgmSampleCount);
    
    // 准备输出缓冲区
    NSMutableData *mixedData = [NSMutableData dataWithLength:maxSampleCount * sizeof(int16_t)];
    
    const int16_t *vocalSamples = (const int16_t *)vocalData.bytes;
    const int16_t *bgmSamples = (const int16_t *)bgmData.bytes;
    int16_t *mixedSamples = (int16_t *)mixedData.mutableBytes;
    
    NSLog(@"🎵 混音中: 人声样本数=%lu, BGM样本数=%lu", (unsigned long)vocalSampleCount, (unsigned long)bgmSampleCount);
    
    // 混音
    for (NSUInteger i = 0; i < maxSampleCount; i++) {
        int32_t vocalSample = 0;
        int32_t bgmSample = 0;
        
        // 获取人声样本
        if (i < vocalSampleCount) {
            vocalSample = (int32_t)(vocalSamples[i] * vocalVolume);
        }
        
        // 获取BGM样本
        if (i < bgmSampleCount) {
            bgmSample = (int32_t)(bgmSamples[i] * bgmVolume);
        }
        
        // 混合（相加）
        int32_t mixed = vocalSample + bgmSample;
        
        // 防止溢出
        if (mixed > 32767) {
            mixed = 32767;
        } else if (mixed < -32768) {
            mixed = -32768;
        }
        
        mixedSamples[i] = (int16_t)mixed;
    }
    
    return mixedData;
}

#pragma mark - PCM转M4A辅助方法

+ (BOOL)convertPCMToM4A:(NSString *)pcmPath
            outputPath:(NSString *)m4aPath
                 error:(NSError **)error {
    
    NSLog(@"🔄 将PCM转换为M4A: %@ -> %@", pcmPath, m4aPath);
    
    // 读取PCM数据
    NSData *pcmData = [NSData dataWithContentsOfFile:pcmPath];
    if (!pcmData) {
        if (error) {
            *error = [NSError errorWithDomain:@"AudioMixer" code:5 userInfo:@{NSLocalizedDescriptionKey: @"无法读取PCM文件"}];
        }
        return NO;
    }
    
    // 设置PCM格式 (44.1kHz, 单声道, 16bit)
    AudioStreamBasicDescription pcmFormat = {0};
    pcmFormat.mSampleRate = 44100.0;
    pcmFormat.mFormatID = kAudioFormatLinearPCM;
    pcmFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    pcmFormat.mBytesPerPacket = 2;
    pcmFormat.mFramesPerPacket = 1;
    pcmFormat.mBytesPerFrame = 2;
    pcmFormat.mChannelsPerFrame = 1;
    pcmFormat.mBitsPerChannel = 16;
    
    AVAudioFormat *inputFormat = [[AVAudioFormat alloc] initWithStreamDescription:&pcmFormat];
    
    // 设置AAC输出格式
    AudioStreamBasicDescription aacFormat = {0};
    aacFormat.mSampleRate = 44100.0;
    aacFormat.mFormatID = kAudioFormatMPEG4AAC;
    aacFormat.mChannelsPerFrame = 1;
    
    AVAudioFormat *outputFormat = [[AVAudioFormat alloc] initWithStreamDescription:&aacFormat];
    
    // 创建临时输出文件
    [[NSFileManager defaultManager] removeItemAtPath:m4aPath error:nil];
    
    AVAudioFile *outputFile = [[AVAudioFile alloc] initForWriting:[NSURL fileURLWithPath:m4aPath]
                                                          settings:outputFormat.settings
                                                      commonFormat:AVAudioPCMFormatFloat32
                                                       interleaved:NO
                                                             error:error];
    if (*error || !outputFile) {
        NSLog(@"❌ 创建输出文件失败: %@", *error);
        return NO;
    }
    
    // 创建转换器
    AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:inputFormat toFormat:outputFormat];
    if (!converter) {
        if (error) {
            *error = [NSError errorWithDomain:@"AudioMixer" code:6 userInfo:@{NSLocalizedDescriptionKey: @"创建音频转换器失败"}];
        }
        return NO;
    }
    
    // 转换并写入
    const int16_t *pcmSamples = (const int16_t *)pcmData.bytes;
    NSUInteger totalFrames = pcmData.length / sizeof(int16_t);
    NSUInteger frameIndex = 0;
    AVAudioFrameCount frameCapacity = 4096;
    
    while (frameIndex < totalFrames) {
        AVAudioFrameCount framesToRead = MIN(frameCapacity, (AVAudioFrameCount)(totalFrames - frameIndex));
        
        // 创建输入缓冲区
        AVAudioPCMBuffer *inputBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:inputFormat
                                                                       frameCapacity:frameCapacity];
        inputBuffer.frameLength = framesToRead;
        
        // 填充输入数据
        int16_t *inputData = inputBuffer.int16ChannelData[0];
        memcpy(inputData, &pcmSamples[frameIndex], framesToRead * sizeof(int16_t));
        
        // 创建输出缓冲区
        AVAudioPCMBuffer *outputBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:outputFormat
                                                                        frameCapacity:frameCapacity];
        
        // 转换
        __block BOOL inputProvided = NO;
        AVAudioConverterInputBlock inputBlock = ^AVAudioBuffer *(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus *outStatus) {
            if (!inputProvided) {
                inputProvided = YES;
                *outStatus = AVAudioConverterInputStatus_HaveData;
                return inputBuffer;
            } else {
                *outStatus = AVAudioConverterInputStatus_NoDataNow;
                return nil;
            }
        };
        
        AVAudioConverterOutputStatus status = [converter convertToBuffer:outputBuffer
                                                                    error:error
                                                   withInputFromBlock:inputBlock];
        
        if (status == AVAudioConverterOutputStatus_Error) {
            NSLog(@"❌ 转换失败: %@", *error);
            return NO;
        }
        
        if (status == AVAudioConverterOutputStatus_HaveData && outputBuffer.frameLength > 0) {
            [outputFile writeFromBuffer:outputBuffer error:error];
            if (*error) {
                NSLog(@"❌ 写入文件失败: %@", *error);
                return NO;
            }
        } else if (status == AVAudioConverterOutputStatus_InputRanDry) {
            // 输入数据用完，继续下一批
            continue;
        }
        
        frameIndex += framesToRead;
    }
    
    NSLog(@"✅ PCM转M4A成功");
    return YES;
}

@end

