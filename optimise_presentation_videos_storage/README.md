# Optimise Presentation Videos Storage

This directory contains scripts to reduce the storage size of videos that are primarily static, such as slideshows or screen recordings of presentations.

## 📈 Scripts

### `decimate_slideshow_video.sh`
Uses the `mpdecimate` filter to drop duplicate frames, significantly reducing file size while maintaining visual quality for static content. The output uses Variable Frame Rate (VFR).

**Usage:**
```bash
./decimate_slideshow_video.sh input.mp4 output_decimated.mp4
```

### `reconstitute_decimated_slideshow_video.sh`
Converts a decimated (VFR) video back to a Constant Frame Rate (CFR) of 29.97 fps. This is useful for compatibility with video editors or players that do not handle VFR well.

**Usage:**
```bash
./reconstitute_decimated_slideshow_video.sh output_decimated.mp4 restored_video.mp4
```

## 🛠 Dependencies
* **FFmpeg**: Must be installed and available in your PATH.
