# RetroArch Recording Build for Miyoo Mini

This repository builds RetroArch with FFmpeg recording support for the Miyoo Mini and Miyoo Mini Plus running OnionOS.

## What This Does

- Cross-compiles FFmpeg (v5.1.4) for ARM Cortex-A7
- Patches RetroArch-MiyoMini to enable FFmpeg recording support  
- Builds RetroArch binaries with recording capability
- Packages everything you need for easy installation

## Recording Features

- **Lossless quality** - Uses FFV1 video codec + FLAC audio
- **Perfect sync** - Audio and video captured from same emulation frame
- **Hotkey toggle** - Start/stop recording with a button combo
- **Native resolution** - Records at game resolution (240x160 for GBA, etc.)
- **MKV container** - Universal format, works with all major editors

## How to Build

### Prerequisites

- A GitHub account (free)
- That's it! GitHub Actions does all the heavy lifting

### Steps

1. **Fork this repository** to your own GitHub account

2. **Enable GitHub Actions:**
   - Go to your fork's "Actions" tab
   - Click "I understand my workflows, go ahead and enable them"

3. **Run the build:**
   - Go to Actions → "Build RetroArch with FFmpeg Recording for Miyoo Mini"
   - Click "Run workflow" → "Run workflow"
   - Wait 10-20 minutes for the build to complete

4. **Download the artifacts:**
   - Once the build is green (successful), click on the completed run
   - Scroll down to "Artifacts"
   - Download "RetroArch-Recording-MiyooMini"

5. **Install on your Miyoo Mini:**
   - Extract the downloaded ZIP
   - Follow the instructions in INSTALL.md

## Build Troubleshooting

If the build fails:

1. Check the build logs (click on the failed job to see details)
2. The most likely issues are:
   - Makefile patch didn't apply cleanly
   - Missing dependencies in the Docker image
   - FFmpeg configure options need adjustment

3. Open an issue with the error log and I can help debug

## Credits

- RetroArch-MiyoMini by schmurtzm and contributors
- OnionOS team for the excellent Miyoo Mini firmware
- FFmpeg project for the encoding libraries
- libretro team for RetroArch

## License

This build script is provided as-is. RetroArch is GPLv3, FFmpeg components are LGPL/GPL.
