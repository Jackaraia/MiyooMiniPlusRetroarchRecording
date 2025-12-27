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


## Credits

- RetroArch-MiyoMini by schmurtzm and contributors
- OnionOS team for the excellent Miyoo Mini firmware
- FFmpeg project for the encoding libraries
- libretro team for RetroArch

## License

This build script is provided as-is. RetroArch is GPLv3, FFmpeg components are LGPL/GPL.
