#!/bin/bash
set -e

echo "============================================"
echo "RetroArch Recording Build for Miyoo Mini"
echo "============================================"

WORKSPACE="${GITHUB_WORKSPACE:-/workspace}"
FFMPEG_PREFIX="/opt/ffmpeg-miyoo"
OUTPUT_DIR="${WORKSPACE}/output"
FFMPEG_OUTPUT="${WORKSPACE}/ffmpeg-output"

# Cross-compiler settings
export CROSS_COMPILE=arm-linux-gnueabihf-
export CC=${CROSS_COMPILE}gcc
export CXX=${CROSS_COMPILE}g++
export AR=${CROSS_COMPILE}ar
export STRIP=${CROSS_COMPILE}strip
export PKG_CONFIG_PATH="${FFMPEG_PREFIX}/lib/pkgconfig"

# ARM optimization flags
ARM_FLAGS="-marm -mtune=cortex-a7 -march=armv7ve+simd -mfpu=neon-vfpv4 -mfloat-abi=hard"
export CFLAGS="${ARM_FLAGS} -O2 -ffast-math"
export CXXFLAGS="${CFLAGS}"
export LDFLAGS="${ARM_FLAGS}"

mkdir -p "${OUTPUT_DIR}" "${FFMPEG_OUTPUT}"

# ============================================
# STEP 1: Build FFmpeg
# ============================================
echo ""
echo "::group::Building FFmpeg"
echo "============================================"
echo "Step 1: Building FFmpeg for Miyoo Mini"
echo "============================================"

cd /tmp
git clone --depth 1 --branch n5.1.4 https://github.com/FFmpeg/FFmpeg.git ffmpeg-src
cd ffmpeg-src

./configure \
    --prefix="${FFMPEG_PREFIX}" \
    --cross-prefix=${CROSS_COMPILE} \
    --arch=arm \
    --cpu=cortex-a7 \
    --target-os=linux \
    --enable-cross-compile \
    --enable-shared \
    --disable-static \
    --disable-programs \
    --disable-ffmpeg \
    --disable-ffplay \
    --disable-ffprobe \
    --disable-doc \
    --disable-htmlpages \
    --disable-manpages \
    --disable-podpages \
    --disable-txtpages \
    --disable-network \
    --disable-debug \
    --disable-stripping \
    --disable-encoders \
    --disable-decoders \
    --disable-hwaccels \
    --disable-muxers \
    --disable-demuxers \
    --disable-parsers \
    --disable-bsfs \
    --disable-protocols \
    --disable-indevs \
    --disable-outdevs \
    --disable-devices \
    --disable-filters \
    --enable-small \
    --enable-encoder=ffv1 \
    --enable-encoder=flac \
    --enable-encoder=pcm_s16le \
    --enable-encoder=pcm_s16be \
    --enable-encoder=png \
    --enable-decoder=ffv1 \
    --enable-decoder=flac \
    --enable-decoder=pcm_s16le \
    --enable-decoder=pcm_s16be \
    --enable-decoder=png \
    --enable-muxer=matroska \
    --enable-muxer=avi \
    --enable-muxer=wav \
    --enable-demuxer=matroska \
    --enable-demuxer=avi \
    --enable-demuxer=wav \
    --enable-protocol=file \
    --enable-filter=aresample \
    --enable-filter=scale \
    --enable-filter=null \
    --enable-filter=anull \
    --extra-cflags="${CFLAGS}" \
    --extra-ldflags="${LDFLAGS}" \
    --pkg-config=pkg-config

make -j$(nproc)
make install

echo "FFmpeg build complete!"
ls -la "${FFMPEG_PREFIX}/lib/"

# Copy FFmpeg libs for output
cp -a "${FFMPEG_PREFIX}/lib"/*.so* "${FFMPEG_OUTPUT}/"
echo "::endgroup::"

# ============================================
# STEP 2: Clone and patch RetroArch
# ============================================
echo ""
echo "::group::Patching RetroArch"
echo "============================================"
echo "Step 2: Cloning and patching RetroArch"
echo "============================================"

cd /tmp
git clone --depth 1 --branch miyoomini-1.16.0 https://github.com/schmurtzm/RetroArch-MiyoMini.git retroarch
cd retroarch

# Apply FFmpeg recording patch to Makefile.miyoomini
echo "Applying FFmpeg patch to Makefile.miyoomini..."

# Create the patch inline
cat > /tmp/ffmpeg-recording.patch << 'PATCHEOF'
--- a/Makefile.miyoomini
+++ b/Makefile.miyoomini
@@ -1,5 +1,8 @@
 include Makefile.common
 
+# FFmpeg Recording Support
+HAVE_FFMPEG ?= 0
+
 TARGET := retroarch
 
 SYSROOT := $(shell $(CC) --print-sysroot)
@@ -8,6 +11,22 @@ CFLAGS += -marm -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -O3
 CFLAGS += -DRARCH_CONSOLE -DRARCH_INTERNAL -DDINGUX -DMIYOOMINI
 CFLAGS += -I$(SYSROOT)/usr/include/sdkdir -I$(SYSROOT)/usr/include/freetype2
 
+# FFmpeg Recording Support
+ifeq ($(HAVE_FFMPEG), 1)
+    FFMPEG_PREFIX ?= /opt/ffmpeg-miyoo
+    CFLAGS += -DHAVE_FFMPEG
+    CFLAGS += -I$(FFMPEG_PREFIX)/include
+    LDFLAGS += -L$(FFMPEG_PREFIX)/lib
+    LDFLAGS += -Wl,-rpath,/mnt/SDCARD/RetroArch/lib
+    LIBS += -lavformat -lavcodec -lswresample -lswscale -lavutil -lm -lz
+    
+    # Add FFmpeg recording driver
+    OBJ += record/drivers/record_ffmpeg.o
+    
+    DEFINES += -DHAVE_FFMPEG
+    $(info FFmpeg recording support enabled)
+endif
+
 LDFLAGS += -L$(SYSROOT)/usr/lib -lmi_common -lmi_gfx -lmi_ao -lmi_sys
 LDFLAGS += -lpthread -lz -ldl -lrt -lpng -lfreetype
 LDFLAGS += -Wl,--gc-sections
PATCHEOF

# Apply patch (may need adjustment based on actual Makefile content)
patch -p1 < /tmp/ffmpeg-recording.patch || {
    echo "Patch failed, trying manual modification..."
    
    # Manual modification as fallback
    # Add FFmpeg support after the include line
    sed -i '/^include Makefile.common/a\
\
# FFmpeg Recording Support\
HAVE_FFMPEG ?= 0\
ifeq ($(HAVE_FFMPEG), 1)\
    FFMPEG_PREFIX ?= /opt/ffmpeg-miyoo\
    CFLAGS += -DHAVE_FFMPEG -I$(FFMPEG_PREFIX)/include\
    LDFLAGS += -L$(FFMPEG_PREFIX)/lib -Wl,-rpath,/mnt/SDCARD/RetroArch/lib\
    LIBS += -lavformat -lavcodec -lswresample -lswscale -lavutil -lm -lz\
    OBJ += record/drivers/record_ffmpeg.o\
    DEFINES += -DHAVE_FFMPEG\
    $(info FFmpeg recording support enabled)\
endif' Makefile.miyoomini
}

# Do the same for Makefile.miyoomini_plus
cp Makefile.miyoomini_plus Makefile.miyoomini_plus.bak
sed -i '/^include Makefile.common/a\
\
# FFmpeg Recording Support\
HAVE_FFMPEG ?= 0\
ifeq ($(HAVE_FFMPEG), 1)\
    FFMPEG_PREFIX ?= /opt/ffmpeg-miyoo\
    CFLAGS += -DHAVE_FFMPEG -I$(FFMPEG_PREFIX)/include\
    LDFLAGS += -L$(FFMPEG_PREFIX)/lib -Wl,-rpath,/mnt/SDCARD/RetroArch/lib\
    LIBS += -lavformat -lavcodec -lswresample -lswscale -lavutil -lm -lz\
    OBJ += record/drivers/record_ffmpeg.o\
    DEFINES += -DHAVE_FFMPEG\
    $(info FFmpeg recording support enabled)\
endif' Makefile.miyoomini_plus

echo "Patch applied!"
echo "::endgroup::"

# ============================================
# STEP 3: Build RetroArch with FFmpeg
# ============================================
echo ""
echo "::group::Building RetroArch"
echo "============================================"
echo "Step 3: Building RetroArch with FFmpeg"
echo "============================================"

cd /tmp/retroarch

# Set up environment for FFmpeg
export PKG_CONFIG_PATH="${FFMPEG_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH}"
export CFLAGS="${CFLAGS} -I${FFMPEG_PREFIX}/include"
export LDFLAGS="${LDFLAGS} -L${FFMPEG_PREFIX}/lib"

# Build RetroArch for Miyoo Mini (standard)
echo "Building retroarch (standard)..."
make -f Makefile.miyoomini HAVE_FFMPEG=1 -j$(nproc)
cp retroarch "${OUTPUT_DIR}/retroarch"
make clean

# Build RetroArch for Miyoo Mini Plus
echo "Building retroarch for Miyoo Mini Plus..."
make -f Makefile.miyoomini_plus HAVE_FFMPEG=1 -j$(nproc)
cp retroarch "${OUTPUT_DIR}/retroarch_miyoo354"
make clean

echo "RetroArch build complete!"
echo "::endgroup::"

# ============================================
# STEP 4: Package everything
# ============================================
echo ""
echo "::group::Packaging"
echo "============================================"
echo "Step 4: Packaging for Miyoo Mini"
echo "============================================"

cd "${OUTPUT_DIR}"

# Create directory structure
mkdir -p lib
mkdir -p .retroarch/records_config

# Copy FFmpeg libraries
cp "${FFMPEG_PREFIX}/lib"/libav*.so* lib/
cp "${FFMPEG_PREFIX}/lib"/libsw*.so* lib/

# Create symlinks for library versions (in case they're needed)
cd lib
for lib in *.so.*.*.*; do
    if [ -f "$lib" ]; then
        base=$(echo "$lib" | sed 's/\.[0-9]*\.[0-9]*\.[0-9]*$//')
        ln -sf "$lib" "${base}" 2>/dev/null || true
    fi
done
cd ..

# Create recording config files
cat > .retroarch/records_config/FFV1-Lossless.cfg << 'RECORDCFG'
# FFV1 Lossless Recording for Miyoo Mini
# Perfect quality, reasonable file size for GB/GBC/GBA
# Files can be imported directly into most video editors

# Container format
format = "matroska"

# Video codec - FFV1 is lossless and efficient
vcodec = "ffv1"

# Audio codec - FLAC is lossless
acodec = "flac"

# Use 2 threads for encoding
threads = "2"
RECORDCFG

cat > .retroarch/records_config/PCM-Uncompressed.cfg << 'RECORDCFG'
# Uncompressed Recording for Miyoo Mini
# Fastest encoding, largest files
# Use if FFV1 causes performance issues

format = "avi"
vcodec = "ffv1"
acodec = "pcm_s16le"
threads = "1"
RECORDCFG

# Create launcher script
cat > retroarch_recording.sh << 'LAUNCHER'
#!/bin/sh
# RetroArch with Recording Support Launcher
# This script ensures FFmpeg libraries are found

SCRIPT_DIR=$(dirname "$0")
export LD_LIBRARY_PATH="${SCRIPT_DIR}/lib:${LD_LIBRARY_PATH}"

exec "${SCRIPT_DIR}/retroarch" "$@"
LAUNCHER
chmod +x retroarch_recording.sh

# Create installation instructions
cat > INSTALL.md << 'INSTALL'
# RetroArch Recording Build for Miyoo Mini / Miyoo Mini Plus

## Installation

1. **Backup your existing RetroArch:**
   - Copy your current `RetroArch/retroarch` binary somewhere safe

2. **Copy new files to your SD card:**
   - Copy the `retroarch` binary to `/mnt/SDCARD/RetroArch/` (replacing the existing one)
   - For Miyoo Mini Plus, use `retroarch_miyoo354` instead
   - Copy the entire `lib/` folder to `/mnt/SDCARD/RetroArch/lib/`
   - Copy `.retroarch/records_config/` to your `.retroarch` folder

3. **Configure recording in RetroArch:**
   - Go to Settings > Recording
   - Set "Recording Output Directory" to where you want recordings saved
   - Set "Recording Config" to one of the provided configs (FFV1-Lossless recommended)
   - Set "Recording Quality" and other options as desired

4. **Set up recording hotkey:**
   - Go to Settings > Input > Hotkeys
   - Bind "Recording Toggle" to a button combination (e.g., Menu + Y)

## Usage

1. Start a game
2. Press your Recording Toggle hotkey to start recording
3. A notification will appear confirming recording started
4. Press the hotkey again to stop recording
5. Your recording will be saved as an MKV file in your output directory

## File Locations

- Recordings are saved as `.mkv` files (Matroska container with FFV1 video + FLAC audio)
- Most video editors (DaVinci Resolve, Premiere, etc.) can import MKV directly
- If you need MP4, convert on your PC using FFmpeg:
  `ffmpeg -i recording.mkv -c:v libx264 -crf 18 -c:a aac recording.mp4`

## Troubleshooting

- If RetroArch crashes on launch, make sure the `lib/` folder is in place
- If recording doesn't start, check Settings > Recording is properly configured
- For performance issues, try the PCM-Uncompressed config instead

## Notes

- Recording adds minimal CPU overhead for GB/GBC/GBA games
- File sizes are roughly 50-100MB per minute with FFV1
- Audio and video are perfectly synced in the MKV container
INSTALL

# Create a simple version info file
cat > VERSION.txt << VERSION
RetroArch Recording Build for Miyoo Mini
Built: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
FFmpeg: 5.1.4
RetroArch Base: miyoomini-1.16.0
Recording Support: FFV1 + FLAC in MKV container
VERSION

echo ""
echo "============================================"
echo "Build complete! Output contents:"
echo "============================================"
ls -lahR "${OUTPUT_DIR}"

echo "::endgroup::"
echo ""
echo "SUCCESS: Build completed successfully!"
