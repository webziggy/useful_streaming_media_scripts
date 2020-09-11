#!/bin/bash
#
# @webziggy
#
# with thanks to ideas from mrbar42 - https://gist.github.com/mrbar42/ae111731906f958b396f30906004b3fa
# - and the create-vod-hls.sh script.

OPTIND=1
me=`basename "$0"`

show_help() {
  cat << EOF
  Usage: ${me} -i INPUTFILE [-o OUTPUTFILE] [-e] [-p]
    -e : encode input file to renditions - single mp4 output for each rendition profile
    -p : package for hls and dash FMP4

    Encoding will be done before packaging if encoding is picked.
    If packaging is selected on it's own, then this script assumes that encoding was done
    to the exact filename specifications output by that. You'll get errors otherwise.

EOF
}

do_encoding=false
do_packaging=false
while getopts ":i:o:enc:pkg" opt; do
  case $opt in
    i)
      echo "RECEVIED: -i INPUTFILE: '${OPTARG}'" >&2
      source="${OPTARG}"
      ;;
    o)
      echo "RECEVIED: -o OUTPUTFILE '${OPTARG}'" >&2
      target="${OPTARG}"
      ;;
    e)
      echo "RECEVIED: -e ENCODE TO RENDITIONS" >&2
      do_encoding=true
      ;;
    p)
      echo "RECEVIED: -p PACKAGE TO HLS+DASH" >&2
      do_packaging=true
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

# The commands for ffmpeg and shaka-packager - customise as needed for your system
ffmpeg="ffmpeg"
shakapackager="shaka-packager"

# set these to the maximum width and height, if the input video is not exactly
# within the ratio of this it will pad with black bars
maxheight="1080"
maxwidth="1920"

# comment/add lines here to control which renditions would be created
renditions=(
# resolution  bitrate  audio-rate
#  "426x240    400k    64k"
  "640x360    800k     96k"
  "842x480    1400k    128k"
  "1280x720   2800k    128k"
  "1920x1080  5000k    192k"
)

segment_target_duration=4       # try to create a new segment every X seconds
max_bitrate_ratio=1.07          # maximum accepted bitrate fluctuations
rate_monitor_buffer_ratio=1.5   # maximum buffer size between bitrate conformance checks

if [[ ! "${target}" ]]; then
  target="${source##*/}" # leave only last component of path
  target="${target%.*}"  # strip extension
fi
mkdir -p ${target}

key_frames_interval="$(echo `ffprobe ${source} 2>&1 | grep -oE '[[:digit:]]+(.[[:digit:]]+)? fps' | grep -oE '[[:digit:]]+(.[[:digit:]]+)?'`*2 | bc || echo '')"
key_frames_interval=${key_frames_interval:-50}
key_frames_interval=$(echo `printf "%.1f\n" $(bc -l <<<"$key_frames_interval/10")`*10 | bc) # round
key_frames_interval=${key_frames_interval%.*} # truncate to integer

# static parameters that are similar for all renditions
static_params="-c:a aac -ar 48000 -c:v h264 -profile:v main -crf 20 -sc_threshold 0"
static_params+=" -g ${key_frames_interval} -keyint_min ${key_frames_interval} "

# misc params
misc_params="-hide_banner -y"

echo "Identified key_frames_interval of input file:"
echo "${key_frames_interval}"

#echo "static_params:"
#echo "${static_params}"

if [ "${do_encoding}" == true ]; then
  echo "############ ENCODING REQUESTED ###########"

  cmd=""
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

    cmd+=" ${static_params} -vf pad=width=${maxwidth}:height=${maxheight}:x=0:y=-1,scale=w=${width}:h=${height}:force_original_aspect_ratio=decrease"
    cmd+=" -b:v ${bitrate} -maxrate ${maxrate%.*}k -bufsize ${bufsize%.*}k -b:a ${audiorate}"
    cmd+=" ${target}/${name}.mp4"
  #  echo "if ${counter} -lt ${num_of_renditions}"
  #  if [ "${counter}" -lt "${num_of_renditions}" ]; then
  #    cmd+=$' \\\n'
  #  fi
    counter=$((counter+1))

  done

  # start conversion
  echo -e "Executing encoding command:\n${ffmpeg} ${misc_params} -i ${source} ${cmd}"
  ${ffmpeg} ${misc_params} -i ${source} ${cmd}
  echo "Done - renditions encoded to MP4 at ${target}/"
fi

if [ "${do_packaging}" == true ]; then
  echo "############ PACKAGING REQUESTED ###########"

  cmd=""
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

    counter=$((counter+1))
  done
  cmd+=" --hls_master_playlist_output ${target}/hlsdash/master.m3u8"
  cmd+=" --mpd_output ${target}/hlsdash/master.mpd"

  #echo "${cmd}"

  # start conversion
  echo -e "Executing packaging command:\n${shakapackager} ${cmd}"
  ${shakapackager} ${cmd}
  echo "Done - HLS and DASH packaged ${target}/hlsdash/"

fi
