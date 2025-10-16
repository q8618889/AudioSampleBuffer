////////////////////////////////////////////////////////////////////////////////
///
/// SoundTouch C Bridge - C 接口桥接层实现
/// 为 SoundTouch C++ 库提供 C 语言接口
///
/// Based on SoundTouch Audio Processing Library
/// Copyright (c) Olli Parviainen
/// License: LGPL v2.1
///
////////////////////////////////////////////////////////////////////////////////

#include "SoundTouchBridge.h"
#include "SoundTouch.h"
#include <string.h>

using namespace soundtouch;

extern "C" {

SoundTouchHandle* soundtouch_create() {
    return reinterpret_cast<SoundTouchHandle*>(new SoundTouch());
}

void soundtouch_destroy(SoundTouchHandle* handle) {
    if (handle) {
        delete reinterpret_cast<SoundTouch*>(handle);
    }
}

void soundtouch_setSampleRate(SoundTouchHandle* handle, unsigned int sampleRate) {
    if (handle) {
        reinterpret_cast<SoundTouch*>(handle)->setSampleRate(sampleRate);
    }
}

void soundtouch_setChannels(SoundTouchHandle* handle, unsigned int numChannels) {
    if (handle) {
        reinterpret_cast<SoundTouch*>(handle)->setChannels(numChannels);
    }
}

void soundtouch_setPitch(SoundTouchHandle* handle, float pitch) {
    if (handle) {
        // SoundTouch 的 setPitchSemiTones 接受半音数
        reinterpret_cast<SoundTouch*>(handle)->setPitchSemiTones(pitch);
    }
}

void soundtouch_setRate(SoundTouchHandle* handle, float rate) {
    if (handle) {
        reinterpret_cast<SoundTouch*>(handle)->setRate(rate);
    }
}

void soundtouch_setTempo(SoundTouchHandle* handle, float tempo) {
    if (handle) {
        reinterpret_cast<SoundTouch*>(handle)->setTempo(tempo);
    }
}

void soundtouch_putSamples(SoundTouchHandle* handle, const float* samples, 
                          unsigned int numSamples) {
    if (handle && samples && numSamples > 0) {
        reinterpret_cast<SoundTouch*>(handle)->putSamples(samples, numSamples);
    }
}

unsigned int soundtouch_receiveSamples(SoundTouchHandle* handle, float* outBuffer, 
                                       unsigned int maxSamples) {
    if (!handle || !outBuffer) {
        return 0;
    }
    return reinterpret_cast<SoundTouch*>(handle)->receiveSamples(outBuffer, maxSamples);
}

void soundtouch_flush(SoundTouchHandle* handle) {
    if (handle) {
        reinterpret_cast<SoundTouch*>(handle)->flush();
    }
}

void soundtouch_clear(SoundTouchHandle* handle) {
    if (handle) {
        reinterpret_cast<SoundTouch*>(handle)->clear();
    }
}

unsigned int soundtouch_numSamples(SoundTouchHandle* handle) {
    if (!handle) {
        return 0;
    }
    return reinterpret_cast<SoundTouch*>(handle)->numSamples();
}

int soundtouch_isEmpty(SoundTouchHandle* handle) {
    if (!handle) {
        return 1;
    }
    return reinterpret_cast<SoundTouch*>(handle)->isEmpty() ? 1 : 0;
}

const char* soundtouch_getVersionString() {
    return SoundTouch::getVersionString();
}

unsigned int soundtouch_getVersionId() {
    return SoundTouch::getVersionId();
}

void soundtouch_setSetting(SoundTouchHandle* handle, int settingId, int value) {
    if (handle) {
        reinterpret_cast<SoundTouch*>(handle)->setSetting(settingId, value);
    }
}

int soundtouch_getSetting(SoundTouchHandle* handle, int settingId) {
    if (!handle) {
        return 0;
    }
    return reinterpret_cast<SoundTouch*>(handle)->getSetting(settingId);
}

} // extern "C"

