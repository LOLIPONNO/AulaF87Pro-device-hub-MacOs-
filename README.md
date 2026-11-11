# AULA F87 Pro Studio for macOS

A native macOS configuration tool for the **AULA F87 Pro V1** mechanical keyboard.

## Key Features

- **Backlight Effects**: Configure 16 lighting animations with brightness, speed, and color controls.
- **Per-Key RGB Painter**: Customize individual key colors, save custom lighting layouts, and apply presets.
- **Side Lights & Light Bar**: Control the keyboard's dual side RGB strips and navigation-cluster light bar.
- **Key Matrix Remapping**: Remap keys across Default (Layer 0), FN1 (Layer 1), and FN2 (Layer 2). Includes quick Mac (Cmd/Option swap) and Korean (Lang1 Hangul) presets.
- **Music Reactive (Audio Dance)**: 11-band real-time audio visualizer syncing system microphone or rhythm synthesizer to keyboard LEDs.
- **Performance & Power Settings**: Adjust debounce delay (1ms to 5ms) and wireless sleep timeout (30s to 60m).
- **Profiles**: Save, manage, and switch between your favorite lighting and key setups.

## Supported Hardware

- **2.4GHz Wireless Mode**: VID `0x3554`, PID `0xFA09`
- **USB Wired Mode**: VID `0x258A`, PID `0x010C`
- **Bluetooth Mode**: VID `0x3554`, PID `0xFA07` (Profile caching & status monitoring)

## Installation

1. Download `AULA-F87-Pro-Studio-v1.0.0.dmg` from the Releases page.
2. Open the `.dmg` and drag `AULA F87 Pro Studio.app` to your `/Applications` folder.
3. On first launch, macOS Gatekeeper may prompt verification:
   - Right-click (or Control-click) `AULA F87 Pro Studio.app` and choose **Open**.
   - Or navigate to **System Settings > Privacy & Security** and select **Open Anyway**.
4. Grant **Input Monitoring** permission when prompted so the app can communicate with the USB/2.4G HID interface.

## Building from Source

```bash
swift build -c release
```
