////////////////////////////////////////////////////////////////////////////////
///
/// SoundTouch - 音高和速度调整库 (简化实现)
///
////////////////////////////////////////////////////////////////////////////////

#include "SoundTouch.h"
#include <math.h>
#include <string.h>
#include <stdlib.h>
#include <algorithm>
#include <vector>

#define MAX_BUFFER_SIZE 8192
#define OVERLAP_SIZE 1024

struct SoundTouchHandle {
    unsigned int sampleRate;
    unsigned int channels;
    float pitchShift;      // 半音数
    float rateChange;      // 速度变化
    float tempoChange;     // 节奏变化
    
    std::vector<float> inputBuffer;
    std::vector<float> outputBuffer;
    
    float phaseAccumulator;
    int outputPos;
    int inputPos;
};

extern "C" {

SoundTouchHandle* soundtouch_create() {
    SoundTouchHandle* handle = new SoundTouchHandle();
    handle->sampleRate = 44100;
    handle->channels = 1;
    handle->pitchShift = 0.0f;
    handle->rateChange = 1.0f;
    handle->tempoChange = 1.0f;
    handle->phaseAccumulator = 0.0f;
    handle->outputPos = 0;
    handle->inputPos = 0;
    return handle;
}

void soundtouch_destroy(SoundTouchHandle* handle) {
    if (handle) {
        delete handle;
    }
}

void soundtouch_setSampleRate(SoundTouchHandle* handle, unsigned int sampleRate) {
    if (handle) {
        handle->sampleRate = sampleRate;
    }
}

void soundtouch_setChannels(SoundTouchHandle* handle, unsigned int numChannels) {
    if (handle) {
        handle->channels = numChannels;
    }
}

void soundtouch_setPitch(SoundTouchHandle* handle, float pitch) {
    if (handle) {
        // 限制音高范围 -12 到 +12 半音
        handle->pitchShift = std::max(-12.0f, std::min(12.0f, pitch));
    }
}

void soundtouch_setRate(SoundTouchHandle* handle, float rate) {
    if (handle) {
        handle->rateChange = std::max(0.5f, std::min(2.0f, rate));
    }
}

void soundtouch_setTempo(SoundTouchHandle* handle, float tempo) {
    if (handle) {
        handle->tempoChange = std::max(0.5f, std::min(2.0f, tempo));
    }
}

// 简化的音高变换算法（保持样本数不变，避免同步问题）
static void applyPitchShiftInPlace(SoundTouchHandle* handle, float* buffer, unsigned int numSamples) {
    // 音高变化因子：2^(半音/12)
    float pitchRatio = powf(2.0f, handle->pitchShift / 12.0f);
    
    // 反向比率（用于读取位置）
    float readRatio = 1.0f / pitchRatio;
    
    unsigned int channels = handle->channels;
    
    // 临时缓冲区
    std::vector<float> temp(numSamples * channels);
    memcpy(&temp[0], buffer, numSamples * channels * sizeof(float));
    
    // 重采样，保持输出样本数不变
    for (unsigned int i = 0; i < numSamples; i++) {
        // 计算源样本位置
        float srcPos = i * readRatio;
        int srcIndex = (int)srcPos;
        float frac = srcPos - srcIndex;
        
        if (srcIndex < (int)numSamples - 1) {
            // 线性插值
            for (unsigned int ch = 0; ch < channels; ch++) {
                int idx1 = srcIndex * channels + ch;
                int idx2 = (srcIndex + 1) * channels + ch;
                buffer[i * channels + ch] = temp[idx1] * (1.0f - frac) + temp[idx2] * frac;
            }
        } else if (srcIndex < (int)numSamples) {
            // 最后一个样本
            for (unsigned int ch = 0; ch < channels; ch++) {
                buffer[i * channels + ch] = temp[srcIndex * channels + ch];
            }
        } else {
            // 超出范围，填充最后的样本
            for (unsigned int ch = 0; ch < channels; ch++) {
                buffer[i * channels + ch] = temp[(numSamples - 1) * channels + ch];
            }
        }
    }
}

void soundtouch_putSamples(SoundTouchHandle* handle, const float* samples, 
                          unsigned int numSamples) {
    if (!handle || !samples || numSamples == 0) return;
    
    unsigned int channels = handle->channels;
    unsigned int totalFloats = numSamples * channels;
    
    // 直接处理，不使用缓冲区（实时模式）
    handle->outputBuffer.resize(totalFloats);
    memcpy(&handle->outputBuffer[0], samples, totalFloats * sizeof(float));
    
    // 就地应用音高变换
    if (handle->pitchShift != 0.0f) {
        applyPitchShiftInPlace(handle, &handle->outputBuffer[0], numSamples);
    }
}

unsigned int soundtouch_receiveSamples(SoundTouchHandle* handle, float* outBuffer, 
                                       unsigned int maxSamples) {
    if (!handle || !outBuffer) return 0;
    
    unsigned int channels = handle->channels;
    unsigned int availableSamples = handle->outputBuffer.size() / channels;
    unsigned int samplesToReturn = std::min(maxSamples, availableSamples);
    
    if (samplesToReturn > 0) {
        unsigned int totalFloats = samplesToReturn * channels;
        memcpy(outBuffer, &handle->outputBuffer[0], totalFloats * sizeof(float));
        
        // 移除已返回的样本
        handle->outputBuffer.erase(handle->outputBuffer.begin(), 
                                   handle->outputBuffer.begin() + totalFloats);
    }
    
    return samplesToReturn;
}

void soundtouch_flush(SoundTouchHandle* handle) {
    if (!handle) return;
    // 实时模式下不需要 flush
}

void soundtouch_clear(SoundTouchHandle* handle) {
    if (!handle) return;
    
    handle->inputBuffer.clear();
    handle->outputBuffer.clear();
    handle->phaseAccumulator = 0.0f;
    handle->outputPos = 0;
    handle->inputPos = 0;
}

unsigned int soundtouch_numSamples(SoundTouchHandle* handle) {
    if (!handle) return 0;
    return handle->outputBuffer.size() / handle->channels;
}

int soundtouch_isEmpty(SoundTouchHandle* handle) {
    if (!handle) return 1;
    return handle->outputBuffer.empty() ? 1 : 0;
}

} // extern "C"

