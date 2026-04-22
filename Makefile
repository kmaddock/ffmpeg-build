SHELL := /bin/bash
.DELETE_ON_ERROR:
.SUFFIXES:

# =============================================================================
# Configuration
# =============================================================================

FFMPEG_VERSION := 8.1

CWD       := $(abspath .)
PACKAGES  := $(CWD)/packages
WORKSPACE := $(CWD)/workspace

MJOBS ?= $(shell sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

UNAME := $(shell uname -s)
ARCH  := $(shell uname -m)

# User options (override on command line: make NONFREE_AND_GPL=1)
NONFREE_AND_GPL ?= 0
DISABLE_LV2     ?= 0
FULL_STATIC     ?= 0
SMALL           ?= 0
NIGHTLY         ?= 0

# Build flags
CFLAGS   := -I$(WORKSPACE)/include -Wno-int-conversion
CXXFLAGS :=
LDFLAGS  := -L$(WORKSPACE)/lib
LDEXEFLAGS :=
EXTRALIBS := -ldl -lpthread -lm -lz

# libtoolize name differs on macOS (brew installs as glibtoolize)
ifeq ($(UNAME),Darwin)
  LIBTOOLIZE := glibtoolize
  MACOS_LIBTOOL := $(shell which libtool)
else
  LIBTOOLIZE := libtoolize
endif

# Apple Silicon detection
MACOS_SILICON :=
ifeq ($(UNAME),Darwin)
  ifeq ($(ARCH),arm64)
    MACOS_SILICON := 1
  endif
endif

# Full static (Linux only)
ifeq ($(FULL_STATIC),1)
  ifeq ($(UNAME),Linux)
    LDEXEFLAGS := -static -fPIC
    CFLAGS += -fPIC
    CXXFLAGS += -fPIC
  endif
endif

# PATH and PKG_CONFIG_PATH
export PATH := $(WORKSPACE)/bin:$(PATH)
export PKG_CONFIG_PATH := $(WORKSPACE)/lib/pkgconfig:/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig:/usr/lib64/pkgconfig
export CMAKE_POLICY_VERSION_MINIMUM=3.5

# System tool checks
HAS_MESON   := $(shell command -v meson 2>/dev/null)
HAS_NINJA   := $(shell command -v ninja 2>/dev/null)
HAS_CARGO   := $(shell command -v cargo 2>/dev/null)
HAS_PYTHON3 := $(shell command -v python3 2>/dev/null)
HAS_NVCC    := $(shell command -v nvcc 2>/dev/null)

# Install prefix
ifeq ($(UNAME),Darwin)
  INSTALL_PREFIX ?= /usr/local
else
  INSTALL_PREFIX ?= $(HOME)/.local
endif

# =============================================================================
# CONFIGURE_OPTIONS and FFMPEG_DEPS accumulation
# =============================================================================

CONFIGURE_OPTIONS :=
FFMPEG_DEPS :=

ifeq ($(UNAME),Darwin)
  CONFIGURE_OPTIONS += --enable-videotoolbox
endif

ifeq ($(SMALL),1)
  CONFIGURE_OPTIONS += --enable-small --disable-doc
  MANPAGES := 0
else
  MANPAGES := 1
endif

# --- Always-built libraries ---
FFMPEG_DEPS += $(PACKAGES)/zlib.done
FFMPEG_DEPS += $(PACKAGES)/giflib.done
FFMPEG_DEPS += $(PACKAGES)/svtav1.done
CONFIGURE_OPTIONS += --enable-libsvtav1
FFMPEG_DEPS += $(PACKAGES)/libvpx.done
CONFIGURE_OPTIONS += --enable-libvpx
FFMPEG_DEPS += $(PACKAGES)/av1.done
CONFIGURE_OPTIONS += --enable-libaom
FFMPEG_DEPS += $(PACKAGES)/zimg.done
CONFIGURE_OPTIONS += --enable-libzimg
FFMPEG_DEPS += $(PACKAGES)/opencore.done
CONFIGURE_OPTIONS += --enable-libopencore_amrnb --enable-libopencore_amrwb
FFMPEG_DEPS += $(PACKAGES)/lame.done
CONFIGURE_OPTIONS += --enable-libmp3lame
FFMPEG_DEPS += $(PACKAGES)/opus.done
CONFIGURE_OPTIONS += --enable-libopus
FFMPEG_DEPS += $(PACKAGES)/libogg.done
FFMPEG_DEPS += $(PACKAGES)/libvorbis.done
CONFIGURE_OPTIONS += --enable-libvorbis
FFMPEG_DEPS += $(PACKAGES)/libtheora.done
CONFIGURE_OPTIONS += --enable-libtheora
FFMPEG_DEPS += $(PACKAGES)/soxr.done
CONFIGURE_OPTIONS += --enable-libsoxr
FFMPEG_DEPS += $(PACKAGES)/libtiff.done
FFMPEG_DEPS += $(PACKAGES)/libpng.done
FFMPEG_DEPS += $(PACKAGES)/lcms2.done
FFMPEG_DEPS += $(PACKAGES)/libjxl.done
CONFIGURE_OPTIONS += --enable-libjxl
EXTRALIBS += -llcms2
FFMPEG_DEPS += $(PACKAGES)/libwebp.done
CONFIGURE_OPTIONS += --enable-libwebp
FFMPEG_DEPS += $(PACKAGES)/libsdl.done
FFMPEG_DEPS += $(PACKAGES)/FreeType2.done
CONFIGURE_OPTIONS += --enable-libfreetype
FFMPEG_DEPS += $(PACKAGES)/VapourSynth.done
CONFIGURE_OPTIONS += --enable-vapoursynth
FFMPEG_DEPS += $(PACKAGES)/libzmq.done
CONFIGURE_OPTIONS += --enable-libzmq
FFMPEG_DEPS += $(PACKAGES)/vulkan-headers.done
CONFIGURE_OPTIONS += --enable-vulkan

ifdef HAS_PYTHON3
  FFMPEG_DEPS += $(PACKAGES)/glslang.done
  CONFIGURE_OPTIONS += --enable-libglslang
endif

ifneq ($(and $(HAS_MESON),$(HAS_NINJA)),)
  FFMPEG_DEPS += $(PACKAGES)/dav1d.done
  CONFIGURE_OPTIONS += --enable-libdav1d
endif

ifdef HAS_CARGO
  FFMPEG_DEPS += $(PACKAGES)/rav1e.done
  CONFIGURE_OPTIONS += --enable-librav1e
endif

ifeq ($(NONFREE_AND_GPL),1)
  CONFIGURE_OPTIONS += --enable-nonfree --enable-gpl
  FFMPEG_DEPS += $(PACKAGES)/gettext.done
  FFMPEG_DEPS += $(PACKAGES)/openssl.done
  CONFIGURE_OPTIONS += --enable-openssl
  FFMPEG_DEPS += $(PACKAGES)/x264.done
  CONFIGURE_OPTIONS += --enable-libx264
  FFMPEG_DEPS += $(PACKAGES)/x265.done
  CONFIGURE_OPTIONS += --enable-libx265
  FFMPEG_DEPS += $(PACKAGES)/xvidcore.done
  CONFIGURE_OPTIONS += --enable-libxvid
  FFMPEG_DEPS += $(PACKAGES)/vid_stab.done
  CONFIGURE_OPTIONS += --enable-libvidstab
  FFMPEG_DEPS += $(PACKAGES)/fdk_aac.done
  CONFIGURE_OPTIONS += --enable-libfdk-aac
  FFMPEG_DEPS += $(PACKAGES)/srt.done
  CONFIGURE_OPTIONS += --enable-libsrt
  FFMPEG_DEPS += $(PACKAGES)/zvbi.done
  CONFIGURE_OPTIONS += --enable-libzvbi
else
  FFMPEG_DEPS += $(PACKAGES)/gmp.done
  FFMPEG_DEPS += $(PACKAGES)/nettle.done
endif

ifneq ($(DISABLE_LV2),1)
  ifneq ($(and $(HAS_MESON),$(HAS_NINJA)),)
    FFMPEG_DEPS += $(PACKAGES)/lilv.done
    CONFIGURE_OPTIONS += --enable-lv2
    CFLAGS += -I$(WORKSPACE)/include/lilv-0
  endif
endif

ifeq ($(UNAME),Linux)
  ifdef HAS_NVCC
    FFMPEG_DEPS += $(PACKAGES)/nv-codec.done
    CFLAGS += -I/usr/local/cuda/include
    LDFLAGS += -L/usr/local/cuda/lib64
    CUDA_COMPUTE_CAPABILITY ?= 52
    CONFIGURE_OPTIONS += --enable-cuda-nvcc --enable-cuvid --enable-nvdec --enable-nvenc --enable-cuda-llvm --enable-ffnvcodec
    CONFIGURE_OPTIONS += --nvccflags="-gencode arch=compute_$(CUDA_COMPUTE_CAPABILITY),code=sm_$(CUDA_COMPUTE_CAPABILITY) -O2"
  else
    CONFIGURE_OPTIONS += --disable-ffnvcodec
  endif
  FFMPEG_DEPS += $(PACKAGES)/amf.done
  CONFIGURE_OPTIONS += --enable-amf
  FFMPEG_DEPS += $(PACKAGES)/opencl-icd-loader.done
  CONFIGURE_OPTIONS += --enable-opencl
endif

# =============================================================================
# Download macro: curl with retry, checksum verification
# Usage: $(call download_file,URL[,SHA256])
# =============================================================================

SHA256CMD := $(shell command -v sha256sum 2>/dev/null || echo "shasum -a 256")

define download_file
	curl -L --silent --fail --retry 2 --retry-delay 5 -o $@ "$(1)"
	@[ -s $@ ] || { rm -f $@; echo "Failed to download $(1)"; exit 1; }
	$(if $(strip $(2)),@ACTUAL=$$($(SHA256CMD) "$@" | cut -d' ' -f1); \
		if [ "$$ACTUAL" != "$(strip $(2))" ]; then \
			echo "SHA256 mismatch for $@ - expected $(strip $(2)) got $$ACTUAL"; rm -f $@; exit 1; \
		fi)
endef

# =============================================================================
# Phony & default targets
# =============================================================================

.PHONY: all nonfree clean install dirs

all: $(PACKAGES)/ffmpeg.done

nonfree:
	$(MAKE) all NONFREE_AND_GPL=1

clean:
	rm -rf $(PACKAGES) $(WORKSPACE)

install: $(PACKAGES)/ffmpeg.done
	mkdir -p $(INSTALL_PREFIX)/bin
	cp $(WORKSPACE)/bin/ffmpeg $(INSTALL_PREFIX)/bin/ffmpeg
	cp $(WORKSPACE)/bin/ffprobe $(INSTALL_PREFIX)/bin/ffprobe
	cp $(WORKSPACE)/bin/ffplay $(INSTALL_PREFIX)/bin/ffplay
ifeq ($(MANPAGES),1)
	mkdir -p $(INSTALL_PREFIX)/share/man/man1
	cp $(WORKSPACE)/share/man/man1/ff* $(INSTALL_PREFIX)/share/man/man1/ 2>/dev/null || true
endif

dirs:
	@mkdir -p $(PACKAGES) $(WORKSPACE)

# =============================================================================
# zlib
# =============================================================================

$(PACKAGES)/zlib-1.3.2.tar.gz: | dirs
	$(call download_file,https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.gz,bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16)

$(PACKAGES)/zlib.done: $(PACKAGES)/zlib-1.3.2.tar.gz
	@rm -rf $(PACKAGES)/zlib-1.3.2 && mkdir -p $(PACKAGES)/zlib-1.3.2
	@tar -xf $< -C $(PACKAGES)/zlib-1.3.2 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/zlib-1.3.2 && \
		./configure --static --prefix="$(WORKSPACE)" && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "1.3.2" > $@

# =============================================================================
# giflib
# =============================================================================

$(PACKAGES)/giflib-5.2.2.tar.gz: | dirs
	$(call download_file,https://sf-eu-introserv-1.dl.sourceforge.net/project/giflib/giflib-5.x/giflib-5.2.2.tar.gz,be7ffbd057cadebe2aa144542fd90c6838c6a083b5e8a9048b8ee3b66b29d5fb)

$(PACKAGES)/giflib.done: $(PACKAGES)/giflib-5.2.2.tar.gz
	@rm -rf $(PACKAGES)/giflib-5.2.2 && mkdir -p $(PACKAGES)/giflib-5.2.2
	@tar -xf $< -C $(PACKAGES)/giflib-5.2.2 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/giflib-5.2.2 && \
		sed 's/$$(MAKE) -C doc//g' Makefile > Makefile.patched && \
		rm Makefile && \
		sed 's/install: all install-bin install-include install-lib install-man/install: all install-bin install-include install-lib/g' Makefile.patched > Makefile && \
		$(MAKE) && \
		$(MAKE) PREFIX="$(WORKSPACE)" install
	@echo "5.2.2" > $@

# =============================================================================
# TLS / crypto (conditional)
# =============================================================================

ifeq ($(NONFREE_AND_GPL),1)

$(PACKAGES)/gettext-1.0.tar.gz: | dirs
	$(call download_file,https://ftpmirror.gnu.org/gettext/gettext-1.0.tar.gz,85d99b79c981a404874c02e0342176cf75c7698e2b51fe41031cf6526d974f1a)

$(PACKAGES)/gettext.done: $(PACKAGES)/gettext-1.0.tar.gz
	@ACTUAL=$$($(SHA256CMD) "$<" | cut -d' ' -f1); \
		if [ "$$ACTUAL" != "85d99b79c981a404874c02e0342176cf75c7698e2b51fe41031cf6526d974f1a" ]; then \
			echo "gettext tarball SHA256 mismatch: $$ACTUAL (expected 85d99b79c981a404874c02e0342176cf75c7698e2b51fe41031cf6526d974f1a) - removing and retrying"; \
			rm -f "$<"; \
			$(MAKE) "$<"; \
		fi
	@rm -rf $(PACKAGES)/gettext-1.0 && mkdir -p $(PACKAGES)/gettext-1.0
	@tar -xf $< -C $(PACKAGES)/gettext-1.0 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/gettext-1.0 && \
		./configure --prefix="$(WORKSPACE)" --enable-static --disable-shared && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "1.0" > $@

$(PACKAGES)/openssl-3.6.1.tar.gz: | dirs
	$(call download_file,https://github.com/openssl/openssl/archive/refs/tags/openssl-3.6.1.tar.gz,f68e6e3a19902c0487d684a4122d4127bc649b4f8f51c15324bb36e0e4dc0bfa)

$(PACKAGES)/openssl.done: $(PACKAGES)/openssl-3.6.1.tar.gz $(PACKAGES)/zlib.done
	@rm -rf $(PACKAGES)/openssl-3.6.1 && mkdir -p $(PACKAGES)/openssl-3.6.1
	@tar -xf $< -C $(PACKAGES)/openssl-3.6.1 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/openssl-3.6.1 && \
		./Configure --prefix="$(WORKSPACE)" --openssldir="$(WORKSPACE)" --libdir="lib" \
			--with-zlib-include="$(WORKSPACE)/include/" --with-zlib-lib="$(WORKSPACE)/lib" \
			no-shared zlib && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install_sw
	@echo "3.6.1" > $@

else # !NONFREE_AND_GPL

$(PACKAGES)/gmp-6.3.0.tar.xz: | dirs
	$(call download_file,https://ftpmirror.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz,a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898)

$(PACKAGES)/gmp.done: $(PACKAGES)/gmp-6.3.0.tar.xz
	@rm -rf $(PACKAGES)/gmp-6.3.0 && mkdir -p $(PACKAGES)/gmp-6.3.0
	@tar -xf $< -C $(PACKAGES)/gmp-6.3.0 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/gmp-6.3.0 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "6.3.0" > $@

$(PACKAGES)/nettle-3.10.2.tar.gz: | dirs
	$(call download_file,https://ftpmirror.gnu.org/gnu/nettle/nettle-3.10.2.tar.gz,fe9ff51cb1f2abb5e65a6b8c10a92da0ab5ab6eaf26e7fc2b675c45f1fb519b5)

$(PACKAGES)/nettle.done: $(PACKAGES)/nettle-3.10.2.tar.gz $(PACKAGES)/gmp.done
	@rm -rf $(PACKAGES)/nettle-3.10.2 && mkdir -p $(PACKAGES)/nettle-3.10.2
	@tar -xf $< -C $(PACKAGES)/nettle-3.10.2 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/nettle-3.10.2 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static \
			--disable-openssl --disable-documentation --libdir="$(WORKSPACE)/lib" \
			CPPFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)" && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "3.10.2" > $@

endif # NONFREE_AND_GPL

# =============================================================================
# Video libraries
# =============================================================================

$(PACKAGES)/dav1d-1.5.3.tar.gz: | dirs
	$(call download_file,https://code.videolan.org/videolan/dav1d/-/archive/1.5.3/dav1d-1.5.3.tar.gz,cbe212b02faf8c6eed5b6d55ef8a6e363aaab83f15112e960701a9c3df813686)

$(PACKAGES)/dav1d.done: $(PACKAGES)/dav1d-1.5.3.tar.gz
	@rm -rf $(PACKAGES)/dav1d-1.5.3 && mkdir -p $(PACKAGES)/dav1d-1.5.3
	@tar -xf $< -C $(PACKAGES)/dav1d-1.5.3 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/dav1d-1.5.3 && \
		rm -rf build && mkdir -p build && \
		$(if $(MACOS_SILICON),CFLAGS="-arch arm64") \
		meson build --prefix="$(WORKSPACE)" --buildtype=release --default-library=static --libdir="$(WORKSPACE)/lib" && \
		ninja -C build && \
		ninja -C build install
	@echo "1.5.3" > $@

$(PACKAGES)/svtav1-4.0.1.tar.gz: | dirs
	$(call download_file,https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v4.0.1/SVT-AV1-v4.0.1.tar.gz,9c0f9a4327334c40a76d2f39940d8a1b2dd8b1358375a11c4715d516b90a65cb)

$(PACKAGES)/svtav1.done: $(PACKAGES)/svtav1-4.0.1.tar.gz
	@rm -rf $(PACKAGES)/svtav1-4.0.1 && mkdir -p $(PACKAGES)/svtav1-4.0.1
	@tar -xf $< -C $(PACKAGES)/svtav1-4.0.1 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/svtav1-4.0.1/Build/linux && \
		cmake -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" -DENABLE_SHARED=off -DBUILD_SHARED_LIBS=OFF \
			../.. -G"Unix Makefiles" -DCMAKE_BUILD_TYPE=Release && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install && \
		cp SvtAv1Enc.pc "$(WORKSPACE)/lib/pkgconfig/"
	@echo "4.0.1" > $@

$(PACKAGES)/rav1e-0.8.1.tar.gz: | dirs
	$(call download_file,https://github.com/xiph/rav1e/archive/refs/tags/v0.8.1.tar.gz,06d1523955fb6ed9cf9992eace772121067cca7e8926988a1ee16492febbe01e)

$(PACKAGES)/rav1e.done: $(PACKAGES)/rav1e-0.8.1.tar.gz
	@rm -rf $(PACKAGES)/rav1e-0.8.1 && mkdir -p $(PACKAGES)/rav1e-0.8.1
	@tar -xf $< -C $(PACKAGES)/rav1e-0.8.1 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/rav1e-0.8.1 && \
		cargo install cargo-c && \
		export RUSTFLAGS="-C target-cpu=native" && \
		cargo cinstall --prefix="$(WORKSPACE)" --libdir=lib --library-type=staticlib --crt-static --release
	@echo "0.8.1" > $@

$(PACKAGES)/libvpx-1.16.0.tar.gz: | dirs
	$(call download_file,https://github.com/webmproject/libvpx/archive/refs/tags/v1.16.0.tar.gz,7a479a3c66b9f5d5542a4c6a1b7d3768a983b1e5c14c60a9396edc9b649e015c)

$(PACKAGES)/libvpx.done: $(PACKAGES)/libvpx-1.16.0.tar.gz
	@rm -rf $(PACKAGES)/libvpx-1.16.0 && mkdir -p $(PACKAGES)/libvpx-1.16.0
	@tar -xf $< -C $(PACKAGES)/libvpx-1.16.0 --strip-components 1 || { rm -f $<; exit 1; }
ifeq ($(UNAME),Darwin)
	cd $(PACKAGES)/libvpx-1.16.0 && \
		sed "s/,--version-script//g" build/make/Makefile > build/make/Makefile.patched && \
		sed "s/-Wl,--no-undefined -Wl,-soname/-Wl,-undefined,error -Wl,-install_name/g" build/make/Makefile.patched > build/make/Makefile
endif
	cd $(PACKAGES)/libvpx-1.16.0 && \
		./configure --prefix="$(WORKSPACE)" --disable-unit-tests --disable-shared --disable-examples --as=yasm --enable-vp9-highbitdepth && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "1.16.0" > $@

$(PACKAGES)/av1-3.12.0.tar.gz: | dirs
	$(call download_file,https://aomedia.googlesource.com/aom/+archive/refs/tags/v3.12.0.tar.gz,0f815383162b62191e2b758e7c2aa926620e0aef94ae9b6d4aff0d007886979c)

$(PACKAGES)/av1.done: $(PACKAGES)/av1-3.12.0.tar.gz
	@rm -rf $(PACKAGES)/av1 && mkdir -p $(PACKAGES)/av1
	@tar -xf $< -C $(PACKAGES)/av1 || { rm -f $<; exit 1; }
	rm -rf $(PACKAGES)/aom_build && mkdir -p $(PACKAGES)/aom_build
	cd $(PACKAGES)/aom_build && \
		cmake -DENABLE_TESTS=0 -DENABLE_EXAMPLES=0 \
			-DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" -DCMAKE_INSTALL_LIBDIR=lib \
			$(if $(MACOS_SILICON),-DCONFIG_RUNTIME_CPU_DETECT=0) \
			$(PACKAGES)/av1 && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "3.12.0" > $@

$(PACKAGES)/zimg-3.0.6.tar.gz: | dirs
	$(call download_file,https://github.com/sekrit-twc/zimg/archive/refs/tags/release-3.0.6.tar.gz,be89390f13a5c9b2388ce0f44a5e89364a20c1c57ce46d382b1fcc3967057577)

$(PACKAGES)/zimg.done: $(PACKAGES)/zimg-3.0.6.tar.gz
	@rm -rf $(PACKAGES)/zimg && mkdir -p $(PACKAGES)/zimg
	@tar -xf $< -C $(PACKAGES)/zimg || { rm -f $<; exit 1; }
	cd $(PACKAGES)/zimg/zimg-release-3.0.6 && \
		$(LIBTOOLIZE) -i -f -q && \
		LIBTOOLIZE="$(LIBTOOLIZE)" ./autogen.sh --prefix="$(WORKSPACE)" && \
		./configure --prefix="$(WORKSPACE)" --enable-static --disable-shared && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "3.0.6" > $@

# --- NONFREE_AND_GPL video libraries ---
ifeq ($(NONFREE_AND_GPL),1)

$(PACKAGES)/x264-0480cb05.tar.gz: | dirs
	$(call download_file,https://code.videolan.org/videolan/x264/-/archive/0480cb05/x264-0480cb05.tar.gz,b336cdb04eeca5d15a53db323bc716fd7a1dae7bf19df0a8a41379d2d65e05d0)

$(PACKAGES)/x264.done: $(PACKAGES)/x264-0480cb05.tar.gz
	@rm -rf $(PACKAGES)/x264-0480cb05 && mkdir -p $(PACKAGES)/x264-0480cb05
	@tar -xf $< -C $(PACKAGES)/x264-0480cb05 --strip-components 1 || { rm -f $<; exit 1; }
ifeq ($(UNAME),Linux)
	cd $(PACKAGES)/x264-0480cb05 && \
		./configure --prefix="$(WORKSPACE)" --enable-static --enable-pic CXXFLAGS="-fPIC $(CXXFLAGS)" && \
		$(MAKE) -j $(MJOBS) && $(MAKE) install && $(MAKE) install-lib-static
else
	cd $(PACKAGES)/x264-0480cb05 && \
		./configure --prefix="$(WORKSPACE)" --enable-static --enable-pic && \
		$(MAKE) -j $(MJOBS) && $(MAKE) install && $(MAKE) install-lib-static
endif
	@echo "0480cb05" > $@

$(PACKAGES)/x265-8be7dbf.tar.gz: | dirs
	$(call download_file,https://bitbucket.org/multicoreware/x265_git/get/8be7dbf8159ddfceea4115675a6d48e1611b8baa.tar.gz,9dcb845f22fe75a88707781026fe4f9d170675a5a25bb5a0de9cc66f62a0a465)

$(PACKAGES)/x265.done: $(PACKAGES)/x265-8be7dbf.tar.gz
	@rm -rf $(PACKAGES)/x265-8be7dbf && mkdir -p $(PACKAGES)/x265-8be7dbf
	@tar -xf $< -C $(PACKAGES)/x265-8be7dbf --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/x265-8be7dbf/build/linux && \
		rm -rf 8bit 10bit 12bit 2>/dev/null; \
		mkdir -p 8bit 10bit 12bit && \
		cd 12bit && \
		cmake ../../../source -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" -DENABLE_SHARED=OFF -DBUILD_SHARED_LIBS=OFF \
			-DHIGH_BIT_DEPTH=ON -DENABLE_HDR10_PLUS=ON -DEXPORT_C_API=OFF -DENABLE_CLI=OFF -DMAIN12=ON \
			$(if $(MACOS_SILICON),-DCMAKE_CXX_FLAGS="-DHAVE_NEON=1") && \
		$(MAKE) -j $(MJOBS) && \
		cd ../10bit && \
		cmake ../../../source -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" -DENABLE_SHARED=OFF -DBUILD_SHARED_LIBS=OFF \
			-DHIGH_BIT_DEPTH=ON -DENABLE_HDR10_PLUS=ON -DEXPORT_C_API=OFF -DENABLE_CLI=OFF \
			$(if $(MACOS_SILICON),-DCMAKE_CXX_FLAGS="-DHAVE_NEON=1") && \
		$(MAKE) -j $(MJOBS) && \
		cd ../8bit && \
		ln -sf ../10bit/libx265.a libx265_main10.a && \
		ln -sf ../12bit/libx265.a libx265_main12.a && \
		cmake ../../../source -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" -DENABLE_SHARED=OFF -DBUILD_SHARED_LIBS=OFF \
			-DEXTRA_LIB="x265_main10.a;x265_main12.a;-ldl" -DEXTRA_LINK_FLAGS=-L. \
			-DLINKED_10BIT=ON -DLINKED_12BIT=ON \
			$(if $(MACOS_SILICON),-DCMAKE_CXX_FLAGS="-DHAVE_NEON=1") && \
		$(MAKE) -j $(MJOBS) && \
		mv libx265.a libx265_main.a && \
		$(if $(filter Darwin,$(UNAME)), \
			$(MACOS_LIBTOOL) -static -o libx265.a libx265_main.a libx265_main10.a libx265_main12.a 2>/dev/null, \
			ar -M <<< $$'CREATE libx265.a\nADDLIB libx265_main.a\nADDLIB libx265_main10.a\nADDLIB libx265_main12.a\nSAVE\nEND' \
		) && \
		$(MAKE) install
ifneq ($(LDEXEFLAGS),)
	sed -i.backup 's/-lgcc_s/-lgcc_eh/g' "$(WORKSPACE)/lib/pkgconfig/x265.pc"
endif
	@echo "8be7dbf" > $@

$(PACKAGES)/xvidcore-1.3.7.tar.gz: | dirs
	$(call download_file,https://downloads.xvid.com/downloads/xvidcore-1.3.7.tar.gz,abbdcbd39555691dd1c9b4d08f0a031376a3b211652c0d8b3b8aa9be1303ce2d)

$(PACKAGES)/xvidcore.done: $(PACKAGES)/xvidcore-1.3.7.tar.gz
	@rm -rf $(PACKAGES)/xvidcore-1.3.7 && mkdir -p $(PACKAGES)/xvidcore-1.3.7
	@tar -xf $< -C $(PACKAGES)/xvidcore-1.3.7 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/xvidcore-1.3.7/build/generic && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install && \
		rm -f "$(WORKSPACE)/lib/libxvidcore.4.dylib" && \
		rm -f "$(WORKSPACE)"/lib/libxvidcore.so*
	@echo "1.3.7" > $@

$(PACKAGES)/vid.stab-1.1.1.tar.gz: | dirs
	$(call download_file,https://github.com/georgmartius/vid.stab/archive/v1.1.1.tar.gz,9001b6df73933555e56deac19a0f225aae152abbc0e97dc70034814a1943f3d4)

$(PACKAGES)/vid_stab.done: $(PACKAGES)/vid.stab-1.1.1.tar.gz
	@rm -rf $(PACKAGES)/vid.stab-1.1.1 && mkdir -p $(PACKAGES)/vid.stab-1.1.1
	@tar -xf $< -C $(PACKAGES)/vid.stab-1.1.1 --strip-components 1 || { rm -f $<; exit 1; }
ifdef MACOS_SILICON
	cd $(PACKAGES)/vid.stab-1.1.1 && \
		curl -L --silent -o fix_cmake_quoting.patch \
			"https://raw.githubusercontent.com/Homebrew/formula-patches/5bf1a0e0cfe666ee410305cece9c9c755641bfdf/libvidstab/fix_cmake_quoting.patch" && \
		patch --forward -p1 < fix_cmake_quoting.patch || [ $$? -eq 1 ]
endif
	cd $(PACKAGES)/vid.stab-1.1.1 && \
		cmake -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" -DUSE_OMP=OFF -DENABLE_SHARED=off . && \
		$(MAKE) && $(MAKE) install
	@echo "1.1.1" > $@

$(PACKAGES)/fdk-aac-2.0.3.tar.gz: | dirs
	$(call download_file,https://sourceforge.net/projects/opencore-amr/files/fdk-aac/fdk-aac-2.0.3.tar.gz/download?use_mirror=gigenet,829b6b89eef382409cda6857fd82af84fabb63417b08ede9ea7a553f811cb79e)

$(PACKAGES)/fdk_aac.done: $(PACKAGES)/fdk-aac-2.0.3.tar.gz
	@rm -rf $(PACKAGES)/fdk-aac-2.0.3 && mkdir -p $(PACKAGES)/fdk-aac-2.0.3
	@tar -xf $< -C $(PACKAGES)/fdk-aac-2.0.3 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/fdk-aac-2.0.3 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static --enable-pic && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "2.0.3" > $@

$(PACKAGES)/srt-1.5.4.tar.gz: | dirs
	$(call download_file,https://github.com/Haivision/srt/archive/v1.5.4.tar.gz,d0a8b600fe1b4eaaf6277530e3cfc8f15b8ce4035f16af4a5eb5d4b123640cdd)

$(PACKAGES)/srt.done: $(PACKAGES)/srt-1.5.4.tar.gz $(PACKAGES)/openssl.done
	@rm -rf $(PACKAGES)/srt-1.5.4 && mkdir -p $(PACKAGES)/srt-1.5.4
	@tar -xf $< -C $(PACKAGES)/srt-1.5.4 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/srt-1.5.4 && \
		export OPENSSL_ROOT_DIR="$(WORKSPACE)" && \
		export OPENSSL_LIB_DIR="$(WORKSPACE)/lib" && \
		export OPENSSL_INCLUDE_DIR="$(WORKSPACE)/include/" && \
		cmake . -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" -DCMAKE_INSTALL_LIBDIR=lib \
			-DCMAKE_INSTALL_BINDIR=bin -DCMAKE_INSTALL_INCLUDEDIR=include \
			-DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DENABLE_APPS=OFF -DUSE_STATIC_LIBSTDCXX=ON && \
		$(MAKE) install
ifneq ($(LDEXEFLAGS),)
	sed -i.backup 's/-lgcc_s/-lgcc_eh/g' "$(WORKSPACE)/lib/pkgconfig/srt.pc"
endif
	@echo "1.5.4" > $@

$(PACKAGES)/zvbi-0.2.44.tar.gz: | dirs
	$(call download_file,https://github.com/zapping-vbi/zvbi/archive/refs/tags/v0.2.44.tar.gz,bca620ab670328ad732d161e4ce8d9d9fc832533cb7440e98c50e112b805ac5e)

$(PACKAGES)/zvbi.done: $(PACKAGES)/zvbi-0.2.44.tar.gz $(PACKAGES)/libpng.done
	@rm -rf $(PACKAGES)/zvbi-0.2.44 && mkdir -p $(PACKAGES)/zvbi-0.2.44
	@tar -xf $< -C $(PACKAGES)/zvbi-0.2.44 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/zvbi-0.2.44 && \
		LIBTOOLIZE="$(LIBTOOLIZE)" ./autogen.sh --prefix="$(WORKSPACE)" && \
		./configure CFLAGS="-I$(WORKSPACE)/include/libpng16 $(CFLAGS)" \
			--prefix="$(WORKSPACE)" --enable-static --disable-shared && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "0.2.44" > $@

endif # NONFREE_AND_GPL

# =============================================================================
# Audio libraries
# =============================================================================

$(PACKAGES)/opencore-amr-0.1.6.tar.gz: | dirs
	$(call download_file,https://deac-ams.dl.sourceforge.net/project/opencore-amr/opencore-amr/opencore-amr-0.1.6.tar.gz,483eb4061088e2b34b358e47540b5d495a96cd468e361050fae615b1809dc4a1)

$(PACKAGES)/opencore.done: $(PACKAGES)/opencore-amr-0.1.6.tar.gz
	@rm -rf $(PACKAGES)/opencore-amr-0.1.6 && mkdir -p $(PACKAGES)/opencore-amr-0.1.6
	@tar -xf $< -C $(PACKAGES)/opencore-amr-0.1.6 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/opencore-amr-0.1.6 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "0.1.6" > $@

$(PACKAGES)/lame-3.100.tar.gz: | dirs
	$(call download_file,https://sourceforge.net/projects/lame/files/lame/3.100/lame-3.100.tar.gz/download?use_mirror=gigenet,ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e)

$(PACKAGES)/lame.done: $(PACKAGES)/lame-3.100.tar.gz
	@rm -rf $(PACKAGES)/lame-3.100 && mkdir -p $(PACKAGES)/lame-3.100
	@tar -xf $< -C $(PACKAGES)/lame-3.100 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/lame-3.100 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "3.100" > $@

$(PACKAGES)/opus-1.6.1.tar.gz: | dirs
	$(call download_file,https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz,6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1)

$(PACKAGES)/opus.done: $(PACKAGES)/opus-1.6.1.tar.gz
	@rm -rf $(PACKAGES)/opus-1.6.1 && mkdir -p $(PACKAGES)/opus-1.6.1
	@tar -xf $< -C $(PACKAGES)/opus-1.6.1 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/opus-1.6.1 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "1.6.1" > $@

$(PACKAGES)/libogg-1.3.6.tar.xz: | dirs
	$(call download_file,https://ftp.osuosl.org/pub/xiph/releases/ogg/libogg-1.3.6.tar.xz,5c8253428e181840cd20d41f3ca16557a9cc04bad4a3d04cce84808677fa1061)

$(PACKAGES)/libogg.done: $(PACKAGES)/libogg-1.3.6.tar.xz
	@rm -rf $(PACKAGES)/libogg-1.3.6 && mkdir -p $(PACKAGES)/libogg-1.3.6
	@tar -xf $< -C $(PACKAGES)/libogg-1.3.6 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/libogg-1.3.6 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "1.3.6" > $@

$(PACKAGES)/libvorbis-1.3.7.tar.gz: | dirs
	$(call download_file,https://ftp.osuosl.org/pub/xiph/releases/vorbis/libvorbis-1.3.7.tar.gz,0e982409a9c3fc82ee06e08205b1355e5c6aa4c36bca58146ef399621b0ce5ab)

$(PACKAGES)/libvorbis.done: $(PACKAGES)/libvorbis-1.3.7.tar.gz $(PACKAGES)/libogg.done
	@rm -rf $(PACKAGES)/libvorbis-1.3.7 && mkdir -p $(PACKAGES)/libvorbis-1.3.7
	@tar -xf $< -C $(PACKAGES)/libvorbis-1.3.7 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/libvorbis-1.3.7 && \
		sed 's/-force_cpusubtype_ALL//g' configure.ac > configure.ac.patched && \
		rm configure.ac && mv configure.ac.patched configure.ac && \
		LIBTOOLIZE="$(LIBTOOLIZE)" ./autogen.sh --prefix="$(WORKSPACE)" && \
		./configure --prefix="$(WORKSPACE)" --with-ogg-libraries="$(WORKSPACE)/lib" \
			--with-ogg-includes="$(WORKSPACE)/include/" --enable-static --disable-shared --disable-oggtest && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "1.3.7" > $@

$(PACKAGES)/libtheora-1.2.0.tar.gz: | dirs
	$(call download_file,https://ftp.osuosl.org/pub/xiph/releases/theora/libtheora-1.2.0.tar.gz,279327339903b544c28a92aeada7d0dcfd0397b59c2f368cc698ac56f515906e)

$(PACKAGES)/libtheora.done: $(PACKAGES)/libtheora-1.2.0.tar.gz $(PACKAGES)/libogg.done $(PACKAGES)/libvorbis.done
	@rm -rf $(PACKAGES)/libtheora-1.2.0 && mkdir -p $(PACKAGES)/libtheora-1.2.0
	@tar -xf $< -C $(PACKAGES)/libtheora-1.2.0 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/libtheora-1.2.0 && \
		./configure --prefix="$(WORKSPACE)" \
			--with-ogg-libraries="$(WORKSPACE)/lib" --with-ogg-includes="$(WORKSPACE)/include/" \
			--with-vorbis-libraries="$(WORKSPACE)/lib" --with-vorbis-includes="$(WORKSPACE)/include/" \
			--enable-static --disable-shared --disable-oggtest --disable-vorbistest \
			--disable-examples --disable-spec && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "1.2.0" > $@

$(PACKAGES)/soxr-0.1.3.tar.xz: | dirs
	$(call download_file,https://sourceforge.net/projects/soxr/files/soxr-0.1.3-Source.tar.xz/download?use_mirror=gigenet,b111c15fdc8c029989330ff559184198c161100a59312f5dc19ddeb9b5a15889)

$(PACKAGES)/soxr.done: $(PACKAGES)/soxr-0.1.3.tar.xz
	@rm -rf $(PACKAGES)/soxr-0.1.3 && mkdir -p $(PACKAGES)/soxr-0.1.3
	@tar -xf $< -C $(PACKAGES)/soxr-0.1.3 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/soxr-0.1.3 && \
		mkdir -p build && cd build && \
		cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" \
			-DBUILD_SHARED_LIBS:bool=off -DWITH_OPENMP:bool=off -DBUILD_TESTS:bool=off \
			$(if $(MACOS_SILICON),-DCMAKE_C_FLAGS="-include $(CWD)/soxr-aarch64-neon.h" -DWITH_CR32S=ON -DWITH_CR64S=ON) \
			-Wno-dev .. && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "0.1.3" > $@

# --- LV2 chain ---
ifneq ($(DISABLE_LV2),1)
ifneq ($(and $(HAS_MESON),$(HAS_NINJA)),)

$(PACKAGES)/lv2-1.18.10.tar.xz: | dirs
	$(call download_file,https://lv2plug.in/spec/lv2-1.18.10.tar.xz,78c51bcf21b54e58bb6329accbb4dae03b2ed79b520f9a01e734bd9de530953f)

$(PACKAGES)/lv2.done: $(PACKAGES)/lv2-1.18.10.tar.xz
	@rm -rf $(PACKAGES)/lv2-1.18.10 && mkdir -p $(PACKAGES)/lv2-1.18.10
	@tar -xf $< -C $(PACKAGES)/lv2-1.18.10 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/lv2-1.18.10 && \
		meson build --prefix="$(WORKSPACE)" --buildtype=release --default-library=static --libdir="$(WORKSPACE)/lib" && \
		ninja -C build && \
		ninja -C build install
	@echo "1.18.10" > $@

$(PACKAGES)/serd-v0.32.8.tar.gz: | dirs
	$(call download_file,https://gitlab.com/drobilla/serd/-/archive/v0.32.8/serd-v0.32.8.tar.gz,c0133d878b4b1abf5cb4b2ec4501ebf688edcfefb12a602e3cc26d9e6577a01c)

$(PACKAGES)/serd.done: $(PACKAGES)/serd-v0.32.8.tar.gz
	@rm -rf $(PACKAGES)/serd-v0.32.8 && mkdir -p $(PACKAGES)/serd-v0.32.8
	@tar -xf $< -C $(PACKAGES)/serd-v0.32.8 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/serd-v0.32.8 && \
		meson build --prefix="$(WORKSPACE)" --buildtype=release --default-library=static --libdir="$(WORKSPACE)/lib" && \
		ninja -C build && \
		ninja -C build install
	@echo "0.32.8" > $@

$(PACKAGES)/pcre-8.45.tar.gz: | dirs
	$(call download_file,https://altushost-swe.dl.sourceforge.net/project/pcre/pcre/8.45/pcre-8.45.tar.gz,4e6ce03e0336e8b4a3d6c2b70b1c5e18590a5673a98186da90d4f33c23defc09)

$(PACKAGES)/pcre.done: $(PACKAGES)/pcre-8.45.tar.gz
	@rm -rf $(PACKAGES)/pcre-8.45 && mkdir -p $(PACKAGES)/pcre-8.45
	@tar -xf $< -C $(PACKAGES)/pcre-8.45 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/pcre-8.45 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "8.45" > $@

$(PACKAGES)/zix-v0.8.0.tar.gz: | dirs
	$(call download_file,https://gitlab.com/drobilla/zix/-/archive/v0.8.0/zix-v0.8.0.tar.gz,51d70d63e970214db84e32d55377d84090c02145f5768265ab140d117f2b8e24)

$(PACKAGES)/zix.done: $(PACKAGES)/zix-v0.8.0.tar.gz
	@rm -rf $(PACKAGES)/zix-v0.8.0 && mkdir -p $(PACKAGES)/zix-v0.8.0
	@tar -xf $< -C $(PACKAGES)/zix-v0.8.0 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/zix-v0.8.0 && \
		meson setup build --prefix="$(WORKSPACE)" --buildtype=release --default-library=static --libdir="$(WORKSPACE)/lib" && \
		cd build && \
		meson configure -Dc_args="-march=native" -Dprefix="$(WORKSPACE)" -Dlibdir="$(WORKSPACE)/lib" && \
		meson compile && \
		meson install
	@echo "0.8.0" > $@

$(PACKAGES)/sord-v0.16.22.tar.gz: | dirs
	$(call download_file,https://gitlab.com/drobilla/sord/-/archive/v0.16.22/sord-v0.16.22.tar.gz,040fb3f369dd49a7717eb28ca0a66766352e25e760729903fc8a01e117122901)

$(PACKAGES)/sord.done: $(PACKAGES)/sord-v0.16.22.tar.gz $(PACKAGES)/serd.done $(PACKAGES)/zix.done
	@rm -rf $(PACKAGES)/sord-v0.16.22 && mkdir -p $(PACKAGES)/sord-v0.16.22
	@tar -xf $< -C $(PACKAGES)/sord-v0.16.22 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/sord-v0.16.22 && \
		meson build --prefix="$(WORKSPACE)" --buildtype=release --default-library=static --libdir="$(WORKSPACE)/lib" && \
		ninja -C build && \
		ninja -C build install
	@echo "0.16.22" > $@

$(PACKAGES)/sratom-v0.6.22.tar.gz: | dirs
	$(call download_file,https://gitlab.com/lv2/sratom/-/archive/v0.6.22/sratom-v0.6.22.tar.gz,4a88bde345370584b279895c2cb8f7f8341d2b31b6ca50e128faea02f02d3e76)

$(PACKAGES)/sratom.done: $(PACKAGES)/sratom-v0.6.22.tar.gz $(PACKAGES)/sord.done $(PACKAGES)/lv2.done
	@rm -rf $(PACKAGES)/sratom-v0.6.22 && mkdir -p $(PACKAGES)/sratom-v0.6.22
	@tar -xf $< -C $(PACKAGES)/sratom-v0.6.22 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/sratom-v0.6.22 && \
		meson build --prefix="$(WORKSPACE)" -Ddocs=disabled --buildtype=release --default-library=static --libdir="$(WORKSPACE)/lib" && \
		ninja -C build && \
		ninja -C build install
	@echo "0.6.22" > $@

$(PACKAGES)/lilv-v0.26.4.tar.gz: | dirs
	$(call download_file,https://gitlab.com/lv2/lilv/-/archive/v0.26.4/lilv-v0.26.4.tar.gz,3281f33237385de3efa515e3f6463548bfb8feb358d52961c7d7350094b7d321)

$(PACKAGES)/lilv.done: $(PACKAGES)/lilv-v0.26.4.tar.gz $(PACKAGES)/sratom.done
	@rm -rf $(PACKAGES)/lilv-v0.26.4 && mkdir -p $(PACKAGES)/lilv-v0.26.4
	@tar -xf $< -C $(PACKAGES)/lilv-v0.26.4 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/lilv-v0.26.4 && \
		meson build --prefix="$(WORKSPACE)" -Ddocs=disabled --buildtype=release --default-library=static \
			--libdir="$(WORKSPACE)/lib" -Dcpp_std=c++11 && \
		ninja -C build && \
		ninja -C build install
	@echo "0.26.4" > $@

endif # HAS_MESON
endif # DISABLE_LV2

# =============================================================================
# Image libraries
# =============================================================================

$(PACKAGES)/tiff-4.7.1.tar.xz: | dirs
	$(call download_file,https://download.osgeo.org/libtiff/tiff-4.7.1.tar.xz,b92017489bdc1db3a4c97191aa4b75366673cb746de0dce5d7a749d5954681ba)

$(PACKAGES)/libtiff.done: $(PACKAGES)/tiff-4.7.1.tar.xz $(PACKAGES)/zlib.done
	@rm -rf $(PACKAGES)/tiff-4.7.1 && mkdir -p $(PACKAGES)/tiff-4.7.1
	@tar -xf $< -C $(PACKAGES)/tiff-4.7.1 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/tiff-4.7.1 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static \
			--disable-dependency-tracking --disable-lzma --disable-webp --disable-zstd --without-x && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "4.7.1" > $@

$(PACKAGES)/libpng-1.6.55.tar.gz: | dirs
	$(call download_file,https://sourceforge.net/projects/libpng/files/libpng16/1.6.55/libpng-1.6.55.tar.gz,4b0abab6d219e95690ebe4db7fc9aa95f4006c83baaa022373c0c8442271283d)

$(PACKAGES)/libpng.done: $(PACKAGES)/libpng-1.6.55.tar.gz $(PACKAGES)/zlib.done
	@rm -rf $(PACKAGES)/libpng-1.6.55 && mkdir -p $(PACKAGES)/libpng-1.6.55
	@tar -xf $< -C $(PACKAGES)/libpng-1.6.55 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/libpng-1.6.55 && \
		LDFLAGS="$(LDFLAGS)" CPPFLAGS="$(CFLAGS)" \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "1.6.55" > $@

$(PACKAGES)/lcms2-2.18.tar.gz: | dirs
	$(call download_file,https://github.com/mm2/Little-CMS/releases/download/lcms2.18/lcms2-2.18.tar.gz,ee67be3566f459362c1ee094fde2c159d33fa0390aa4ed5f5af676f9e5004347)

$(PACKAGES)/lcms2.done: $(PACKAGES)/lcms2-2.18.tar.gz
	@rm -rf $(PACKAGES)/lcms2-2.18 && mkdir -p $(PACKAGES)/lcms2-2.18
	@tar -xf $< -C $(PACKAGES)/lcms2-2.18 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/lcms2-2.18 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "2.18" > $@

$(PACKAGES)/libjxl-0.11.2.tar.gz: | dirs
	$(call download_file,https://github.com/libjxl/libjxl/archive/refs/tags/v0.11.2.tar.gz,ab38928f7f6248e2a98cc184956021acb927b16a0dee71b4d260dc040a4320ea)

$(PACKAGES)/libjxl.done: $(PACKAGES)/libjxl-0.11.2.tar.gz $(PACKAGES)/lcms2.done $(PACKAGES)/libpng.done
	@rm -rf $(PACKAGES)/libjxl-0.11.2 && mkdir -p $(PACKAGES)/libjxl-0.11.2
	@tar -xf $< -C $(PACKAGES)/libjxl-0.11.2 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/libjxl-0.11.2 && \
		sed "s/-ljxl_threads/-ljxl_threads @JPEGXL_THREADS_PUBLIC_LIBS@/g" lib/threads/libjxl_threads.pc.in > lib/threads/libjxl_threads.pc.in.patched && \
		rm lib/threads/libjxl_threads.pc.in && mv lib/threads/libjxl_threads.pc.in.patched lib/threads/libjxl_threads.pc.in && \
		sed 's/set(JPEGXL_REQUIRES_TYPE "Requires")/set(JPEGXL_REQUIRES_TYPE "Requires")\n  set(JPEGXL_THREADS_PUBLIC_LIBS "-lm $${PKGCONFIG_CXX_LIB}")/g' lib/jxl_threads.cmake > lib/jxl_threads.cmake.patched && \
		rm lib/jxl_threads.cmake && mv lib/jxl_threads.cmake.patched lib/jxl_threads.cmake && \
		./deps.sh && \
		cmake -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" \
			-DCMAKE_PREFIX_PATH="$(WORKSPACE)" -DCMAKE_FIND_FRAMEWORK=NEVER \
			-DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_BINDIR=bin -DCMAKE_INSTALL_INCLUDEDIR=include \
			-DENABLE_SHARED=off -DENABLE_STATIC=ON -DCMAKE_BUILD_TYPE=Release \
			-DJPEGXL_ENABLE_BENCHMARK=OFF -DJPEGXL_ENABLE_DOXYGEN=OFF -DJPEGXL_ENABLE_MANPAGES=OFF \
			-DJPEGXL_ENABLE_JPEGLI_LIBJPEG=OFF -DJPEGXL_ENABLE_JPEGLI=ON \
			-DJPEGXL_TEST_TOOLS=OFF -DJPEGXL_ENABLE_JNI=OFF -DBUILD_TESTING=OFF \
			-DJPEGXL_ENABLE_SKCMS=OFF . && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "0.11.2" > $@

$(PACKAGES)/libwebp-1.6.0.tar.gz: | dirs
	$(call download_file,https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz,e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564)

$(PACKAGES)/libwebp.done: $(PACKAGES)/libwebp-1.6.0.tar.gz
	@rm -rf $(PACKAGES)/libwebp-1.6.0 && mkdir -p $(PACKAGES)/libwebp-1.6.0
	@tar -xf $< -C $(PACKAGES)/libwebp-1.6.0 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/libwebp-1.6.0 && \
		rm -rf build && mkdir -p build && cd build && \
		cmake -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" -DCMAKE_INSTALL_LIBDIR=lib \
			-DCMAKE_INSTALL_BINDIR=bin -DCMAKE_INSTALL_INCLUDEDIR=include \
			-DENABLE_SHARED=OFF -DENABLE_STATIC=ON \
			-DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF \
			-DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_ANIM_UTILS=OFF ../ && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "1.6.0" > $@

# =============================================================================
# Other libraries
# =============================================================================

$(PACKAGES)/SDL2-2.30.12.tar.gz: | dirs
	$(call download_file,https://github.com/libsdl-org/SDL/releases/download/release-2.30.12/SDL2-2.30.12.tar.gz,ac356ea55e8b9dd0b2d1fa27da40ef7e238267ccf9324704850d5d47375b48ea)

$(PACKAGES)/libsdl.done: $(PACKAGES)/SDL2-2.30.12.tar.gz
	@rm -rf $(PACKAGES)/SDL2-2.30.12 && mkdir -p $(PACKAGES)/SDL2-2.30.12
	@tar -xf $< -C $(PACKAGES)/SDL2-2.30.12 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/SDL2-2.30.12 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "2.30.12" > $@

$(PACKAGES)/freetype-2.14.2.tar.xz: | dirs
	$(call download_file,https://downloads.sourceforge.net/freetype/freetype-2.14.2.tar.xz,4b62dcab4c920a1a860369933221814362e699e26f55792516d671e6ff55b5e1)

$(PACKAGES)/FreeType2.done: $(PACKAGES)/freetype-2.14.2.tar.xz
	@rm -rf $(PACKAGES)/freetype-2.14.2 && mkdir -p $(PACKAGES)/freetype-2.14.2
	@tar -xf $< -C $(PACKAGES)/freetype-2.14.2 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/freetype-2.14.2 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "2.14.2" > $@

$(PACKAGES)/vapoursynth-R73.tar.gz: | dirs
	$(call download_file,https://github.com/vapoursynth/vapoursynth/archive/R73.tar.gz,1bb8ffe31348eaf46d8f541b138f0136d10edaef0c130c1e5a13aa4a4b057280)

$(PACKAGES)/VapourSynth.done: $(PACKAGES)/vapoursynth-R73.tar.gz
	@rm -rf $(PACKAGES)/vapoursynth-R73 && mkdir -p $(PACKAGES)/vapoursynth-R73
	@tar -xf $< -C $(PACKAGES)/vapoursynth-R73 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/vapoursynth-R73 && \
		mkdir -p "$(WORKSPACE)/include/vapoursynth" && \
		cp -r include/. "$(WORKSPACE)/include/vapoursynth/"
	@echo "73" > $@

$(PACKAGES)/zeromq-4.3.5.tar.gz: | dirs
	$(call download_file,https://github.com/zeromq/libzmq/releases/download/v4.3.5/zeromq-4.3.5.tar.gz,6653ef5910f17954861fe72332e68b03ca6e4d9c7160eb3a8de5a5a913bfab43)

$(PACKAGES)/libzmq.done: $(PACKAGES)/zeromq-4.3.5.tar.gz
	@rm -rf $(PACKAGES)/zeromq-4.3.5 && mkdir -p $(PACKAGES)/zeromq-4.3.5
	@tar -xf $< -C $(PACKAGES)/zeromq-4.3.5 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/zeromq-4.3.5 && \
		$(if $(filter Darwin,$(UNAME)),export XML_CATALOG_FILES=/usr/local/etc/xml/catalog &&) \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		sed "s/stats_proxy stats = {0}/stats_proxy stats = {{{0, 0}, {0, 0}}, {{0, 0}, {0, 0}}}/g" src/proxy.cpp > src/proxy.cpp.patched && \
		rm src/proxy.cpp && mv src/proxy.cpp.patched src/proxy.cpp && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "4.3.5" > $@

$(PACKAGES)/Vulkan-Headers-1.4.341.0.tar.gz: | dirs
	$(call download_file,https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/vulkan-sdk-1.4.341.0.tar.gz,d73bc5036b6556b741f6985ff600ca720308c5f2850e4a43ceb498bd3de069e7)

$(PACKAGES)/vulkan-headers.done: $(PACKAGES)/Vulkan-Headers-1.4.341.0.tar.gz
	@rm -rf $(PACKAGES)/Vulkan-Headers-1.4.341.0 && mkdir -p $(PACKAGES)/Vulkan-Headers-1.4.341.0
	@tar -xf $< -C $(PACKAGES)/Vulkan-Headers-1.4.341.0 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/Vulkan-Headers-1.4.341.0 && \
		cmake -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" -B build/ && \
		cd build/ && $(MAKE) install
	@echo "1.4.341.0" > $@

$(PACKAGES)/glslang-16.2.0.tar.gz: | dirs
	$(call download_file,https://github.com/KhronosGroup/glslang/archive/refs/tags/16.2.0.tar.gz,01985335785c97906a91afe3cb5ee015997696181ec6c125bab5555602ba08e2)

$(PACKAGES)/glslang.done: $(PACKAGES)/glslang-16.2.0.tar.gz
	@rm -rf $(PACKAGES)/glslang-16.2.0 && mkdir -p $(PACKAGES)/glslang-16.2.0
	@tar -xf $< -C $(PACKAGES)/glslang-16.2.0 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/glslang-16.2.0 && \
		./update_glslang_sources.py && \
		cmake -DCMAKE_BUILD_TYPE=Release -DENABLE_SHARED=OFF -DBUILD_SHARED_LIBS=OFF \
			-DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" . && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "16.2.0" > $@

# =============================================================================
# Linux-only: HW acceleration
# =============================================================================

ifeq ($(UNAME),Linux)

ifdef HAS_NVCC
$(PACKAGES)/nv-codec-headers-13.0.19.0.tar.gz: | dirs
	$(call download_file,https://github.com/FFmpeg/nv-codec-headers/releases/download/n13.0.19.0/nv-codec-headers-13.0.19.0.tar.gz,13da39edb3a40ed9713ae390ca89faa2f1202c9dda869ef306a8d4383e242bee)

$(PACKAGES)/nv-codec.done: $(PACKAGES)/nv-codec-headers-13.0.19.0.tar.gz
	@rm -rf $(PACKAGES)/nv-codec-headers-13.0.19.0 && mkdir -p $(PACKAGES)/nv-codec-headers-13.0.19.0
	@tar -xf $< -C $(PACKAGES)/nv-codec-headers-13.0.19.0 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/nv-codec-headers-13.0.19.0 && \
		$(MAKE) PREFIX="$(WORKSPACE)" && \
		$(MAKE) PREFIX="$(WORKSPACE)" install
	@echo "13.0.19.0" > $@
endif

$(PACKAGES)/AMF-1.5.0.tar.gz: | dirs
	$(call download_file,https://github.com/GPUOpen-LibrariesAndSDKs/AMF/archive/refs/tags/v1.5.0.tar.gz,bf80ee4a77a731c5a2351b4dd74f524a18806a70099ba66a8058d91aac1150b5)

$(PACKAGES)/amf.done: $(PACKAGES)/AMF-1.5.0.tar.gz
	@rm -rf $(PACKAGES)/AMF-1.5.0 && mkdir -p $(PACKAGES)/AMF-1.5.0
	@tar -xf $< -C $(PACKAGES)/AMF-1.5.0 || { rm -f $<; exit 1; }
	rm -rf "$(WORKSPACE)/include/AMF"
	mkdir -p "$(WORKSPACE)/include/AMF"
	cp -r "$(PACKAGES)/AMF-1.5.0/AMF-1.5.0/amf/public/include/"* "$(WORKSPACE)/include/AMF/"
	@echo "1.5.0" > $@

$(PACKAGES)/OpenCL-Headers-2025.07.22.tar.gz: | dirs
	$(call download_file,https://github.com/KhronosGroup/OpenCL-Headers/archive/refs/tags/v2025.07.22.tar.gz,98f0a3ea26b4aec051e533cb1750db2998ab8e82eda97269ed6efe66ec94a240)

$(PACKAGES)/opencl-headers.done: $(PACKAGES)/OpenCL-Headers-2025.07.22.tar.gz
	@rm -rf $(PACKAGES)/OpenCL-Headers-2025.07.22 && mkdir -p $(PACKAGES)/OpenCL-Headers-2025.07.22
	@tar -xf $< -C $(PACKAGES)/OpenCL-Headers-2025.07.22 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/OpenCL-Headers-2025.07.22 && \
		cmake -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" -B build/ && \
		cmake --build build --target install
	@echo "2025.07.22" > $@

$(PACKAGES)/OpenCL-ICD-Loader-2025.07.22.tar.gz: | dirs
	$(call download_file,https://github.com/KhronosGroup/OpenCL-ICD-Loader/archive/refs/tags/v2025.07.22.tar.gz,dff7a0b11ad5b63a669358e3476e3dc889a4a361674e5b69b267b944d0794142)

$(PACKAGES)/opencl-icd-loader.done: $(PACKAGES)/OpenCL-ICD-Loader-2025.07.22.tar.gz $(PACKAGES)/opencl-headers.done
	@rm -rf $(PACKAGES)/OpenCL-ICD-Loader-2025.07.22 && mkdir -p $(PACKAGES)/OpenCL-ICD-Loader-2025.07.22
	@tar -xf $< -C $(PACKAGES)/OpenCL-ICD-Loader-2025.07.22 --strip-components 1 || { rm -f $<; exit 1; }
	cd $(PACKAGES)/OpenCL-ICD-Loader-2025.07.22 && \
		cmake -DCMAKE_PREFIX_PATH="$(WORKSPACE)" -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" \
			-DENABLE_SHARED=OFF -DBUILD_SHARED_LIBS=OFF -B build/ && \
		cmake --build build --target install
	@echo "2025.07.22" > $@

endif # Linux

# =============================================================================
# FFmpeg
# =============================================================================

FFMPEG_SRCDIR := $(PACKAGES)/ffmpeg-src

FFMPEG_EXTRA_VERSION :=
ifeq ($(UNAME),Darwin)
  ifeq ($(NIGHTLY),1)
    FFMPEG_EXTRA_VERSION := nightly
  else
    FFMPEG_EXTRA_VERSION := $(FFMPEG_VERSION)
  endif
endif

ifeq ($(NIGHTLY),1)

# --- Nightly: shallow-clone HEAD of master ---
$(FFMPEG_SRCDIR)/.git:
	@mkdir -p $(PACKAGES)
	git clone --depth 1 https://github.com/FFmpeg/FFmpeg.git $(FFMPEG_SRCDIR)

# Always re-pull on each build; .PHONY-like via the force target
.PHONY: ffmpeg-pull
ffmpeg-pull: $(FFMPEG_SRCDIR)/.git
	cd $(FFMPEG_SRCDIR) && git pull --ff-only

$(PACKAGES)/ffmpeg.done: ffmpeg-pull $(FFMPEG_DEPS) | dirs
	@if [ -d "$(CWD)/.git" ]; then mv "$(CWD)/.git" "$(CWD)/.git.bak"; fi
	cd $(FFMPEG_SRCDIR) && \
		./configure $(CONFIGURE_OPTIONS) \
			--disable-debug \
			--disable-shared \
			--enable-pthreads \
			--enable-static \
			--enable-version3 \
			--extra-cflags="$(CFLAGS)" \
			--extra-ldexeflags="$(LDEXEFLAGS)" \
			--extra-ldflags="$(LDFLAGS)" \
			--extra-libs="$(EXTRALIBS)" \
			--pkgconfigdir="$(WORKSPACE)/lib/pkgconfig" \
			--pkg-config-flags="--static" \
			--prefix="$(WORKSPACE)" \
			--extra-version="$(FFMPEG_EXTRA_VERSION)" && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@if [ -d "$(CWD)/.git.bak" ]; then mv "$(CWD)/.git.bak" "$(CWD)/.git"; fi
	@cd $(FFMPEG_SRCDIR) && echo "nightly-$$(git rev-parse --short HEAD)" > $@

else

# --- Release: download tagged tarball ---
$(PACKAGES)/FFmpeg-release-$(FFMPEG_VERSION).tar.gz: | dirs
	$(call download_file,https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n$(FFMPEG_VERSION).tar.gz,dd308201bb1239a1b73185f80c6b4121f4efdfa424a009ce544fd00bf736bb2e)

$(PACKAGES)/ffmpeg.done: $(PACKAGES)/FFmpeg-release-$(FFMPEG_VERSION).tar.gz $(FFMPEG_DEPS)
	@rm -rf $(PACKAGES)/FFmpeg-release-$(FFMPEG_VERSION) && mkdir -p $(PACKAGES)/FFmpeg-release-$(FFMPEG_VERSION)
	@tar -xf $< -C $(PACKAGES)/FFmpeg-release-$(FFMPEG_VERSION) --strip-components 1 || { rm -f $<; exit 1; }
	@if [ -d "$(CWD)/.git" ]; then mv "$(CWD)/.git" "$(CWD)/.git.bak"; fi
	cd $(PACKAGES)/FFmpeg-release-$(FFMPEG_VERSION) && \
		./configure $(CONFIGURE_OPTIONS) \
			--disable-debug \
			--disable-shared \
			--enable-pthreads \
			--enable-static \
			--enable-version3 \
			--extra-cflags="$(CFLAGS)" \
			--extra-ldexeflags="$(LDEXEFLAGS)" \
			--extra-ldflags="$(LDFLAGS)" \
			--extra-libs="$(EXTRALIBS)" \
			--pkgconfigdir="$(WORKSPACE)/lib/pkgconfig" \
			--pkg-config-flags="--static" \
			--prefix="$(WORKSPACE)" \
			--extra-version="$(FFMPEG_EXTRA_VERSION)" && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@if [ -d "$(CWD)/.git.bak" ]; then mv "$(CWD)/.git.bak" "$(CWD)/.git"; fi
	@echo "$(FFMPEG_VERSION)" > $@

endif # NIGHTLY
