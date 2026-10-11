#!/usr/bin/env bash
# Source this to get the mobile toolchain on PATH.
export ANDROID_HOME="$HOME/sdks/android-sdk"
export ANDROID_SDK_ROOT="$HOME/sdks/android-sdk"
export ANDROID_NDK_HOME="$HOME/sdks/android-sdk/ndk/27.2.12479018"
export PATH="$HOME/sdks/android-sdk/platform-tools:$HOME/sdks/android-sdk/emulator:$HOME/sdks/android-sdk/cmdline-tools/latest/bin:$HOME/sdks/flutter/bin:$HOME/.cargo/bin:$PATH"
