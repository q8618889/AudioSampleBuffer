/* SpeexDSP iOS/macOS 配置文件 */
#ifndef CONFIG_H
#define CONFIG_H

/* 核心配置 - 浮点运算 */
#ifndef FLOATING_POINT
#define FLOATING_POINT 1
#endif

/* 使用 Kiss FFT */
#ifndef USE_KISS_FFT
#define USE_KISS_FFT 1
#endif

/* 导出符号 */
#ifndef EXPORT
#define EXPORT __attribute__((visibility("default")))
#endif

/* 采样率转换 */
#define RESAMPLE_FULL_SINC_TABLE 1

/* 基础类型定义 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#endif /* CONFIG_H */
