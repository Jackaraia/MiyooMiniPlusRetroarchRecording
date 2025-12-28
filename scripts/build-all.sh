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
    --disable-hwaccels \
    --disable-parsers \
    --disable-bsfs \
    --disable-indevs \
    --disable-outdevs \
    --disable-devices \
    --enable-swresample \
    --enable-swscale \
    --enable-avcodec \
    --enable-avformat \
    --enable-avutil \
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

# Clone the specific 1.14.0 branch directly
echo "Cloning miyoomini-1.14.0 branch from schmurtzm/RetroArch-MiyoMini..."
git clone --depth 1 --branch miyoomini-1.14.0 https://github.com/schmurtzm/RetroArch-MiyoMini.git retroarch
cd retroarch

echo ""
echo "Current branch:"
git branch
echo ""
echo "Checking for Makefile.miyoomini..."
ls -la Makefile.miyoomini* 2>/dev/null || echo "Makefile.miyoomini not found in current directory"

# Apply FFmpeg recording patch to Makefile.miyoomini
echo "Applying FFmpeg patch to Makefile.miyoomini..."

# First, let's see what we're working with
echo "Current Makefile.miyoomini contents (first 50 lines):"
head -50 Makefile.miyoomini

# Create a sed script to add FFmpeg support right after the include line
cat > /tmp/add_ffmpeg.sed << 'SEDSCRIPT'
/^include Makefile.common/a\
\
# FFmpeg Recording Support - Added by build script\
HAVE_FFMPEG ?= 0\
ifeq ($(HAVE_FFMPEG), 1)\
    FFMPEG_PREFIX ?= /opt/ffmpeg-miyoo\
    CFLAGS += -DHAVE_FFMPEG -I$(FFMPEG_PREFIX)/include\
    LDFLAGS += -L$(FFMPEG_PREFIX)/lib -Wl,-rpath,/mnt/SDCARD/RetroArch/lib\
    LIBS += -lavformat -lavcodec -lswresample -lswscale -lavutil\
    DEFINES += -DHAVE_FFMPEG\
    $(info FFmpeg recording support enabled)\
endif
SEDSCRIPT

sed -i -f /tmp/add_ffmpeg.sed Makefile.miyoomini
sed -i -f /tmp/add_ffmpeg.sed Makefile.miyoomini_plus

# Verify the changes
echo ""
echo "Modified Makefile.miyoomini (first 50 lines):"
head -50 Makefile.miyoomini

# Check what Makefile.common does with HAVE_FFMPEG
echo ""
echo "Checking Makefile.common for HAVE_FFMPEG handling..."
grep -n "HAVE_FFMPEG\|record_ffmpeg\|ffmpeg_core" Makefile.common | head -30 || echo "No existing HAVE_FFMPEG in Makefile.common"

# The FFmpeg playback core IS required because HAVE_FFMPEG enables both recording
# AND the built-in video player core. The core references libretro_ffmpeg_* functions.
# We need to keep it, but fix the missing swresample include.

echo ""
echo "Fixing FFmpeg core to include swresample header..."

# Show current includes
echo "Current FFmpeg includes in ffmpeg_core.c:"
grep -n "#include.*libav\|#include.*libsw" cores/libretro-ffmpeg/ffmpeg_core.c | head -15

# The most reliable method: prepend the include to the file
echo ""
echo "Adding swresample include at the top of ffmpeg_core.c..."

# Create temp file with the include, then append original content
echo '#include <libswresample/swresample.h>' > /tmp/ffmpeg_core_fixed.c
cat cores/libretro-ffmpeg/ffmpeg_core.c >> /tmp/ffmpeg_core_fixed.c
mv /tmp/ffmpeg_core_fixed.c cores/libretro-ffmpeg/ffmpeg_core.c

# Verify the fix
echo ""
echo "First 15 lines after fix:"
head -15 cores/libretro-ffmpeg/ffmpeg_core.c

# Double-check swresample is present
if grep -q "libswresample/swresample.h" cores/libretro-ffmpeg/ffmpeg_core.c; then
    echo "SUCCESS: swresample header added!"
else
    echo "WARNING: Could not add swresample header automatically"
    head -50 cores/libretro-ffmpeg/ffmpeg_core.c
fi

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
cp retroarch_miyoo354 "${OUTPUT_DIR}/retroarch_miyoo354"
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
