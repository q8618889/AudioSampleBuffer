//
//  AudioMixer.h
//  AudioSampleBuffer
//
//  Created on 2025/10/14.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AudioMixer : NSObject

/**
 * 混合两个PCM文件
 * @param vocalPath 人声PCM文件路径
 * @param bgmPath BGM音频文件路径（支持mp3, m4a等）
 * @param outputPath 输出的混合PCM文件路径
 * @param vocalVolume 人声音量 (0.0 - 1.0)
 * @param bgmVolume BGM音量 (0.0 - 1.0)
 * @param completion 完成回调
 */
+ (void)mixVocalFile:(NSString *)vocalPath
         withBGMFile:(NSString *)bgmPath
        outputToFile:(NSString *)outputPath
         vocalVolume:(float)vocalVolume
           bgmVolume:(float)bgmVolume
          completion:(void(^)(BOOL success, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END

