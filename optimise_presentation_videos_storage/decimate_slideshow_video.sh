#!/bin/bash
#
# Usage:
#
# decimate_slideshow_video.sh INPUTFILE OUTPUTFILE

ffmpeg -i $1 -vsync vfr -vf mpdecimate -c:a copy $2
