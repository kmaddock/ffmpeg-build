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

# macOS: VideoToolbox
ifeq ($(UNAME),Darwin)
  CONFIGURE_OPTIONS += --enable-videotoolbox
endif

# Small build
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

# --- Conditional: python3 ---
ifdef HAS_PYTHON3
  FFMPEG_DEPS += $(PACKAGES)/glslang.done
  CONFIGURE_OPTIONS += --enable-libglslang
endif

# --- Conditional: meson + ninja ---
ifneq ($(and $(HAS_MESON),$(HAS_NINJA)),)
  FFMPEG_DEPS += $(PACKAGES)/dav1d.done
  CONFIGURE_OPTIONS += --enable-libdav1d
endif

# --- Conditional: cargo ---
ifdef HAS_CARGO
  FFMPEG_DEPS += $(PACKAGES)/rav1e.done
  CONFIGURE_OPTIONS += --enable-librav1e
endif

# --- Conditional: NONFREE_AND_GPL ---
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

# --- Conditional: LV2 (requires meson + ninja, not disabled) ---
ifneq ($(DISABLE_LV2),1)
  ifneq ($(and $(HAS_MESON),$(HAS_NINJA)),)
    FFMPEG_DEPS += $(PACKAGES)/lilv.done
    CONFIGURE_OPTIONS += --enable-lv2
    CFLAGS += -I$(WORKSPACE)/include/lilv-0
  endif
endif

# --- Conditional: Linux-only ---
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
# Download macro
# =============================================================================
# Usage: $(call download,URL,FILENAME)           — extracts with --strip-components 1
#        $(call download,URL,FILENAME,DIRNAME)    — extracts into DIRNAME without stripping
#
# If FILENAME is empty, derives it from the URL.
# After download+extract, cd's into the extracted directory.
define download
	@mkdir -p $(PACKAGES)
	$(eval _dl_url := $(1))
	$(eval _dl_file := $(if $(2),$(2),$(notdir $(1))))
	$(eval _dl_stem := $(basename $(basename $(_dl_file))))
	$(eval _dl_dir := $(if $(3),$(3),$(_dl_stem)))
	@if [ ! -f "$(PACKAGES)/$(_dl_file)" ] || [ ! -s "$(PACKAGES)/$(_dl_file)" ]; then \
		echo "Downloading $(_dl_url) as $(_dl_file)"; \
		RETRIES=0; SUCCESS=false; \
		while [ $$RETRIES -le 2 ]; do \
			curl -L --silent -o "$(PACKAGES)/$(_dl_file)" "$(_dl_url)" && \
			[ -s "$(PACKAGES)/$(_dl_file)" ] && SUCCESS=true && break; \
			RETRIES=$$((RETRIES + 1)); \
			echo "Retry $$RETRIES..."; \
		done; \
		if [ "$$SUCCESS" != true ]; then echo "Failed to download $(_dl_url)"; exit 1; fi; \
	else \
		echo "$(_dl_file) already downloaded."; \
	fi
	@rm -rf "$(PACKAGES)/$(_dl_dir)" && mkdir -p "$(PACKAGES)/$(_dl_dir)"
	@if [ -n "$(3)" ]; then \
		tar -xf "$(PACKAGES)/$(_dl_file)" -C "$(PACKAGES)/$(_dl_dir)" 2>/dev/null; \
	else \
		tar -xf "$(PACKAGES)/$(_dl_file)" -C "$(PACKAGES)/$(_dl_dir)" --strip-components 1 2>/dev/null; \
	fi
	@echo "Extracted $(_dl_file)"
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
# Foundation libraries
# =============================================================================

$(PACKAGES)/zlib.done: | dirs
	$(call download,https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.gz)
	cd $(PACKAGES)/zlib-1.3.2 && \
		./configure --static --prefix="$(WORKSPACE)" && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "1.3.2" > $@

$(PACKAGES)/giflib.done: | dirs
	$(call download,https://sf-eu-introserv-1.dl.sourceforge.net/project/giflib/giflib-5.x/giflib-5.2.2.tar.gz)
	cd $(PACKAGES)/giflib-5.2.2 && \
		sed 's/$$(MAKE) -C doc//g' Makefile > Makefile.patched && \
		rm Makefile && \
		sed 's/install: all install-bin install-include install-lib install-man/install: all install-bin install-include install-lib/g' Makefile.patched > Makefile && \
		$(MAKE) && \
		$(MAKE) PREFIX="$(WORKSPACE)" install
	@echo "5.2.2" > $@

# =============================================================================
# Conditional: TLS / crypto
# =============================================================================

ifeq ($(NONFREE_AND_GPL),1)

$(PACKAGES)/gettext.done: | dirs
	$(call download,https://ftpmirror.gnu.org/gettext/gettext-1.0.tar.gz)
	cd $(PACKAGES)/gettext-1.0 && \
		./configure --prefix="$(WORKSPACE)" --enable-static --disable-shared && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "1.0" > $@

$(PACKAGES)/openssl.done: $(PACKAGES)/zlib.done | dirs
	$(call download,https://github.com/openssl/openssl/archive/refs/tags/openssl-3.6.1.tar.gz,openssl-3.6.1.tar.gz)
	cd $(PACKAGES)/openssl-3.6.1 && \
		./Configure --prefix="$(WORKSPACE)" --openssldir="$(WORKSPACE)" --libdir="lib" \
			--with-zlib-include="$(WORKSPACE)"/include/ --with-zlib-lib="$(WORKSPACE)"/lib \
			no-shared zlib && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install_sw
	@echo "3.6.1" > $@

else

$(PACKAGES)/gmp.done: | dirs
	$(call download,https://ftpmirror.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz)
	cd $(PACKAGES)/gmp-6.3.0 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "6.3.0" > $@

$(PACKAGES)/nettle.done: $(PACKAGES)/gmp.done | dirs
	$(call download,https://ftpmirror.gnu.org/gnu/nettle/nettle-3.10.2.tar.gz)
	cd $(PACKAGES)/nettle-3.10.2 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static \
			--disable-openssl --disable-documentation --libdir="$(WORKSPACE)"/lib \
			CPPFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)" && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "3.10.2" > $@

endif

# =============================================================================
# Video libraries
# =============================================================================

$(PACKAGES)/dav1d.done: | dirs
ifdef MACOS_SILICON
	$(call download,https://code.videolan.org/videolan/dav1d/-/archive/1.5.3/dav1d-1.5.3.tar.gz)
	cd $(PACKAGES)/dav1d-1.5.3 && \
		rm -rf build && mkdir -p build && \
		CFLAGS="-arch arm64" meson build --prefix="$(WORKSPACE)" --buildtype=release --default-library=static --libdir="$(WORKSPACE)"/lib && \
		ninja -C build && \
		ninja -C build install
else
	$(call download,https://code.videolan.org/videolan/dav1d/-/archive/1.5.3/dav1d-1.5.3.tar.gz)
	cd $(PACKAGES)/dav1d-1.5.3 && \
		rm -rf build && mkdir -p build && \
		meson build --prefix="$(WORKSPACE)" --buildtype=release --default-library=static --libdir="$(WORKSPACE)"/lib && \
		ninja -C build && \
		ninja -C build install
endif
	@echo "1.5.3" > $@

$(PACKAGES)/svtav1.done: | dirs
	$(call download,https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v4.0.1/SVT-AV1-v4.0.1.tar.gz,svtav1-4.0.1.tar.gz)
	cd $(PACKAGES)/svtav1-4.0.1/Build/linux && \
		cmake -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" -DENABLE_SHARED=off -DBUILD_SHARED_LIBS=OFF \
			../.. -G"Unix Makefiles" -DCMAKE_BUILD_TYPE=Release && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install && \
		cp SvtAv1Enc.pc "$(WORKSPACE)/lib/pkgconfig/"
	@echo "4.0.1" > $@

$(PACKAGES)/rav1e.done: | dirs
	$(call download,https://github.com/xiph/rav1e/archive/refs/tags/v0.8.1.tar.gz)
	cd $(PACKAGES)/v0.8.1 && \
		cargo install cargo-c && \
		export RUSTFLAGS="-C target-cpu=native" && \
		cargo cinstall --prefix="$(WORKSPACE)" --libdir=lib --library-type=staticlib --crt-static --release
	@echo "0.8.1" > $@

ifeq ($(NONFREE_AND_GPL),1)

$(PACKAGES)/x264.done: | dirs
	$(call download,https://code.videolan.org/videolan/x264/-/archive/0480cb05/x264-0480cb05.tar.gz,x264-0480cb05.tar.gz)
ifeq ($(UNAME),Linux)
	cd $(PACKAGES)/x264-0480cb05 && \
		./configure --prefix="$(WORKSPACE)" --enable-static --enable-pic CXXFLAGS="-fPIC $(CXXFLAGS)" && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install && \
		$(MAKE) install-lib-static
else
	cd $(PACKAGES)/x264-0480cb05 && \
		./configure --prefix="$(WORKSPACE)" --enable-static --enable-pic && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install && \
		$(MAKE) install-lib-static
endif
	@echo "0480cb05" > $@

$(PACKAGES)/x265.done: | dirs
	$(call download,https://bitbucket.org/multicoreware/x265_git/get/8be7dbf8159ddfceea4115675a6d48e1611b8baa.tar.gz,x265-8be7dbf.tar.gz)
	cd $(PACKAGES)/x265-8be7dbf && \
		cd build/linux && \
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

$(PACKAGES)/xvidcore.done: | dirs
	$(call download,https://downloads.xvid.com/downloads/xvidcore-1.3.7.tar.gz)
	cd $(PACKAGES)/xvidcore-1.3.7/build/generic && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install && \
		rm -f "$(WORKSPACE)/lib/libxvidcore.4.dylib" && \
		rm -f "$(WORKSPACE)"/lib/libxvidcore.so*
	@echo "1.3.7" > $@

$(PACKAGES)/vid_stab.done: | dirs
	$(call download,https://github.com/georgmartius/vid.stab/archive/v1.1.1.tar.gz,vid.stab-1.1.1.tar.gz)
ifdef MACOS_SILICON
	cd $(PACKAGES)/vid.stab-1.1.1 && \
		curl -L --silent -o fix_cmake_quoting.patch \
			"https://raw.githubusercontent.com/Homebrew/formula-patches/5bf1a0e0cfe666ee410305cece9c9c755641bfdf/libvidstab/fix_cmake_quoting.patch" && \
		patch -p1 < fix_cmake_quoting.patch && \
		cmake -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" -DUSE_OMP=OFF -DENABLE_SHARED=off . && \
		$(MAKE) && $(MAKE) install
else
	cd $(PACKAGES)/vid.stab-1.1.1 && \
		cmake -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" -DUSE_OMP=OFF -DENABLE_SHARED=off . && \
		$(MAKE) && $(MAKE) install
endif
	@echo "1.1.1" > $@

$(PACKAGES)/fdk_aac.done: | dirs
	$(call download,https://sourceforge.net/projects/opencore-amr/files/fdk-aac/fdk-aac-2.0.3.tar.gz/download?use_mirror=gigenet,fdk-aac-2.0.3.tar.gz)
	cd $(PACKAGES)/fdk-aac-2.0.3 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static --enable-pic && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "2.0.3" > $@

$(PACKAGES)/srt.done: $(PACKAGES)/openssl.done | dirs
	$(call download,https://github.com/Haivision/srt/archive/v1.5.4.tar.gz,srt-1.5.4.tar.gz)
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

$(PACKAGES)/zvbi.done: $(PACKAGES)/libpng.done | dirs
	$(call download,https://github.com/zapping-vbi/zvbi/archive/refs/tags/v0.2.44.tar.gz,zvbi-0.2.44.tar.gz)
	cd $(PACKAGES)/zvbi-0.2.44 && \
		./autogen.sh --prefix="$(WORKSPACE)" && \
		./configure CFLAGS="-I$(WORKSPACE)/include/libpng16 $(CFLAGS)" \
			--prefix="$(WORKSPACE)" --enable-static --disable-shared && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "0.2.44" > $@

endif # NONFREE_AND_GPL

$(PACKAGES)/libvpx.done: | dirs
	$(call download,https://github.com/webmproject/libvpx/archive/refs/tags/v1.16.0.tar.gz,libvpx-1.16.0.tar.gz)
ifeq ($(UNAME),Darwin)
	cd $(PACKAGES)/libvpx-1.16.0 && \
		sed "s/,--version-script//g" build/make/Makefile > build/make/Makefile.patched && \
		sed "s/-Wl,--no-undefined -Wl,-soname/-Wl,-undefined,error -Wl,-install_name/g" build/make/Makefile.patched > build/make/Makefile && \
		./configure --prefix="$(WORKSPACE)" --disable-unit-tests --disable-shared --disable-examples --as=yasm --enable-vp9-highbitdepth && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
else
	cd $(PACKAGES)/libvpx-1.16.0 && \
		./configure --prefix="$(WORKSPACE)" --disable-unit-tests --disable-shared --disable-examples --as=yasm --enable-vp9-highbitdepth && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
endif
	@echo "1.16.0" > $@

$(PACKAGES)/av1.done: | dirs
	$(call download,https://aomedia.googlesource.com/aom/+archive/refs/tags/v3.12.0.tar.gz,av1-3.12.0.tar.gz,av1)
	rm -rf $(PACKAGES)/aom_build && mkdir -p $(PACKAGES)/aom_build
	cd $(PACKAGES)/aom_build && \
		cmake -DENABLE_TESTS=0 -DENABLE_EXAMPLES=0 \
			-DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" -DCMAKE_INSTALL_LIBDIR=lib \
			$(if $(MACOS_SILICON),-DCONFIG_RUNTIME_CPU_DETECT=0) \
			$(PACKAGES)/av1 && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "3.12.0" > $@

$(PACKAGES)/zimg.done: | dirs
	$(call download,https://github.com/sekrit-twc/zimg/archive/refs/tags/release-3.0.6.tar.gz,zimg-3.0.6.tar.gz,zimg)
	cd $(PACKAGES)/zimg/zimg-release-3.0.6 && \
		$(LIBTOOLIZE) -i -f -q && \
		./autogen.sh --prefix="$(WORKSPACE)" && \
		./configure --prefix="$(WORKSPACE)" --enable-static --disable-shared && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "3.0.6" > $@

# =============================================================================
# Audio libraries
# =============================================================================

$(PACKAGES)/opencore.done: | dirs
	$(call download,https://deac-ams.dl.sourceforge.net/project/opencore-amr/opencore-amr/opencore-amr-0.1.6.tar.gz,opencore-amr-0.1.6.tar.gz)
	cd $(PACKAGES)/opencore-amr-0.1.6 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "0.1.6" > $@

$(PACKAGES)/lame.done: | dirs
	$(call download,https://sourceforge.net/projects/lame/files/lame/3.100/lame-3.100.tar.gz/download?use_mirror=gigenet,lame-3.100.tar.gz)
	cd $(PACKAGES)/lame-3.100 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "3.100" > $@

$(PACKAGES)/opus.done: | dirs
	$(call download,https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz)
	cd $(PACKAGES)/opus-1.6.1 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "1.6.1" > $@

$(PACKAGES)/libogg.done: | dirs
	$(call download,https://ftp.osuosl.org/pub/xiph/releases/ogg/libogg-1.3.6.tar.xz)
	cd $(PACKAGES)/libogg-1.3.6 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "1.3.6" > $@

$(PACKAGES)/libvorbis.done: $(PACKAGES)/libogg.done | dirs
	$(call download,https://ftp.osuosl.org/pub/xiph/releases/vorbis/libvorbis-1.3.7.tar.gz)
	cd $(PACKAGES)/libvorbis-1.3.7 && \
		sed 's/-force_cpusubtype_ALL//g' configure.ac > configure.ac.patched && \
		rm configure.ac && mv configure.ac.patched configure.ac && \
		./autogen.sh --prefix="$(WORKSPACE)" && \
		./configure --prefix="$(WORKSPACE)" --with-ogg-libraries="$(WORKSPACE)"/lib \
			--with-ogg-includes="$(WORKSPACE)"/include/ --enable-static --disable-shared --disable-oggtest && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "1.3.7" > $@

$(PACKAGES)/libtheora.done: $(PACKAGES)/libogg.done $(PACKAGES)/libvorbis.done | dirs
	$(call download,https://ftp.osuosl.org/pub/xiph/releases/theora/libtheora-1.2.0.tar.gz)
	cd $(PACKAGES)/libtheora-1.2.0 && \
		./configure --prefix="$(WORKSPACE)" \
			--with-ogg-libraries="$(WORKSPACE)"/lib --with-ogg-includes="$(WORKSPACE)"/include/ \
			--with-vorbis-libraries="$(WORKSPACE)"/lib --with-vorbis-includes="$(WORKSPACE)"/include/ \
			--enable-static --disable-shared --disable-oggtest --disable-vorbistest \
			--disable-examples --disable-spec && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "1.2.0" > $@

$(PACKAGES)/soxr.done: | dirs
	$(call download,https://sourceforge.net/projects/soxr/files/soxr-0.1.3-Source.tar.xz/download?use_mirror=gigenet,soxr-0.1.3.tar.xz)
	cd $(PACKAGES)/soxr-0.1.3 && \
		mkdir -p build && cd build && \
		cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" \
			-DBUILD_SHARED_LIBS:bool=off -DWITH_OPENMP:bool=off -DBUILD_TESTS:bool=off -Wno-dev .. && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "0.1.3" > $@

# --- LV2 chain ---
ifneq ($(DISABLE_LV2),1)
ifneq ($(and $(HAS_MESON),$(HAS_NINJA)),)

$(PACKAGES)/lv2.done: | dirs
	$(call download,https://lv2plug.in/spec/lv2-1.18.10.tar.xz,lv2-1.18.10.tar.xz)
	cd $(PACKAGES)/lv2-1.18.10 && \
		meson build --prefix="$(WORKSPACE)" --buildtype=release --default-library=static --libdir="$(WORKSPACE)"/lib && \
		ninja -C build && \
		ninja -C build install
	@echo "1.18.10" > $@

$(PACKAGES)/serd.done: | dirs
	$(call download,https://gitlab.com/drobilla/serd/-/archive/v0.32.8/serd-v0.32.8.tar.gz,serd-v0.32.8.tar.gz)
	cd $(PACKAGES)/serd-v0.32.8 && \
		meson build --prefix="$(WORKSPACE)" --buildtype=release --default-library=static --libdir="$(WORKSPACE)"/lib && \
		ninja -C build && \
		ninja -C build install
	@echo "0.32.8" > $@

$(PACKAGES)/pcre.done: | dirs
	$(call download,https://altushost-swe.dl.sourceforge.net/project/pcre/pcre/8.45/pcre-8.45.tar.gz,pcre-8.45.tar.gz)
	cd $(PACKAGES)/pcre-8.45 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "8.45" > $@

$(PACKAGES)/zix.done: | dirs
	$(call download,https://gitlab.com/drobilla/zix/-/archive/v0.8.0/zix-v0.8.0.tar.gz,zix-v0.8.0.tar.gz)
	cd $(PACKAGES)/zix-v0.8.0 && \
		meson setup build --prefix="$(WORKSPACE)" --buildtype=release --default-library=static --libdir="$(WORKSPACE)"/lib && \
		cd build && \
		meson configure -Dc_args="-march=native" -Dprefix="$(WORKSPACE)" -Dlibdir="$(WORKSPACE)"/lib && \
		meson compile && \
		meson install
	@echo "0.8.0" > $@

$(PACKAGES)/sord.done: $(PACKAGES)/serd.done $(PACKAGES)/zix.done | dirs
	$(call download,https://gitlab.com/drobilla/sord/-/archive/v0.16.22/sord-v0.16.22.tar.gz,sord-v0.16.22.tar.gz)
	cd $(PACKAGES)/sord-v0.16.22 && \
		meson build --prefix="$(WORKSPACE)" --buildtype=release --default-library=static --libdir="$(WORKSPACE)"/lib && \
		ninja -C build && \
		ninja -C build install
	@echo "0.16.22" > $@

$(PACKAGES)/sratom.done: $(PACKAGES)/sord.done $(PACKAGES)/lv2.done | dirs
	$(call download,https://gitlab.com/lv2/sratom/-/archive/v0.6.22/sratom-v0.6.22.tar.gz,sratom-v0.6.22.tar.gz)
	cd $(PACKAGES)/sratom-v0.6.22 && \
		meson build --prefix="$(WORKSPACE)" -Ddocs=disabled --buildtype=release --default-library=static --libdir="$(WORKSPACE)"/lib && \
		ninja -C build && \
		ninja -C build install
	@echo "0.6.22" > $@

$(PACKAGES)/lilv.done: $(PACKAGES)/sratom.done | dirs
	$(call download,https://gitlab.com/lv2/lilv/-/archive/v0.26.4/lilv-v0.26.4.tar.gz,lilv-v0.26.4.tar.gz)
	cd $(PACKAGES)/lilv-v0.26.4 && \
		meson build --prefix="$(WORKSPACE)" -Ddocs=disabled --buildtype=release --default-library=static \
			--libdir="$(WORKSPACE)"/lib -Dcpp_std=c++11 && \
		ninja -C build && \
		ninja -C build install
	@echo "0.26.4" > $@

endif # HAS_MESON
endif # DISABLE_LV2

# =============================================================================
# Image libraries
# =============================================================================

$(PACKAGES)/libtiff.done: $(PACKAGES)/zlib.done | dirs
	$(call download,https://download.osgeo.org/libtiff/tiff-4.7.1.tar.xz)
	cd $(PACKAGES)/tiff-4.7.1 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static \
			--disable-dependency-tracking --disable-lzma --disable-webp --disable-zstd --without-x && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "4.7.1" > $@

$(PACKAGES)/libpng.done: $(PACKAGES)/zlib.done | dirs
	$(call download,https://sourceforge.net/projects/libpng/files/libpng16/1.6.55/libpng-1.6.55.tar.gz,libpng-1.6.55.tar.gz)
	cd $(PACKAGES)/libpng-1.6.55 && \
		LDFLAGS="$(LDFLAGS)" CPPFLAGS="$(CFLAGS)" \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "1.6.55" > $@

$(PACKAGES)/lcms2.done: | dirs
	$(call download,https://github.com/mm2/Little-CMS/releases/download/lcms2.18/lcms2-2.18.tar.gz)
	cd $(PACKAGES)/lcms2-2.18 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "2.18" > $@

$(PACKAGES)/libjxl.done: $(PACKAGES)/lcms2.done | dirs
	$(call download,https://github.com/libjxl/libjxl/archive/refs/tags/v0.11.2.tar.gz,libjxl-0.11.2.tar.gz)
	cd $(PACKAGES)/libjxl-0.11.2 && \
		sed "s/-ljxl_threads/-ljxl_threads @JPEGXL_THREADS_PUBLIC_LIBS@/g" lib/threads/libjxl_threads.pc.in > lib/threads/libjxl_threads.pc.in.patched && \
		rm lib/threads/libjxl_threads.pc.in && mv lib/threads/libjxl_threads.pc.in.patched lib/threads/libjxl_threads.pc.in && \
		sed 's/set(JPEGXL_REQUIRES_TYPE "Requires")/set(JPEGXL_REQUIRES_TYPE "Requires")\n  set(JPEGXL_THREADS_PUBLIC_LIBS "-lm $${PKGCONFIG_CXX_LIB}")/g' lib/jxl_threads.cmake > lib/jxl_threads.cmake.patched && \
		rm lib/jxl_threads.cmake && mv lib/jxl_threads.cmake.patched lib/jxl_threads.cmake && \
		./deps.sh && \
		cmake -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" \
			-DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_BINDIR=bin -DCMAKE_INSTALL_INCLUDEDIR=include \
			-DENABLE_SHARED=off -DENABLE_STATIC=ON -DCMAKE_BUILD_TYPE=Release \
			-DJPEGXL_ENABLE_BENCHMARK=OFF -DJPEGXL_ENABLE_DOXYGEN=OFF -DJPEGXL_ENABLE_MANPAGES=OFF \
			-DJPEGXL_ENABLE_JPEGLI_LIBJPEG=OFF -DJPEGXL_ENABLE_JPEGLI=ON \
			-DJPEGXL_TEST_TOOLS=OFF -DJPEGXL_ENABLE_JNI=OFF -DBUILD_TESTING=OFF \
			-DJPEGXL_ENABLE_SKCMS=OFF . && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "0.11.2" > $@

$(PACKAGES)/libwebp.done: | dirs
	$(call download,https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz,libwebp-1.6.0.tar.gz)
	cd $(PACKAGES)/libwebp-1.6.0 && \
		rm -rf build && mkdir -p build && cd build && \
		cmake -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" -DCMAKE_INSTALL_LIBDIR=lib \
			-DCMAKE_INSTALL_BINDIR=bin -DCMAKE_INSTALL_INCLUDEDIR=include \
			-DENABLE_SHARED=OFF -DENABLE_STATIC=ON \
			-DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF \
			-DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF ../ && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "1.6.0" > $@

# =============================================================================
# Other libraries
# =============================================================================

$(PACKAGES)/libsdl.done: | dirs
	$(call download,https://github.com/libsdl-org/SDL/releases/download/release-2.30.12/SDL2-2.30.12.tar.gz)
	cd $(PACKAGES)/SDL2-2.30.12 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "2.30.12" > $@

$(PACKAGES)/FreeType2.done: | dirs
	$(call download,https://downloads.sourceforge.net/freetype/freetype-2.14.2.tar.xz)
	cd $(PACKAGES)/freetype-2.14.2 && \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "2.14.2" > $@

$(PACKAGES)/VapourSynth.done: | dirs
	$(call download,https://github.com/vapoursynth/vapoursynth/archive/R73.tar.gz)
	cd $(PACKAGES)/R73 && \
		mkdir -p "$(WORKSPACE)/include/vapoursynth" && \
		cp -r include/. "$(WORKSPACE)/include/vapoursynth/"
	@echo "73" > $@

$(PACKAGES)/libzmq.done: | dirs
	$(call download,https://github.com/zeromq/libzmq/releases/download/v4.3.5/zeromq-4.3.5.tar.gz)
	cd $(PACKAGES)/zeromq-4.3.5 && \
		$(if $(filter Darwin,$(UNAME)),export XML_CATALOG_FILES=/usr/local/etc/xml/catalog &&) \
		./configure --prefix="$(WORKSPACE)" --disable-shared --enable-static && \
		sed "s/stats_proxy stats = {0}/stats_proxy stats = {{{0, 0}, {0, 0}}, {{0, 0}, {0, 0}}}/g" src/proxy.cpp > src/proxy.cpp.patched && \
		rm src/proxy.cpp && mv src/proxy.cpp.patched src/proxy.cpp && \
		$(MAKE) -j $(MJOBS) && \
		$(MAKE) install
	@echo "4.3.5" > $@

$(PACKAGES)/vulkan-headers.done: | dirs
	$(call download,https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/vulkan-sdk-1.4.341.0.tar.gz,Vulkan-Headers-1.4.341.0.tar.gz)
	cd $(PACKAGES)/Vulkan-Headers-1.4.341.0 && \
		cmake -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" -B build/ && \
		cd build/ && $(MAKE) install
	@echo "1.4.341.0" > $@

$(PACKAGES)/glslang.done: | dirs
	$(call download,https://github.com/KhronosGroup/glslang/archive/refs/tags/16.2.0.tar.gz,glslang-16.2.0.tar.gz)
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
$(PACKAGES)/nv-codec.done: | dirs
	$(call download,https://github.com/FFmpeg/nv-codec-headers/releases/download/n13.0.19.0/nv-codec-headers-13.0.19.0.tar.gz)
	cd $(PACKAGES)/nv-codec-headers-13.0.19.0 && \
		$(MAKE) PREFIX="$(WORKSPACE)" && \
		$(MAKE) PREFIX="$(WORKSPACE)" install
	@echo "13.0.19.0" > $@
endif

$(PACKAGES)/amf.done: | dirs
	$(call download,https://github.com/GPUOpen-LibrariesAndSDKs/AMF/archive/refs/tags/v1.5.0.tar.gz,AMF-1.5.0.tar.gz,AMF-1.5.0)
	rm -rf "$(WORKSPACE)/include/AMF"
	mkdir -p "$(WORKSPACE)/include/AMF"
	cp -r "$(PACKAGES)/AMF-1.5.0/AMF-1.5.0/amf/public/include/"* "$(WORKSPACE)/include/AMF/"
	@echo "1.5.0" > $@

$(PACKAGES)/opencl-headers.done: | dirs
	$(call download,https://github.com/KhronosGroup/OpenCL-Headers/archive/refs/tags/v2025.07.22.tar.gz,OpenCL-Headers-2025.07.22.tar.gz)
	cd $(PACKAGES)/OpenCL-Headers-2025.07.22 && \
		cmake -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" -B build/ && \
		cmake --build build --target install
	@echo "2025.07.22" > $@

$(PACKAGES)/opencl-icd-loader.done: $(PACKAGES)/opencl-headers.done | dirs
	$(call download,https://github.com/KhronosGroup/OpenCL-ICD-Loader/archive/refs/tags/v2025.07.22.tar.gz,OpenCL-ICD-Loader-2025.07.22.tar.gz)
	cd $(PACKAGES)/OpenCL-ICD-Loader-2025.07.22 && \
		cmake -DCMAKE_PREFIX_PATH="$(WORKSPACE)" -DCMAKE_INSTALL_PREFIX="$(WORKSPACE)" \
			-DENABLE_SHARED=OFF -DBUILD_SHARED_LIBS=OFF -B build/ && \
		cmake --build build --target install
	@echo "2025.07.22" > $@

endif # Linux

# =============================================================================
# FFmpeg
# =============================================================================

FFMPEG_EXTRA_VERSION :=
ifeq ($(UNAME),Darwin)
  FFMPEG_EXTRA_VERSION := $(FFMPEG_VERSION)
endif

$(PACKAGES)/ffmpeg.done: $(FFMPEG_DEPS) | dirs
	$(call download,https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n$(FFMPEG_VERSION).tar.gz,FFmpeg-release-$(FFMPEG_VERSION).tar.gz)
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
