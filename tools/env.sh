#!/usr/bin/env bash
# Source this to get the mobile toolchain on PATH.
SDK_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/sdks/android-sdk}}"
export ANDROID_HOME="$SDK_HOME"
export ANDROID_SDK_ROOT="$SDK_HOME"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$SDK_HOME/ndk/27.2.12479018}"
export PATH="$SDK_HOME/platform-tools:$SDK_HOME/emulator:$SDK_HOME/cmdline-tools/latest/bin:$HOME/sdks/flutter/bin:$HOME/.cargo/bin:$PATH"
