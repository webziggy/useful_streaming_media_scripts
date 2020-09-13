#!/bin/bash
#
# @webziggy
#
# with thanks to ideas from mrbar42 - https://gist.github.com/mrbar42/ae111731906f958b396f30906004b3fa
# - and the create-vod-hls.sh script.

OPTIND=1
me=$(basename "$0")

show_help() {
  cat << EOF

  Usage:

    ${me} -i INPUTFILE [-h] [-e] [-p] [-o OUTPUTFILE] [-x WIDTH -y HEIGHT] [-r RENDITIONFILE] [-s SCALERNAME] [-t TIME]

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

    -r : [OPTIONAL] file containing a description of the encoding renditions required -
          a text file that contains 1 rendition per line like this:

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

    You'll need ffmpeg installed on your system. (Edit this script if the name
    is not 'ffmpeg')

    You'll need Shaka Packager installed on your system. (Edit this script if
    the name/location is not shaka-packager)

EOF
}

# The commands for ffmpeg and shaka-packager - customise as needed for your system
ffmpeg="ffmpeg"
shakapackager="shaka-packager"

# set these to the default maximum width and height, if the input video is not exactly
# within the ratio of this it will pad with black bars
# can be overriden by using -mfh and -mfw on the command line
maxwidth="1920"
maxheight="1080"

# don't change these...
do_encoding=false
do_packaging=false
renditionsprovider="SCRIPT"
testrun=false
scalername="lanczos"
timelimit="NONE"

while getopts ":i:o:epx:y:r:hds:t:" opt; do
  case ${opt} in
    i)
      echo "RECEIVED: -i INPUTFILE: '${OPTARG}'" >&2
      source="${OPTARG}"
      ;;
    o)
      echo "RECEIVED: -o OUTPUTFILE: '${OPTARG}'" >&2
      target="${OPTARG}"
      ;;
    e)
      echo "RECEIVED: -e :: WILL ENCODE TO RENDITIONS" >&2
      do_encoding=true
      ;;
    p)
      echo "RECEIVED: -p :: WILL PACKAGE TO HLS+DASH" >&2
      do_packaging=true
      ;;
    y)
      echo "RECEIVED: -h MAX FRAME HEIGHT: '${OPTARG}'"
      maxheight="${OPTARG}"
      ;;
    x)
      echo "RECEIVED: -w MAX FRAME WIDTH: '${OPTARG}'"
      maxwidth="${OPTARG}"
      ;;
    r)
      echo "RECEIVED: -r RENDITION FILE: '${OPTARG}'"
      renditionfile="${OPTARG}"
      renditionsprovider="FILE"
      ;;
    d)
      echo "RECEIVED: -d :: TEST RUN!"
      testrun=true
      ;;
    t)
      echo "RECEIVED: -t TIME: '${OPTARG}'"
      timelimit="${OPTARG}"
      ;;
    s)
      echo "RECEIVED: -s SCALER NAME: '${OPTARG}'"
      scalername="${OPTARG}"
      ;;
    h)
      echo "SHOWING HELP: (and exiting)"
      show_help
      exit
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      show_help
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      show_help
      exit 1
      ;;
  esac
done

echo "############ CHECKING DEPENDENCIES ############"
echo ""
echo "---- CHECKING FOR FFMPEG ----"
echo ""
if ! [ -x "$(command -v ${ffmpeg})" ]; then
  echo "ffmpeg doesn't exist as '${ffmpeg}' on your system, edit this script to fix this problem."
  exit 1
else
  echo "ffmpeg exists and is called '${ffmpeg}'"
  echo ""
  echo "ffmpeg Licence Info:"
  echo "----------------------------------------------------------------"
  ${ffmpeg} -L
  echo "----------------------------------------------------------------"
fi

echo ""
echo "---- CHECKING FOR SHAKA PACKAGER ----"
echo ""
if ! [ -x "$(command -v ${shakapackager})" ]; then
  echo "Shaka Packager doesn't exist as '${shakapackager}' on your system, edit this script to fix this problem."
  exit 1
else
  echo "Shaka Packager exists and is called '${shakapackager}'."
  echo ""
  echo "Shaka Packager version info:"
  echo "----------------------------------------------------------------"
  ${shakapackager} -version
  echo "----------------------------------------------------------------"
  echo ""
  echo ""
fi


# If renditions were provided by a file then check to see if we can read the file
# and then read the renditions into an array
# TODO: CHECK THE RENDITIONS IN THE FILE ARE ACTUALLY IN THE FORMAT ACCEPTED
if [ "${renditionsprovider}" == "FILE" ]; then
  echo "############ GETTING RENDITIONS FROM FILE ###########"
  echo "FILE: ${renditionfile}"
  if [[ -f "${renditionfile}" ]]; then
      echo "File exists, reading now."
      IFS=$'\n' read -d '' -r -a renditions < "${renditionfile}"
  else
    echo "File doesn't exist, this is a failure and script will exit. Nothing done."
    exit 1
  fi
fi

if [ "${renditionsprovider}" == "SCRIPT" ]; then
  echo "############ GETTING RENDITIONS FROM THIS SCRIPT, DEFAULT ###########"

  # comment/add lines here to control which renditions would be created
  renditions=(
  # resolution(pixels - width x height)  video-bitrate(kbps)  audio-bitrate(kbps)
  #  "426x240    400k    64k"
    "640x360    800k     96k"
    "842x480    1400k    128k"
    "1280x720   2800k    128k"
    "1920x1080  5000k    192k"
  )
fi
echo "RENDTIONS:"
for rendition in "${renditions[@]}"; do
  echo "${rendition}"
done

segment_target_duration=4       # try to create a new segment every X seconds
max_bitrate_ratio=1.07          # maximum accepted bitrate fluctuations
rate_monitor_buffer_ratio=1.5   # maximum buffer size between bitrate conformance checks

if [[ ! "${target}" ]]; then
  target="${source##*/}" # leave only last component of path
  target="${target%.*}"  # strip extension
fi
mkdir -p "${target}"

# Find the frames per second of the input file, and calculate what
# ffmpeg should be using based on for key frames interval
key_frames_interval="$(echo `ffprobe ${source} 2>&1 | grep -oE '[[:digit:]]+(.[[:digit:]]+)? fps' | grep -oE '[[:digit:]]+(.[[:digit:]]+)?'`*2 | bc || echo '')"
key_frames_interval=${key_frames_interval:-50}
key_frames_interval=$(echo `printf "%.1f\n" $(bc -l <<<"$key_frames_interval/10")`*10 | bc) # round
key_frames_interval=${key_frames_interval%.*} # truncate to integer

# Find the audio sample rate, we really shouldn't change this during encodes
audio_sample_rate="$(echo `ffprobe ${source} 2>&1 | grep -oE '[[:digit:]]+(.[[:digit:]]+)? Hz' | grep -oE '[[:digit:]]+(.[[:digit:]]+)?'`)"

# static parameters that are similar for all renditions
static_params="-c:a aac -ar ${audio_sample_rate} -c:v h264 -profile:v main -crf 20 -sc_threshold 0"
static_params+=" -g ${key_frames_interval} -keyint_min ${key_frames_interval} "

# misc params
misc_params=""
if [ "${timelimit}" == "NONE" ]; then
  echo "No timelimit, we'll encode the whole input file"
else
  misc_params+="-t ${timelimit} "
fi
misc_params+="-hide_banner -y"

echo "Identified key_frames_interval of input file:"
echo "${key_frames_interval}"

echo "Identified audio_sample_rate of input file"
echo "${audio_sample_rate}"


#echo "static_params:"
#echo "${static_params}"

if [ "${do_encoding}" == true ]; then
  echo "############ ENCODING ... ###########"

  cmd=""
  cmd_prettyprint=$' \\\n'
  num_of_renditions=${#renditions[@]}
  #echo "num_of_renditions:"
  #echo "${num_of_renditions}"
  counter=1
  for rendition in "${renditions[@]}"; do
    # drop extraneous spaces
    rendition="${rendition/[[:space:]]+/ }"

    # rendition fields
    resolution="$(echo ${rendition} | cut -d ' ' -f 1)"
    bitrate="$(echo ${rendition} | cut -d ' ' -f 2)"
    audiorate="$(echo ${rendition} | cut -d ' ' -f 3)"

    # calculated fields
    width="$(echo ${resolution} | grep -oE '^[[:digit:]]+')"
    height="$(echo ${resolution} | grep -oE '[[:digit:]]+$')"
    maxrate="$(echo "`echo ${bitrate} | grep -oE '[[:digit:]]+'`*${max_bitrate_ratio}" | bc)"
    bufsize="$(echo "`echo ${bitrate} | grep -oE '[[:digit:]]+'`*${rate_monitor_buffer_ratio}" | bc)"
    bandwidth="$(echo ${bitrate} | grep -oE '[[:digit:]]+')000"

    name="${height}p_${bitrate%?}v_${audiorate%?}a"

    #removed from scaling- :force_original_aspect_ratio=increase
    cmd+=" ${static_params} -vf pad=width=${maxwidth}:height=${maxheight}:x=0:y=-1,scale=w=${width}:h=${height}:flags=${scalername}"
    cmd+=" -b:v ${bitrate} -maxrate ${maxrate%.*}k -bufsize ${bufsize%.*}k -b:a ${audiorate}"
    cmd+=" ${target}/${name}.mp4"

    cmd_prettyprint+=" ${static_params} -vf pad=width=${maxwidth}:height=${maxheight}:x=0:y=-1,scale=w=${width}:h=${height}:flags=${scalername}"
    cmd_prettyprint+=" -b:v ${bitrate} -maxrate ${maxrate%.*}k -bufsize ${bufsize%.*}k -b:a ${audiorate}"
    cmd_prettyprint+=" ${target}/${name}.mp4"
    if [ "${counter}" -lt "${num_of_renditions}" ]; then
      cmd_prettyprint+=$' \\\n'
    fi

    counter=$((counter+1))

  done

  # start conversion
  echo "Encoding command:"
  echo "----------------------------------------------------------------"
  echo "${ffmpeg} ${misc_params} -i ${source} ${cmd_prettyprint}"
  echo "----------------------------------------------------------------"

  if [ "${testrun}" == false ]; then
    echo "Encoder output:"
    echo "----------------------------------------------------------------"
    ${ffmpeg} ${misc_params} -i ${source} ${cmd}
    echo "----------------------------------------------------------------"
  else
    echo "TEST RUN - WILL NOT EXECUTE THE COMMAND"
  fi
  echo "Done - renditions encoded to MP4 at ${target}/"
fi

if [ "${do_packaging}" == true ]; then
  echo "############ PACKAGING HLS & DASH ... ###########"

  cmd=""
  cmd_prettyprint=$' \\\n'
  counter=1
  for rendition in "${renditions[@]}"; do
    # drop extraneous spaces
    rendition="${rendition/[[:space:]]+/ }"

    # rendition fields
    resolution="$(echo ${rendition} | cut -d ' ' -f 1)"
    bitrate="$(echo ${rendition} | cut -d ' ' -f 2)"
    audiorate="$(echo ${rendition} | cut -d ' ' -f 3)"

    # calculated fields
    width="$(echo ${resolution} | grep -oE '^[[:digit:]]+')"
    height="$(echo ${resolution} | grep -oE '[[:digit:]]+$')"
    maxrate="$(echo "`echo ${bitrate} | grep -oE '[[:digit:]]+'`*${max_bitrate_ratio}" | bc)"
    bufsize="$(echo "`echo ${bitrate} | grep -oE '[[:digit:]]+'`*${rate_monitor_buffer_ratio}" | bc)"
    bandwidth="$(echo ${bitrate} | grep -oE '[[:digit:]]+')000"
    name="${height}p_${bitrate%?}v_${audiorate%?}a"

    inname="${target}/${name}.mp4"
    outnamevideo="${target}/hlsdash/${height}p_${bitrate%?}v.mp4"
    outplaylisthls_video="${height}p_${bitrate%?}v.m3u8"
    outnameaudio="${target}/hlsdash/${audiorate%?}a_audio${counter}.mp4"
    outplaylisthls_audio="${audiorate%?}a_audio${counter}.m3u8"
    outplaylisthls_videoiframe="${height}p_${bitrate%?}v_iframe.m3u8"

    cmd+="in=${inname},stream=audio,output=${outnameaudio},playlist_name=${outplaylisthls_audio},hls_group_id=audio,hls_name=ENGLISH "
    cmd+="in=${inname},stream=video,output=${outnamevideo},playlist_name=${outplaylisthls_video},iframe_playlist_name=${outplaylisthls_videoiframe} "

    cmd_prettyprint+="in=${inname},stream=audio,output=${outnameaudio},playlist_name=${outplaylisthls_audio},hls_group_id=audio,hls_name=ENGLISH"
    cmd_prettyprint+=$' \\\n'
    cmd_prettyprint+="in=${inname},stream=video,output=${outnamevideo},playlist_name=${outplaylisthls_video},iframe_playlist_name=${outplaylisthls_videoiframe} "
    cmd_prettyprint+=$' \\\n'

    counter=$((counter+1))
  done
  cmd+=" --hls_master_playlist_output ${target}/hlsdash/master.m3u8"
  cmd+=" --mpd_output ${target}/hlsdash/master.mpd"

  cmd_prettyprint+=" --hls_master_playlist_output ${target}/hlsdash/master.m3u8"
  cmd_prettyprint+=$' \\\n'
  cmd_prettyprint+=" --mpd_output ${target}/hlsdash/master.mpd"

  #echo "${cmd}"

  # start conversion
  echo "Packaging command:"
  echo "----------------------------------------------------------------"
  echo "${shakapackager} ${cmd}"
  echo "----------------------------------------------------------------"
  if [ "${testrun}" == false ]; then
    echo "Packager output:"
    echo "----------------------------------------------------------------"
    ${shakapackager} ${cmd}
    echo "----------------------------------------------------------------"
  else
    echo "TEST RUN - WILL NOT EXECUTE THE COMMAND"
  fi
  echo "Done - HLS and DASH packaged ${target}/hlsdash/"

fi
