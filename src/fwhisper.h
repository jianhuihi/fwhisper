#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#if _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

#ifndef FLUTTER_WHISPER_CPP_H
#define FLUTTER_WHISPER_CPP_H

#include <stddef.h>

#define COMMON_SAMPLE_RATE 16000
#define MAX_PCMF32_LENGTH 1000000

// 根据不同平台定义 FFI_PLUGIN_EXPORT 宏
#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#elif defined(__APPLE__)
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FFI_PLUGIN_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

FFI_PLUGIN_EXPORT int read_wav(const char *fname, float *pcmf32, size_t *pcmf32_length, int stereo);
FFI_PLUGIN_EXPORT bool c_read_wav(const char* fname, float* pcmf32, size_t* pcmf32_len, float** pcmf32s, size_t* pcmf32s_len, bool stereo);


#ifdef __cplusplus
}
#endif

#endif // FLUTTER_WHISPER_CPP_H
