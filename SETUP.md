# SETUP — one-time toolchain (Linux, user-space)

Everything installs under `$HOME`; no root needed. CachyOS/Arch notes included.

## 1. Rust (rustup)

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile default
source $HOME/.cargo/env
rustup show active-toolchain # project rust-toolchain.toml pins Rust 1.99.0 + Android targets
cargo install flutter_rust_bridge_codegen --version 2.13.0
cargo install cargo-ndk --version 4.1.2
```

The bridge is validated with Rust 1.99.0; the upstream engine declares Rust 1.90+ (edition 2024).

## 2. Flutter (pinned validation version)

```bash
curl -sSL -o /tmp/flutter.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.7-stable.tar.xz
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

## 4. APK on every push

The local hook builds a release APK before pushing and saves it to
`dist/apk/PdfCraft-Mobile-latest.apk`. Enable the tracked hook once per clone:

```bash
git config --local core.hooksPath .githooks
```

It refuses dirty worktrees and pushes whose new commit is not `HEAD`, so the local APK corresponds
to the pushed source. GitHub Actions independently tests and builds each pushed commit; download
the `PdfCraft-Mobile-<commit SHA>` artifact from the workflow run under **Actions → Android APK**.
Artifacts expire after 30 days. Pushes initiated on GitHub's website do not run local hooks, but the
GitHub Actions build still runs.

Manual local build: `source tools/env.sh && tools/build-apk.sh`.
The current release variant is debug-signed for testing; production signing is not configured.

## 5. Pinned PdfCraft source

```bash
git clone --recurse-submodules https://github.com/sujayganorkar/pdfcraft-mobile.git
cd pdfcraft-mobile
```

The tracked submodule pointer pins PdfCraft at the validated revision. If a clone already exists,
run `git submodule update --init --recursive`. The root Cargo workspace uses relative paths and
patches crates.io to the submodule's vendored `hayro`/`lopdf`; no user-specific Cargo paths are
needed. Keep `Cargo.lock` and `pubspec.lock` under version control.

## 6. iOS (future milestone)

Shared code is portable (same bridge crate + Flutter UI). iOS builds need a macOS machine with
Xcode: install the Rust iOS targets (`rustup target add aarch64-apple-ios aarch64-apple-ios-sim`),
run `pod install` in `ios/`, and build with Xcode. The iOS project skeleton already exists from
`flutter create --platforms android,ios`.

## 7. Emulator notes

The x86_64 Google APIs API 35 image was used for the initial runtime verification on this Linux
host, with KVM. The Rust x86_64 library was packaged alongside ARM64. arm64 on an x86_64 host falls
back to slow binary translation; use the x86_64 image for UI work and a physical ARM64 device for
final ARM64 checks.
