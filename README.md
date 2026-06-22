# Useful Media Scripts

A collection of utility scripts for video encoding, packaging, and manipulation using FFmpeg, Node.js, and other tools.

## 🛠 Tools Index

### 📦 [Create Renditions & Package (HLS/DASH)](./create-renditions-package-hls-dash)
*   **Script:** `make_abr_mp4_for_dash_hls_fmp4.sh`
*   **Purpose:** Automatically generates multiple ABR renditions from a single input and packages them into HLS and MPEG-DASH formats using fMP4.
*   **Dependencies:** `ffmpeg`, `shaka-packager`.

### 🌐 [Webpage to Video](./nodejs-webpage2video)
*   **Script:** `webpage2video.js`
*   **Purpose:** Records a specified URL for a set duration, outputting an MP4 video. Useful for capturing dynamic web graphics or animations.
*   **Dependencies:** `node`, `puppeteer`, `puppeteer-screen-recorder`.

### 📉 [Optimise Presentation Videos](./optimise_presentation_videos_storage)
*   **Scripts:** 
    *   `decimate_slideshow_video.sh`: Reduces file size by dropping duplicate frames (ideal for slideshow-style videos).
    *   `reconstitute_decimated_slideshow_video.sh`: Converts decimated videos back to a standard constant framerate.
*   **Dependencies:** `ffmpeg`.

### ⚙️ [FFmpeg Brew Update (macOS)](./ffmpeg-brew-update-macos)
*   **Script:** `ffmpeg_brew_update.sh`
*   **Purpose:** A helper script to install or update FFmpeg via Homebrew with a wide array of non-default codecs and options enabled.
*   **Dependencies:** `brew`, `homebrew-ffmpeg`.

---

## 🚀 Getting Started
Most scripts require **FFmpeg** to be installed and available in your system path. For the Node.js tools, ensure you have a recent version of Node.js installed.
