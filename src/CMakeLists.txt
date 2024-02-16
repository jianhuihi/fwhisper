cmake_minimum_required(VERSION 3.10)

project(fwhisper_library VERSION 0.0.1 LANGUAGES C CXX )

set(CMAKE_CXX_STANDARD 11) # 或更高版本，如14或17
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 添加 whisper.cpp 子目录
#set(WHISPER_METAL_EMBED_LIBRARY ON CACHE BOOL "whisper: embed Metal library")
add_subdirectory(whisper.cpp)
message(STATUS "Adding fwhisper.mm to the build.")
# 创建 flutter_whisper_cpp 动态库
add_library(fwhisper SHARED fwhisper.mm)
message(STATUS "Compiling fwhisper.mm")


# 链接 whisper 库（之前称为 whisper）
target_link_libraries(fwhisper PRIVATE whisper)

# 设置目标属性，如公共头文件和输出名称
set_target_properties(fwhisper PROPERTIES
  PUBLIC_HEADER fwhisper.h 
  OUTPUT_NAME "fwhisper"
)

# 添加编译定义
target_compile_definitions(fwhisper PUBLIC DART_SHARED_LIB)

# 打印链接库信息（用于调试）
get_target_property(LIBS fwhisper LINK_LIBRARIES)
message(STATUS "Link libs: ${LIBS}")

# 确保在构建 fwhisper 之前构建 whisper
# 这假设 whisper 已经在 whisper.cpp 子目录中被定义
add_dependencies(fwhisper whisper)
