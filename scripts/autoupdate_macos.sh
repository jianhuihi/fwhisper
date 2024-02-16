#!/bin/bash
# Copyright (C) 2023  Daniel Breedeveld
# Please read LICENSE for terms and conditions.

# Print out system information
echo "[WHisper.AI] Your system information:"
echo "[WHisper.AI] $(uname -a)"

# Navigate to root directory of the project
echo "[WHisper.AI] Navigating to root directory of the project..."
cd ..

# Check if its really the root directory of the project
if [ ! -f "pubspec.yaml" ]; then
    echo "[WHisper.AI] Sorry, this script only works when you are in the root directory of the project. Exiting..."
    exit 1
fi

# Detect if OS is macOS, if not, exit the script.
if [ "$(uname)" != "Darwin" ]; then
    echo "[WHisper.AI] Sorry, this script only works on macOS. Exiting..."
    exit 1
fi

# Run git submodule update to get the latest version of llama.cpp
echo "[WHisper.AI] Updating git submodules..."
git submodule init
git submodule update

# Flutter related
flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
cd example || exit
flutter clean
flutter pub get
cd .. || exit

# Generate a native libraries for the C++ code
echo "[WHisper.AI] Generating a native libraries for the C++ code..."
cd src || exit
rm -rf build

# cmake .. -DBUILD_SHARED_LIBS=ON -DCMAKE_TOOLCHAIN_FILE=../ios-cmake/ios.toolchain.cmake -DPLATFORM=MAC_UNIVERSAL
cmake -B build -DBUILD_SHARED_LIBS=ON -DCMAKE_TOOLCHAIN_FILE=./ios-cmake/ios.toolchain.cmake -DPLATFORM=MAC_UNIVERSAL

# cmake -B build -DBUILD_SHARED_LIBS=ON  -DWHISPER_METAL_EMBED_LIBRARY=ON

cd build || exit

cmake --build . --config Release

# cmake -B build -DBUILD_SHARED_LIBS=ON -DCMAKE_TOOLCHAIN_FILE=./ios-cmake/ios.toolchain.cmake -DPLATFORM=MAC_UNIVERSAL

# Tell user that /src/whisper.cpp/build/libwhisper.dylib has been created.
echo "[WHisper.AI] 'libwhisper.dylib' has been generated successfully."

# Navigate back to the root directory
echo "[WHisper.AI] Navigating back to the root directory..."
cd ../.. || exit

# Check if its really the root directory of the project
if [ ! -f "pubspec.yaml" ]; then
    echo "[WHisper.AI] Sorry, this script only works when you are in the root directory of the project. Exiting..."
    exit 1
fi

# Create a few essential directories if they do not exist
echo "[WHisper.AI] Creating a few essential directories if they do not exist..."
rm -rf macos/Frameworks
mkdir -p macos/Frameworks

# Copy over the compiled libwhisper.a file to both Debug and Release directories of the Flutter app for macOS/iOS
echo "[WHisper.AI] Adding libwhisper.dylib to the macOS project..."
cp src/build/whisper.cpp/libwhisper.dylib macos/Frameworks/libwhisper.dylib
cp src/build/libfwhisper.dylib macos/Frameworks/libfwhisper.dylib


# Copy ggml-metal.metal to the macos/Runner directory of the Flutter app
# TODO: See issue https://github.com/BrutalCoding/aub.ai/issues/1.
echo "[WHisper.AI] Adding ggml-metal.metal to the macOS project..."
cp src/whisper.cpp/build/bin/ggml-metal.metal example/macos/Runner/ggml-metal.metal

# Generate all required files
echo "[WHisper.AI] Generating Dart files..."
dart run build_runner build --delete-conflicting-outputs # Generate files for riverpod, freezed, and json_serializable etc.
sleep 1 # Wait for 1 second to decrease the chance of the next command failing.
dart run ffigen --config ffigen.yaml # Generate files for ffigen, see ffigen.yaml for more info.

# Notify user that AUB is ready to use.
printf "[WHisper.AI] Thanks for flying with WHisper.AI today, the setup took off with success.\n\n"