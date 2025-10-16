////////////////////////////////////////////////////////////////////////////////
///
/// SoundTouch C Bridge - C 接口桥接层
/// 为 SoundTouch C++ 库提供 C 语言接口
///
/// Based on SoundTouch Audio Processing Library
/// Copyright (c) Olli Parviainen
/// License: LGPL v2.1
///
////////////////////////////////////////////////////////////////////////////////

#ifndef SOUNDTOUCH_BRIDGE_H
#define SOUNDTOUCH_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SoundTouchHandle SoundTouchHandle;

/**
 * 创建 SoundTouch 实例
 */
SoundTouchHandle* soundtouch_create(void);

/**
 * 销毁 SoundTouch 实例
 */
void soundtouch_destroy(SoundTouchHandle* handle);

/**
 * 设置采样率
 */
void soundtouch_setSampleRate(SoundTouchHandle* handle, unsigned int sampleRate);

/**
 * 设置声道数 (1=单声道, 2=立体声)
 */
void soundtouch_setChannels(SoundTouchHandle* handle, unsigned int numChannels);

/**
 * 设置音高变化（半音）
 * @param pitch 半音数，范围 -12.0 到 +12.0
 *              0 = 不变，+1 = 升高一个半音，-1 = 降低一个半音
 */
void soundtouch_setPitch(SoundTouchHandle* handle, float pitch);

/**
 * 设置速度变化比率
 * @param rate 速度比率，范围 0.5 到 2.0
 *             1.0 = 原速，2.0 = 2倍速，0.5 = 半速
 */
void soundtouch_setRate(SoundTouchHandle* handle, float rate);

/**
 * 设置节奏变化（不改变音高）
 * @param tempo 节奏比率，范围 0.5 to 2.0
 *              1.0 = 原节奏
 */
void soundtouch_setTempo(SoundTouchHandle* handle, float tempo);

/**
 * 添加待处理的样本
 * @param samples 样本缓冲区（交错格式，例如 LRLRLR...）
 * @param numSamples 每个声道的样本数
 */
void soundtouch_putSamples(SoundTouchHandle* handle, const float* samples, unsigned int numSamples);

/**
 * 接收处理后的样本
 * @param outBuffer 输出缓冲区
 * @param maxSamples 最大接收样本数（每个声道）
 * @return 实际接收到的样本数
 */
unsigned int soundtouch_receiveSamples(SoundTouchHandle* handle, float* outBuffer, unsigned int maxSamples);

/**
 * 刷新缓冲区，获取所有待处理的样本
 */
void soundtouch_flush(SoundTouchHandle* handle);

/**
 * 清空内部缓冲区
 */
void soundtouch_clear(SoundTouchHandle* handle);

/**
 * 检查可用的处理后样本数
 */
unsigned int soundtouch_numSamples(SoundTouchHandle* handle);

/**
 * 检查是否还有未处理的样本
 */
int soundtouch_isEmpty(SoundTouchHandle* handle);

/**
 * 获取版本信息
 */
const char* soundtouch_getVersionString(void);

/**
 * 获取版本 ID
 */
unsigned int soundtouch_getVersionId(void);

/**
 * 设置参数
 * @param settingId 设置 ID (见 SETTING_* 常量)
 * @param value 设置值
 */
void soundtouch_setSetting(SoundTouchHandle* handle, int settingId, int value);

/**
 * 获取参数
 */
int soundtouch_getSetting(SoundTouchHandle* handle, int settingId);

// 设置 ID 常量
#define SETTING_USE_AA_FILTER       0
#define SETTING_AA_FILTER_LENGTH    1
#define SETTING_USE_QUICKSEEK       2
#define SETTING_SEQUENCE_MS         3
#define SETTING_SEEKWINDOW_MS       4
#define SETTING_OVERLAP_MS          5

#ifdef __cplusplus
}
#endif

#endif // SOUNDTOUCH_BRIDGE_H

