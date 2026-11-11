# ✨ MiniPop

English | [简体中文](./README.zh-CN.md)

A lightweight, native macOS instant selection translator & search tool built with a single Swift file. Designed as a clean replacement for PopClip — **it never touches your clipboard or simulates `Cmd+C` when reading selected text**.

## Features

- **Zero Clipboard Pollution**: Reads selected text strictly via macOS Accessibility API (`AXUIElement`) and automatically wakes up accessibility trees for Chrome/Electron apps. Your clipboard history (Paste, Raycast, Alfred, etc.) stays 100% clean.
- **Instant Translation on Selection**: Select text with your mouse (drag or double-click) and release — the translation popover appears immediately without extra button clicks.
- **Auto Bi-directional Translation & `中/英` Toggle**: Automatically translates Chinese text into English, and any other language into Simplified Chinese via Google Translate. For mixed Chinese/English text, click the **`中/英`** button on the popover to switch target language between Chinese and English on the fly.
- **Click Card to Copy**: Click anywhere on the translation card to copy the translated result to the clipboard and dismiss the popover, or click `🔍 搜原文` to search the original text on Google.
- **System Proxy Support**: Uses native `URLSession.shared`, automatically inheriting your macOS system HTTP/HTTPS/SOCKS proxy settings with zero configuration.
- **Non-Activating Floating HUD**: Never steals window focus from your active app.
- **Launch at Login**: Built-in macOS 13+ `SMAppService` login item toggle in the `✨` menu bar icon.

## Requirements

- macOS 13.0 or later
- Xcode Command Line Tools (`swiftc` and `iconutil`)

## Build & Run

```bash
./build.sh
open MiniPop.app
```

You can also move `MiniPop.app` to `/Applications`:

```bash
cp -R MiniPop.app /Applications/
open /Applications/MiniPop.app
```

## Accessibility Permission

On first launch (or after rebuilding with `./build.sh`), MiniPop needs **Accessibility** permission to detect text selection:

1. Click the **`✨`** icon in the macOS menu bar.
2. If the first item shows `⚠️ 点击授权「辅助功能」权限…`, click it to open **System Settings → Privacy & Security → Accessibility**.
3. Enable **MiniPop** (if rebuilding an existing app, toggle it off and back on).
4. Once authorized, the menu bar item will display `✓ 辅助功能权限已开启`.

## Project Structure

- `main.swift` — All core logic: Accessibility selection reader, Google Translate client, non-activating HUD panel, and menu bar controller.
- `make_icon.swift` — Generates the white-background `✨` `.icns` app icon natively.
- `build.sh` — Compiles the binary, bundles `MiniPop.app`, signs it ad-hoc, and runs self-tests.
