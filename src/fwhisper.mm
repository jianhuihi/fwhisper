#include "fwhisper.h"

#include "whisper.cpp/whisper.h"

#define DR_WAV_IMPLEMENTATION
#include "whisper.cpp/examples/dr_wav.h"
//#include "whisper.cpp/examples/common.h"

#include <cmath>
#include <cstring>
#include <fstream>
#include <regex>
#include <locale>
#include <codecvt>
#include <sstream>
#include <iostream>


#include <string>
#include <map>
#include <vector>
#include <random>
#include <thread>
#include <ctime>
#include <fstream>



bool read_wav(const std::string & fname, std::vector<float>& pcmf32, std::vector<std::vector<float>>& pcmf32s, bool stereo) {
    drwav wav;
    std::vector<uint8_t> wav_data; // used for pipe input from stdin

    if (fname == "-") {
        {
            uint8_t buf[1024];
            while (true)
            {
                const size_t n = fread(buf, 1, sizeof(buf), stdin);
                if (n == 0) {
                    break;
                }
                wav_data.insert(wav_data.end(), buf, buf + n);
            }
        }

        if (drwav_init_memory(&wav, wav_data.data(), wav_data.size(), nullptr) == false) {
            fprintf(stderr, "error: failed to open WAV file from stdin\n");
            return false;
        }

        fprintf(stderr, "%s: read %zu bytes from stdin\n", __func__, wav_data.size());
    }
    else if (fname.size() > 256 || (fname.size() > 40 && fname.substr(0, 4) == "RIFF" && fname.substr(8, 4) == "WAVE")) {
        if (drwav_init_memory(&wav, fname.c_str(), fname.size(), nullptr) == false) {
            fprintf(stderr, "error: failed to open WAV file from fname buffer\n");
            return false;
        }
    }
    else if (drwav_init_file(&wav, fname.c_str(), nullptr) == false) {
        fprintf(stderr, "error: failed to open '%s' as WAV file\n", fname.c_str());
        return false;
    }

    if (wav.channels != 1 && wav.channels != 2) {
        fprintf(stderr, "%s: WAV file '%s' must be mono or stereo\n", __func__, fname.c_str());
        return false;
    }

    if (stereo && wav.channels != 2) {
        fprintf(stderr, "%s: WAV file '%s' must be stereo for diarization\n", __func__, fname.c_str());
        return false;
    }

    if (wav.sampleRate != COMMON_SAMPLE_RATE) {
        fprintf(stderr, "%s: WAV file '%s' must be %i kHz\n", __func__, fname.c_str(), COMMON_SAMPLE_RATE/1000);
        return false;
    }

    if (wav.bitsPerSample != 16) {
        fprintf(stderr, "%s: WAV file '%s' must be 16-bit\n", __func__, fname.c_str());
        return false;
    }

    const uint64_t n = wav_data.empty() ? wav.totalPCMFrameCount : wav_data.size()/(wav.channels*wav.bitsPerSample/8);

    std::vector<int16_t> pcm16;
    pcm16.resize(n*wav.channels);
    drwav_read_pcm_frames_s16(&wav, n, pcm16.data());
    drwav_uninit(&wav);

    // convert to mono, float

    std::cout << "C++: wav.channels: " << wav.channels << std::endl;

    pcmf32.resize(n);
    if (wav.channels == 1) {
        for (uint64_t i = 0; i < n; i++) {
            pcmf32[i] = float(pcm16[i])/32768.0f;
        }
    } else {
        for (uint64_t i = 0; i < n; i++) {
            pcmf32[i] = float(pcm16[2*i] + pcm16[2*i + 1])/65536.0f;
        }
    }

    if (stereo) {
        // convert to stereo, float
        pcmf32s.resize(2);

        pcmf32s[0].resize(n);
        pcmf32s[1].resize(n);
        for (uint64_t i = 0; i < n; i++) {
            pcmf32s[0][i] = float(pcm16[2*i])/32768.0f;
            pcmf32s[1][i] = float(pcm16[2*i + 1])/32768.0f;
        }
    }

    return true;
}


extern "C" {
    bool c_read_wav(const char* fname, float* pcmf32, size_t* pcmf32_len, float** pcmf32s, size_t* pcmf32s_len, bool stereo) {
        std::string fname_str(fname);
        std::vector<float> pcmf32_vec;
        std::vector<std::vector<float>> pcmf32s_vec;        
        // 调用原始的C++函数
        bool result = read_wav(fname_str, pcmf32_vec, pcmf32s_vec, stereo);
        
        // std::cout << "C++: pcmf32_vec size: " << pcmf32_vec.size() << std::endl;

        // 检查结果
        if (!result) {
            return false;
        }
        
        // std::cout << "C++: pcmf32_vec first 10 elements:" << std::endl;
        // size_t numElementsToPrint = std::min(pcmf32_vec.size(), size_t(10000));
        // for (size_t i = 0; i < numElementsToPrint; ++i) {
        //     std::cout << pcmf32_vec[i] << " ";
        // }
        // std::cout << std::endl;

        // 复制数据到提供的数组中
        if (pcmf32 != nullptr && pcmf32_len != nullptr) {
            std::memcpy(pcmf32, pcmf32_vec.data(), pcmf32_vec.size() * sizeof(float));
            *pcmf32_len = pcmf32_vec.size();
        }

        // 对于双声道数据的处理
        if (stereo && pcmf32s != nullptr && pcmf32s_len != nullptr) {
            for (size_t i = 0; i < pcmf32s_vec.size(); i++) {
                std::memcpy(pcmf32s[i], pcmf32s_vec[i].data(), pcmf32s_vec[i].size() * sizeof(float));
            }
            *pcmf32s_len = pcmf32s_vec.size();
        }

        // if (pcmf32_len != nullptr) {
        //     std::cout << "C++: pcmf32_len address: " << pcmf32_len << ", value: " << *pcmf32_len << std::endl;
        // } else {
        //     std::cerr << "C++: Error - pcmf32_len is a null pointer." << std::endl;
        // }
        // // 示例：打印修改后的前10个元素
        // std::cout << "C++: pcmf32 after modification:" << std::endl;
        // for (size_t i = 0; i < *pcmf32_len && i < 10000; ++i) {
        //     std::cout << pcmf32[i] << " ";
        // }
        // std::cout << std::endl;

        return true;
    }
}
