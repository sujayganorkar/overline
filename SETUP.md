# SETUP — one-time toolchain (Linux, user-space)

Everything installs under `$HOME`; no root needed. CachyOS/Arch notes included.

## 1. Rust (rustup)

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile default
source $HOME/.cargo/env
rustup target add aarch64-linux-android x86_64-linux-android   # Android ABIs
cargo install flutter_rust_bridge_codegen cargo-ndk
```

The engine needs Rust 1.90+ (its crates use edition 2024 and `rust-version = 1.90`).

## 2. Flutter

```bash
VER=stable   # or pin, e.g. 3.47.7
curl -sSL -o /tmp/flutter.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${VER}.tar.xz
mkdir -p ~/sdks && tar -xJf /tmp/flutter.tar.xz -C ~/sdks
export PATH=~/sdks/flutter/bin:$PATH
flutter config --no-analytics
flutter doctor   # resolve anything it flags
```

## 3. Android SDK + NDK (user-space)

```bash
mkdir -p ~/sdks/android-sdk/cmdline-tools
curl -sSL -o /tmp/cmdline-tools.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip -q /tmp/cmdline-tools.zip -d ~/sdks/android-sdk/cmdline-tools
mv ~/sdks/android-sdk/cmdline-tools/cmdline-tools ~/sdks/android-sdk/cmdline-tools/latest

export ANDROID_HOME=~/sdks/android-sdk PATH=~/sdks/android-sdk/cmdline-tools/latest/bin:$PATH
yes | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" "ndk;27.2.12479018"
```

A JDK is also required (OpenJDK 21 works; `java -version` to check).

## 4. The engine fork

```bash
git clone https://github.com/storytold/pdfcraft ~/src/pdfcraft
cd ~/src/pdfcraft && git checkout dda1a15   # the pinned upstream commit (Phase 1)
```

Our workspace references the engine by absolute path (`/home/sujay/src/pdfcraft/...`) and patches
crates.io to its `vendor/` hayro/lopdf. If you clone the project on another machine or user
account, update the paths in the root `Cargo.toml`.

## 5. iOS (future milestone)

Shared code is portable (same bridge crate + Flutter UI). iOS builds need a macOS machine with
Xcode: install the Rust iOS targets (`rustup target add aarch64-apple-ios aarch64-apple-ios-sim`),
run `pod install` in `ios/`, and build with Xcode. The iOS project skeleton already exists from
`flutter create --platforms android,ios`.

## Emulator notes (if wanted later)

An x86_64 system image + KVM works for UI verification: `sdkmanager "emulator"
"system-images;android-35;google_apis;x86_64"`, then `avdmanager create avd`, then run headless.
arm64 on an x86_64 host falls back to slow binary translation — prefer the x86_64 image for UI
work and a real arm64 device for final checks.
