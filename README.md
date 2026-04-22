# ffmpeg-build

Build FFmpeg for macOS ARM (Apple Silicon) via GitHub Actions.

## Overview

This repository contains a GitHub Actions workflow that compiles FFmpeg from source on macOS ARM with a comprehensive set of external libraries.

FFmpeg source is included as a git submodule pointing to <https://github.com/FFmpeg/FFmpeg.git>.

The build is driven by a local Homebrew formula in the `tap/Formula/` directory, adapted from Homebrew core and configured for static linking. The formula is installed directly from this repository path.

## Formula source

The local formula in this repository is based on:

<https://github.com/Homebrew/homebrew-core/blob/aa4945b8a55342d9f43f752a15ceed357f9ef05b/Formula/f/ffmpeg-full.rb>

## Configuration

The formula passes a broad set of `./configure` flags including static build settings:

```
--disable-shared
--enable-static
--pkg-config-flags=--static
--enable-gpl
--enable-libdav1d
--enable-libharfbuzz
--enable-libmp3lame
--enable-libopencore-amrnb
--enable-libopencore-amrwb
--enable-libopenjpeg
--enable-libopus
--enable-libsoxr
--enable-libspeex
--enable-libtheora
--enable-libvidstab
--enable-libvmaf
--enable-libvorbis
--enable-libvpx
--enable-libwebp
--enable-libx264
--enable-libx265
--enable-libxml2
--enable-libxvid
--enable-libzimg
--enable-libzmq
--enable-version3
```

On macOS, this produces an FFmpeg build configured for static external linking where available. A fully static binary is generally not possible because Apple system libraries are dynamically linked.

In the formula static build, libbluray is enabled only when `pkg-config --static libbluray` succeeds. If static libbluray dependencies are unavailable from Homebrew, the formula disables libbluray and continues the build.

## Build artifacts

The workflow installs the local formula directly from this repository path using `brew install --build-from-source --HEAD ./tap/Formula/ffmpeg-static.rb`. Compiled binaries are uploaded as a GitHub Actions artifact after each successful build.

If the build fails, the workflow uploads Homebrew build logs (including any discovered `config.log` files) as a failure artifact.

## Local build

```bash
git clone --recursive <repo-url>
cd ffmpeg-build

# Build directly from the local formula (HEAD)
brew install --build-from-source --HEAD ./tap/Formula/ffmpeg-static.rb

# Verify
FFMPEG_PREFIX="$(brew --prefix ffmpeg-static)"
"$FFMPEG_PREFIX/bin/ffmpeg" -version
"$FFMPEG_PREFIX/bin/ffmpeg" -buildconf | grep -E -- '--enable-static|--disable-shared'
```
