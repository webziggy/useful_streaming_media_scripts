#!/bin/bash
#
# Usage:
#
# reconstitute_decimated_slideshow_video.sh INPUTFILE OUTPUTFILE

ffmpeg -i $1 -r 30000/1001 -max_muxing_queue_size 999 -c:a copy $2
