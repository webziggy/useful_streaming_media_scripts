# FFmpeg Brew Update (macOS)

A helper script to install or update FFmpeg on macOS using Homebrew with a comprehensive set of non-default codecs and options.

## 🚀 Usage
```bash
chmod +x ffmpeg_brew_update.sh
./ffmpeg_brew_update.sh
```

## 📝 What it does
1. Uninstalls any existing FFmpeg version.
2. Installs dependencies like `chromaprint` and `zvbi`.
3. Taps `homebrew-ffmpeg/ffmpeg`.
4. Installs FFmpeg with almost all available `--with-*` options, excluding a few problematic or unnecessary ones (like `whisper`, `openvino`, `decklink`).

## 🛠 Dependencies
* **Homebrew**: Required to manage packages.
* **macOS**: This script is specifically designed for the macOS environment.
