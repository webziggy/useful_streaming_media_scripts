# Create Renditions Package HLS & Dash

SCRIPT: make_abr_mp4_for_dash_hls_fmp4.sh

REQUIRES:

* BASH (tested with v.3.2.57)
* ffmpeg (tested with v4.3.1 on macOS)
* shaka packager (tested with 2.4.3 on macOS)

```bash
  Usage:

    make_abr_mp4_for_dash_hls_fmp4.sh -i INPUTFILE [-h] [-e] [-p] [-o OUTPUTFILE] [-x WIDTH -y HEIGHT] [-r RENDITIONFILE] [-s SCALERNAME] [-t TIME]

    -h : show this help

    -e : encode input file to renditions - single mp4 output for each
          rendition profile (See General Notes below about dependency on -p)

    -p : package for HLS and MPEG-DASH with FMP4 (no segmentation of
          outputs with this script) (See General Notes below about
          dependency on -e)

    -i : the input video file (anything that ffmpeg will understand) should
          have audio and video. (in this script we assume only one audio track
          and one video)

    -o : [OPTIONAL] the name of the output prefix to be used, if unspecfied
          we will use the input filename (without the extension). This is
          first used as the subdirectory that's created to hold everything
          output. Then it's used as the prefix to the renditions and
          packages.

    -d : [OPTIONAL] test run / debug, don't do any encoding or packaging
          (will just show what would happen so you can sanity check)

    -x and -y : max-frame-width (x) and max-frame-height (y) - this is the
          maximum frame dimensions of video of the renditions -
          by default this assumes 1920 wide x 1080 height
          This allows, say an inputfile video file with larger dimensions
          to be scaled down to fit within this maximum dimensions and
          that will be centred vertically vertical within these maximum
          dimentions, and black padding will be applied where necessary.

          For example - if your input file is an UltraHD video file with
          video frame dimensions of a cinematic style (e.g. 21:9) and you
          specify -x 1920 -y 1080 each rendition will be fitted into this
          16:9 dimension and letterboxing applied. The output renditions
          will follow 16:9 aspect ratio, depending on your input
          renditions required.

    -r : [OPTIONAL] file containing a description of the encoding renditions
          required - a text file that contains 1 rendition per line
          like this:

          640x360    800k     96k
          842x480    1400k    128k
          1280x720   2800k    128k
          1920x1080  5000k    192k

          Each row describes width x height of the output (in pixels), the
          video bitrate desired (in kilobits per second - 'k'), and the
          audio bitrate desired (in kilobits per second - 'k')

          [WIDTH]x[HEIGHT]   [VIDEOBITRATEKBPS]k   [AUDIOBITRATEKBPS]k

          These entries are not optional. All must be supplied. The script
          allows any amount of whitespace between the entries on the row
          and will assume those are the fields. No whitespace in the
          WIDTHxHEIGHT field, or between bitrates and the 'k'.

          It is expected that dimensions will be in 16:9 aspect ratio,
          anything other than that and you'll end up with some strangeness.
          TODO: handle other aspect ratios.

          Dependency note for -r : if -e is specified it will encode to the
          renditions in the file. If -p is specified it will use the renditions
          described in the file to look for the files that either are, or would
          have been (if not called with -e), created in the encoding loop -
          obviously if you specify a renditions file that contains renditions
          that weren't previously created with -e then this script will either
          fail completely or give strange output. (TODO: double check your
          renditions requested matches the files available for packaging)

    -s : [OPTIONAL] Scaler Name - the scaler name in ffmpeg to be used -
          if unspecfied this script will use 'lanczos'

          https://ffmpeg.org/ffmpeg-scaler.html
          https://trac.ffmpeg.org/wiki/Scaling

    -t : [OPTIONAL] duration to encode (in seconds) - this is the first
          x seconds of the input video. Specify as "300s". Default is to
          encode everything in the input video file.

    GENERAL NOTES:

    Encoding will be done before packaging if encoding is picked.
    If packaging is selected on it's own, then this script assumes
    that encoding was done to the exact filename specifications output
    by that. You'll get errors otherwise.

    Encoding will check the framerate of the inputfile and make sure output
    renditions are compatible.

    Encoding will check audio sample rate of the input file and make sure
    output renditions are the same. (Currently mono inputs will recieve
    mono outputs, stereo - stereo, etc.)

    You'll need ffmpeg installed on your system. (Edit this script if the name
    is not 'ffmpeg')

    You'll need Shaka Packager installed on your system. (Edit this script if
    the name/location is not shaka-packager)
```

