#!/bin/bash
# Rebuild ffmpeg from the homebrew-ffmpeg tap with (almost) every --with- option,
# after bringing its dependencies up to date, and check the result actually runs.
#
# Usage:
#   ffmpeg_brew_update.sh                 check first; rebuild only if ffmpeg is broken or missing
#   ffmpeg_brew_update.sh --force         rebuild anyway (e.g. after a brew upgrade, or to pick up new options)
#   ffmpeg_brew_update.sh --clean         also force-uninstall and reinstall chromaprint and zvbi first
#   ffmpeg_brew_update.sh --check         only run the checks, change nothing
#   ffmpeg_brew_update.sh --exclusions    list the excluded options, why, and whether a
#                                         broken library has a newer version worth trying
#   ffmpeg_brew_update.sh --force --include openapv
#                                         rebuild with an excluded option put back, just for this
#                                         run (repeatable); if it builds, update its entry in EXCLUSIONS
#   ffmpeg_brew_update.sh --help          show this help
#
# Checking for the features you need (defaults are in REQUIRE_* below):
#   --require-encoders "aac libx264"      the encoders ffmpeg must have
#   --require-decoders "hevc"             the decoders ffmpeg must have
#   --require-filters "loudnorm ebur128"  the filters ffmpeg must have
#   Use "none" (or "") to check none of that kind. The environment variables
#   FFMPEG_REQUIRE_ENCODERS, FFMPEG_REQUIRE_DECODERS and FFMPEG_REQUIRE_FILTERS do the
#   same; an option given on the command line wins. Example:
#     ffmpeg_brew_update.sh --check --require-filters none --require-encoders "aac libx264"
#
# After any 'brew upgrade', run with --check; if it fails, run again with --force
# (or --clean if the dependency step fails). The exclusions and their reasons are in
# EXCLUSIONS below. Each run writes a log to ~/Library/Logs/ffmpeg_brew_update_<UTC>.log
#
# Decklink needs the Blackmagic DeckLink SDK. To try it, use --include decklink with:
#   export HOMEBREW_EXTRA_CFLAGS="-I$HOME/Documents/Blackmagic-DeckLink-SDK-16.0/Mac/include"
#   export HOMEBREW_EXTRA_LDFLAGS="-L$HOME/Documents/Blackmagic-DeckLink-SDK-16.0/Mac/include"

set -uo pipefail

FORMULA="homebrew-ffmpeg/ffmpeg/ffmpeg"

# The features ffmpeg must have to count as working: space-separated names exactly as
# 'ffmpeg -encoders', 'ffmpeg -decoders' and 'ffmpeg -filters' list them. Empty checks none.
# The defaults suit a transcription workflow (WAV and AAC audio, silence detection,
# trimming, waveform images, hardware H.264). An environment variable of the same name
# with an FFMPEG_ prefix replaces a default, even when set to empty; --require-* replaces both.
REQUIRE_ENCODERS="${FFMPEG_REQUIRE_ENCODERS-aac pcm_s16le h264_videotoolbox}"
REQUIRE_DECODERS="${FFMPEG_REQUIRE_DECODERS-}"
REQUIRE_FILTERS="${FFMPEG_REQUIRE_FILTERS-silencedetect atrim showwavespic}"

# Options left out of the build, one per line, fields separated by '|':
#   option       the name after --with-
#   formula      for a library that broke the build: its Homebrew formula (else empty)
#   broken       the formula version that broke it
#   ffmpeg       the ffmpeg version it broke with
#   last good    the last formula version known to build
#   since        when it was excluded
#   reason
# When 'formula' is set, --exclusions and every rebuild check whether a newer formula or
# ffmpeg is available and say it's worth trying again with --include.
EXCLUSIONS="$(cat <<'EOF'
chromaprint||||||chromaprint itself depends on ffmpeg, so building ffmpeg with it is circular. chromaprint is installed separately instead.
alt-name||||||Not a library: installs the tools as ffmpeg-alt, ffprobe-alt and so on. Not wanted.
game-music-emu||||||Reason not recorded (excluded in the original script).
decklink||||||Needs the Blackmagic DeckLink SDK installed by hand, and still wouldn't build with it.
openvino||||||Reason not recorded (excluded in the original script). OpenVINO is a very large machine-learning dependency.
whisper-cpp||||||Reason not recorded (excluded in the original script). Transcription is done in MacWhisper instead.
librsvg||||||Reason not recorded (excluded in the original script).
libflite||||||Reason not recorded (excluded in the original script).
openapv|openapv|1.1.1.0|9.0.1|0.3.0.0|2026-09-16|openapv 1.1.1.0 changed the arguments of oapvm_create(), so ffmpeg 9.0.1's liboapvenc.c fails to compile ("too few arguments to function call"). The upgrade from 0.3.0.0 also broke the existing ffmpeg at run time (liboapv.3.dylib not found).
EOF
)"

usage() {
  # Print the comment block at the top of this file, without the leading '# '.
  sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0"
}

FORCE=0; CLEAN=0; CHECK_ONLY=0; SHOW_EXCLUSIONS=0; INCLUDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --force) FORCE=1 ;;
    --clean) CLEAN=1; FORCE=1 ;;
    --check) CHECK_ONLY=1 ;;
    --exclusions) SHOW_EXCLUSIONS=1 ;;
    --include)
      [ $# -ge 2 ] || { echo "--include needs an option name, e.g. --include openapv"; exit 2; }
      name="${2#--with-}"
      cut -d'|' -f1 <<<"$EXCLUSIONS" | grep -qx -- "$name" \
        || { echo "'$name' is not in the exclusions list (see --exclusions)"; exit 2; }
      INCLUDE="$INCLUDE $name"; shift ;;
    --require-encoders|--require-decoders|--require-filters)
      [ $# -ge 2 ] || { echo "$1 needs a list, e.g. $1 \"name1 name2\" (or none)"; exit 2; }
      list="$2"; [ "$list" = "none" ] && list=""
      case "$1" in
        --require-encoders) REQUIRE_ENCODERS="$list" ;;
        --require-decoders) REQUIRE_DECODERS="$list" ;;
        --require-filters)  REQUIRE_FILTERS="$list" ;;
      esac
      shift ;;
    *) echo "Unknown option: $1"; echo; usage; exit 2 ;;
  esac
  shift
done

# Names are matched against ffmpeg's lists, so allow only the characters they use.
for list in "$REQUIRE_ENCODERS" "$REQUIRE_DECODERS" "$REQUIRE_FILTERS"; do
  for feature in $list; do
    [[ "$feature" =~ ^[A-Za-z0-9_]+$ ]] \
      || { echo "'$feature' isn't a valid encoder, decoder or filter name"; exit 2; }
  done
done

# The stable version Homebrew currently offers for a formula (empty if unknown).
available_version() {
  brew info "$1" 2>/dev/null | sed -nE '1s/.*: stable ([^ ,]+).*/\1/p'
}

# True if version $1 is newer than version $2.
newer_than() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

# For each exclusion caused by a broken library, say whether anything has changed since.
check_watched() {
  local ffmpeg_now option formula broken broken_ffmpeg last_good since reason now
  ffmpeg_now="$(available_version "$FORMULA")"
  while IFS='|' read -r option formula broken broken_ffmpeg last_good since reason; do
    [ -n "$formula" ] || continue
    now="$(available_version "$formula")"
    if [ -z "$now" ] || [ -z "$ffmpeg_now" ]; then
      echo "  $option: couldn't get current versions from Homebrew"
    elif newer_than "$now" "$broken" || newer_than "$ffmpeg_now" "$broken_ffmpeg"; then
      echo "  $option: WORTH TRYING AGAIN - now $formula $now with ffmpeg $ffmpeg_now" \
           "(broke with $formula $broken and ffmpeg $broken_ffmpeg)."
      echo "    Try: $0 --force --include $option"
    else
      echo "  $option: still excluded - $formula $now and ffmpeg $ffmpeg_now are the versions that broke."
    fi
  done <<<"$EXCLUSIONS"
}

show_exclusions() {
  local option formula broken broken_ffmpeg last_good since reason
  echo "Excluded ffmpeg options (edit EXCLUSIONS in $0):"
  while IFS='|' read -r option formula broken broken_ffmpeg last_good since reason; do
    echo
    echo "--with-$option"
    echo "$reason" | fold -s -w 88 | sed 's/^/    /'
    if [ -n "$formula" ]; then
      echo "    Broken:    $formula $broken with ffmpeg $broken_ffmpeg (excluded $since)"
      echo "    Last good: $formula $last_good"
    fi
  done <<<"$EXCLUSIONS"
  echo
  echo "Checking Homebrew for newer versions:"
  check_watched
}

if [ $SHOW_EXCLUSIONS -eq 1 ]; then
  show_exclusions
  exit 0
fi

LOG="$HOME/Library/Logs/ffmpeg_brew_update_$(date -u +%Y%m%dT%H%M%SZ).log"
exec > >(tee -a "$LOG") 2>&1

# Uninstalling ffmpeg otherwise makes Homebrew autoremove every library only ffmpeg used
# (openapv, sdl2-compat, sdl3 and others), which are then reinstalled moments later.
export HOMEBREW_NO_AUTOREMOVE=1

step() { echo; echo "==> $*"; }
fail() { echo; echo "FAILED: $*"; echo "Log: $LOG"; exit 1; }

# Does ffmpeg run, link cleanly, and have the required features?
# Returns 0 if all is well, 1 if ffmpeg is broken, 2 if it works but a required feature is missing.
check_ffmpeg() {
  local ok=0 missing=0
  if ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; then
    echo "ffmpeg or ffprobe is not installed"; return 1
  fi
  ffmpeg -hide_banner -version 2>&1 | head -1
  ffprobe -hide_banner -version 2>&1 | head -1
  if ! ffmpeg -hide_banner -version >/dev/null 2>&1; then echo "ffmpeg does not start"; return 1; fi
  if ! ffprobe -hide_banner -version >/dev/null 2>&1; then echo "ffprobe does not start"; return 1; fi
  if command -v ffplay >/dev/null && ! ffplay -hide_banner -version >/dev/null 2>&1; then
    echo "ffplay does not start (ffmpeg and ffprobe are unaffected):"
    ffplay -hide_banner -version 2>&1 | grep -m1 'Library not loaded'
    ok=1
  fi
  # 'brew linkage --test' also exits non-zero for "Indirect dependencies with linkage"
  # (libraries used but not declared as direct dependencies), which is harmless; only
  # broken or missing libraries count as a failure.
  local linkage
  linkage="$(brew linkage --test ffmpeg 2>&1)"
  if grep -qE '^(Broken|Missing|Unwanted system)' <<<"$linkage"; then
    echo "brew linkage reports broken libraries:"; echo "$linkage"; ok=1
  elif [ -n "$linkage" ]; then
    echo "brew linkage notes (not a problem):"
    # shellcheck disable=SC2001
    sed 's/^/  /' <<<"$linkage"
  fi
  # The features required (REQUIRE_* and --require-*). Each list is captured once: piping
  # straight into 'grep -q' can make ffmpeg die of SIGPIPE, which pipefail then reports as
  # a missing feature.
  local list
  if [ -n "${REQUIRE_ENCODERS// /}" ]; then
    echo "Required encoders: $REQUIRE_ENCODERS"
    list="$(ffmpeg -hide_banner -encoders 2>/dev/null)"
    for feature in $REQUIRE_ENCODERS; do
      grep -qE "^ [A-Z.]{6} $feature " <<<"$list" || { echo "missing encoder: $feature"; missing=1; }
    done
  else
    echo "Required encoders: none checked"
  fi
  if [ -n "${REQUIRE_DECODERS// /}" ]; then
    echo "Required decoders: $REQUIRE_DECODERS"
    list="$(ffmpeg -hide_banner -decoders 2>/dev/null)"
    for feature in $REQUIRE_DECODERS; do
      grep -qE "^ [A-Z.]{6} $feature " <<<"$list" || { echo "missing decoder: $feature"; missing=1; }
    done
  else
    echo "Required decoders: none checked"
  fi
  if [ -n "${REQUIRE_FILTERS// /}" ]; then
    echo "Required filters: $REQUIRE_FILTERS"
    list="$(ffmpeg -hide_banner -filters 2>/dev/null)"
    for feature in $REQUIRE_FILTERS; do
      grep -qE "^ [A-Z.|]{2,3} $feature " <<<"$list" || { echo "missing filter: $feature"; missing=1; }
    done
  else
    echo "Required filters: none checked"
  fi
  # A real round trip: one second of generated tone to WAV and back.
  local tmp; tmp="$(mktemp -d)"
  if ! ffmpeg -hide_banner -loglevel error -f lavfi -i "sine=frequency=440:duration=1" "$tmp/t.wav" \
     || ! ffprobe -hide_banner -loglevel error -show_entries format=duration -of csv=p=0 "$tmp/t.wav" >/dev/null; then
    echo "test encode failed"; ok=1
  fi
  rm -rf "$tmp"
  [ $ok -ne 0 ] && return 1
  [ $missing -ne 0 ] && return 2
  return 0
}

echo "ffmpeg_brew_update: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Log: $LOG"

step "Checking the current ffmpeg"
check_ffmpeg
status=$?
if [ $status -eq 0 ]; then
  echo "ffmpeg is working."
  if [ $CHECK_ONLY -eq 1 ] || [ $FORCE -eq 0 ]; then
    [ $CHECK_ONLY -eq 0 ] && echo "Nothing to do (use --force to rebuild anyway)."
    exit 0
  fi
elif [ $status -eq 2 ]; then
  # ffmpeg itself works, so don't rebuild on the strength of a feature that may be misspelt
  # or never part of this build.
  echo "ffmpeg works, but a required feature is missing."
  if [ $CHECK_ONLY -eq 1 ] || [ $FORCE -eq 0 ]; then
    [ $CHECK_ONLY -eq 0 ] && echo "Not rebuilding: check the names, then use --force if a rebuild should add them."
    exit 1
  fi
else
  echo "ffmpeg needs rebuilding."
  [ $CHECK_ONLY -eq 1 ] && exit 1
fi

step "Updating Homebrew"
brew update || fail "brew update"

step "Trusting and tapping the ffmpeg tap"
brew trust homebrew-ffmpeg/ffmpeg || fail "brew trust"
brew tap homebrew-ffmpeg/ffmpeg || fail "brew tap"

step "Checking whether any excluded library is worth trying again"
check_watched

if [ $CLEAN -eq 1 ]; then
  step "Clean: removing chromaprint and zvbi"
  brew uninstall --force --ignore-dependencies chromaprint zvbi 2>/dev/null || true
fi

step "Installing helpers (chromaprint, zvbi)"
brew install chromaprint || fail "chromaprint"
brew tap lescanauxdiscrets/tap || fail "tap lescanauxdiscrets/tap"
brew install lescanauxdiscrets/tap/zvbi || fail "zvbi"

step "Removing the old ffmpeg"
brew uninstall --force --ignore-dependencies ffmpeg 2>/dev/null || true

step "Choosing options"
EXCLUDED="$(cut -d'|' -f1 <<<"$EXCLUSIONS")"
OPTIONS=""
for opt in $(brew options "$FORMULA" | grep -E -- '^--with-' | awk '{print $1}'); do
  name="${opt#--with-}"
  if grep -qx -- "$name" <<<"$EXCLUDED"; then
    if echo " $INCLUDE " | grep -q -- " $name "; then
      echo "  include $opt (excluded, but put back with --include for this run)"
      OPTIONS="$OPTIONS $opt"
    else
      echo "  skip    $opt"
    fi
  else
    echo "  include $opt"; OPTIONS="$OPTIONS $opt"
  fi
done
[ -n "$OPTIONS" ] || fail "no options found (is the tap trusted and tapped?)"
for name in $EXCLUDED; do
  brew options "$FORMULA" | grep -qx -- "--with-$name" \
    || echo "  note: excluded option --with-$name no longer exists in the tap; remove it from EXCLUSIONS"
done

step "Bringing ffmpeg's dependencies up to date"
# Out-of-date or half-upgraded libraries are the usual cause of a broken build or a
# 'Library not loaded' crash, so upgrade every dependency before compiling against them.
# Only upgrade what is already installed; the ffmpeg install below adds anything missing.
ALL_DEPS="$(brew deps --include-build --include-optional "$FORMULA" 2>/dev/null)"
OUTDATED="$(brew outdated --formula --quiet 2>/dev/null)"
UPGRADE=""
for dep in $ALL_DEPS; do
  if grep -qx -- "$dep" <<<"$OUTDATED"; then UPGRADE="$UPGRADE $dep"; fi
done
if [ -n "$UPGRADE" ]; then
  echo "Upgrading:$UPGRADE"
  # shellcheck disable=SC2086
  brew upgrade $UPGRADE || fail "upgrading dependencies"
else
  echo "All installed dependencies are up to date."
fi
# Anything installed but with a missing keg (like openapv earlier) gets reinstalled.
echo "Checking installed dependencies for missing files"
INSTALLED="$(brew list --formula -1 2>/dev/null)"
PREFIX="$(brew --prefix)"
for dep in $ALL_DEPS; do
  if grep -qx -- "$dep" <<<"$INSTALLED" && [ ! -e "$PREFIX/opt/$dep" ]; then
    echo "Reinstalling $dep (installed but its files are missing)"
    brew reinstall "$dep" || fail "reinstalling $dep"
  fi
done

step "Building ffmpeg (this takes a while)"
# shellcheck disable=SC2086
if ! brew install "$FORMULA" $OPTIONS; then
  [ -n "$INCLUDE" ] && echo "The build included:$INCLUDE - rerun without --include to build without it."
  fail "building ffmpeg"
fi

step "Checking the new ffmpeg"
check_ffmpeg
case $? in
  0) ;;
  2) fail "ffmpeg built and works, but a required feature is missing (see above)" ;;
  *) fail "ffmpeg built but the checks did not pass" ;;
esac

echo
echo "Done: ffmpeg is installed and working."
if [ -n "$INCLUDE" ]; then
  echo "It built with:$INCLUDE. If you want to keep that, remove those entries from EXCLUSIONS."
fi
echo "Note: a later 'brew upgrade' can update a library ffmpeg was built against and break it again."
echo "Run '$0 --check' after upgrading, and this script again if the check fails."
echo "Log: $LOG"
