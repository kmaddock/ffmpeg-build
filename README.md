# ffmpeg-build

Build FFmpeg for macOS ARM (Apple Silicon) via GitHub Actions.

## Overview

This repository contains a GitHub Actions workflow that compiles FFmpeg from source on macOS ARM with a comprehensive set of external libraries.

FFmpeg source is included as a git submodule pointing to <https://github.com/FFmpeg/FFmpeg.git>.

## Configuration

The build uses the following `./configure` flags:

```
--cc=/usr/bin/clang
--prefix=/opt/ffmpeg
--extra-version=tessus
--disable-shared
--enable-static
--enable-fontconfig
--enable-gpl
--enable-libaom
--enable-libass
--enable-libdav1d
--enable-libfreetype
--enable-libgsm
--enable-libharfbuzz
--enable-libmodplug
--enable-libmp3lame
--enable-libopencore-amrnb
--enable-libopencore-amrwb
--enable-libopenh264
--enable-libopenjpeg
--enable-libopus
--enable-librubberband
--enable-libsnappy
--enable-libsoxr
--enable-libspeex
--enable-libtheora
--enable-libtwolame
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
--pkg-config-flags=--static
--disable-ffplay
```

On macOS, this produces an FFmpeg build configured for static external linking where available. A fully static binary is generally not possible because Apple system libraries are dynamically linked.

In the GitHub Actions static workflow, libbluray is enabled only when `pkg-config --static libbluray` succeeds. If static libbluray dependencies are unavailable from Homebrew, the workflow disables libbluray and continues the build.

## Build artifacts

The workflow uploads the compiled `ffmpeg` and `ffprobe` binaries as a GitHub Actions artifact after each successful build.

## Local build

```bash
git clone --recursive <repo-url>
cd ffmpeg-build

# Install dependencies (macOS ARM)
brew install aom dav1d fontconfig freetype libgsm harfbuzz libass libbluray \
  libmodplug lame libmysofa opencore-amr openh264 openjpeg opus \
  rubberband shine snappy libsoxr speex theora twolame \
  libvidstab libvmaf libvorbis libvpx webp libxml2 x264 x265 xvid \
  zimg zeromq pkg-config

# Build
cd ffmpeg
./configure <flags above>
make -j$(sysctl -n hw.logicalcpu)
sudo make install
```
