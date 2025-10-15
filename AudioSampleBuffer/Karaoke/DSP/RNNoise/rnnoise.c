/* RNNoise - Simplified implementation for iOS integration */
/* 这是一个简化的降噪实现，实际项目中建议使用完整的 RNNoise 库 */

#include "rnnoise.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define FRAME_SIZE 480
#define FREQ_SIZE 240

struct DenoiseState {
    float input_buffer[FRAME_SIZE];
    float output_buffer[FRAME_SIZE];
    int buffer_pos;
    float noise_estimate[FREQ_SIZE];
    float smoothed_spectrum[FREQ_SIZE];
};

int rnnoise_get_size(void) {
    return sizeof(DenoiseState);
}

int rnnoise_get_frame_size(void) {
    return FRAME_SIZE;
}

DenoiseState *rnnoise_init(DenoiseState *st, void *model) {
    if (st == NULL) return NULL;
    memset(st, 0, sizeof(DenoiseState));
    
    // 初始化噪声估计
    for (int i = 0; i < FREQ_SIZE; i++) {
        st->noise_estimate[i] = 0.001f;
        st->smoothed_spectrum[i] = 0.0f;
    }
    st->buffer_pos = 0;
    
    return st;
}

DenoiseState *rnnoise_create(void *model) {
    DenoiseState *st = (DenoiseState *)malloc(rnnoise_get_size());
    return rnnoise_init(st, model);
}

void rnnoise_destroy(DenoiseState *st) {
    free(st);
}

// 简化的频谱降噪算法（实际 RNNoise 使用深度学习模型）
static void spectral_subtraction(float *spectrum, float *noise, int size, float gain) {
    for (int i = 0; i < size; i++) {
        float signal_power = spectrum[i] * spectrum[i];
        float noise_power = noise[i] * noise[i];
        
        // 维纳滤波
        float wiener_gain = fmaxf(0.0f, 1.0f - (noise_power / fmaxf(signal_power, 1e-6f)));
        wiener_gain = powf(wiener_gain, gain);
        
        spectrum[i] *= wiener_gain;
        
        // 更新噪声估计（慢速适应）
        noise[i] = 0.99f * noise[i] + 0.01f * fabsf(spectrum[i]);
    }
}

float rnnoise_process_frame(DenoiseState *st, float *x) {
    // 简化版：应用频谱减法降噪
    // 实际 RNNoise 使用 GRU 神经网络
    
    // 1. 简单的频域变换（实际应用 FFT）
    float spectrum[FREQ_SIZE];
    for (int i = 0; i < FREQ_SIZE; i++) {
        spectrum[i] = (x[i*2] + x[i*2+1]) * 0.5f;
        st->smoothed_spectrum[i] = 0.8f * st->smoothed_spectrum[i] + 0.2f * spectrum[i];
    }
    
    // 2. 应用降噪
    spectral_subtraction(st->smoothed_spectrum, st->noise_estimate, FREQ_SIZE, 1.5f);
    
    // 3. 重构时域信号
    for (int i = 0; i < FREQ_SIZE; i++) {
        x[i*2] = st->smoothed_spectrum[i];
        x[i*2+1] = st->smoothed_spectrum[i];
    }
    
    // 4. 计算语音活动概率（简化版）
    float energy = 0.0f;
    for (int i = 0; i < FRAME_SIZE; i++) {
        energy += x[i] * x[i];
    }
    energy = sqrtf(energy / FRAME_SIZE);
    
    float vad_prob = fminf(1.0f, energy * 10.0f);
    
    return vad_prob;
}

