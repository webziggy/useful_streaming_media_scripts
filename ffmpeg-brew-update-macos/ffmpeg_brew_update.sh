#!/bin/bash
# Rebuild ffmpeg from the homebrew-ffmpeg tap with (almost) every --with- option,
# after bringing its dependencies up to date, and check the result actually runs.
#
# Usage:
#   ffmpeg_brew_update.sh                 check first; rebuild only if ffmpeg is broken, missing or outdated
#   ffmpeg_brew_update.sh --check         only run the checks (including for a newer version), change nothing
#   ffmpeg_brew_update.sh --dry-run       run the checks and show what a rebuild would do, change nothing
#   ffmpeg_brew_update.sh --force         rebuild even if ffmpeg is working and up to date
#   ffmpeg_brew_update.sh --clean         like --force, but first force-uninstall and reinstall chromaprint and zvbi
#   ffmpeg_brew_update.sh --exclusions    list the excluded options, why, and whether a
#                                         broken library has a newer version worth trying
#   ffmpeg_brew_update.sh --include libflite
#                                         rebuild with an excluded option put back, just for this
#                                         run (repeatable); if it builds, remove its entry from EXCLUSIONS
#   ffmpeg_brew_update.sh --decklink-sdk ~/Downloads/Blackmagic_DeckLink_SDK
#                                         rebuild with DeckLink, using the headers from that SDK
#                                         folder (untested; see the README)
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
# Exit codes: 0 working (or rebuilt), 1 broken or the rebuild failed, 2 bad arguments,
#   3 working but a newer version is available (--check), 4 working but a required feature is missing.
#
# After any 'brew upgrade', run it with no options: it rebuilds only if ffmpeg is broken or
# outdated. Each run writes a log to ~/Library/Logs/ffmpeg_brew_update_<UTC>.log (the last
# 20 are kept).

set -uo pipefail

FORMULA="homebrew-ffmpeg/ffmpeg/ffmpeg"
LOG_KEEP=20

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
# (Read with 'read' rather than $(cat <<EOF): bash 3.2, as shipped with macOS, misparses
# quotes and brackets in a here-document inside $(...).)
IFS= read -r -d '' EXCLUSIONS <<'EOF'
chromaprint||||||chromaprint itself depends on ffmpeg, so building ffmpeg with it is circular. chromaprint is installed separately instead.
alt-name||||||Not a library: installs the tools as ffmpeg-alt, ffprobe-alt and so on. Not wanted.
decklink|||9.0.1||2026-09-17|Needs the Blackmagic DeckLink SDK (a manual download from Blackmagic) and, to be of any use, DeckLink hardware with the Desktop Video drivers. Without the SDK, configure stops with "ERROR: DeckLinkAPI.h not found" (tested 2026-09-17 with ffmpeg 9.0.1). To try it, use --decklink-sdk <SDK folder> (untested).
libflite|||9.0.1||2026-09-17|The tap's option doesn't install the flite library, so configure stops with "ERROR: libflite not found" ('flite/flite.h' file not found) (tested 2026-09-17 with ffmpeg 9.0.1). Untested: it may build after 'brew install flite'.
EOF
EXCLUSIONS="${EXCLUSIONS%$'\n'}"

usage() {
  # Print the comment block at the top of this file, without the leading '# '.
  sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0"
}
die_usage() { echo "$*" >&2; exit 2; }

is_excluded() { cut -d'|' -f1 <<<"$EXCLUSIONS" | grep -qx -- "$1"; }
is_included() { case " $INCLUDE " in *" $1 "*) return 0 ;; esac; return 1; }

FORCE=0; CLEAN=0; CHECK_ONLY=0; DRY_RUN=0; SHOW_EXCLUSIONS=0; INCLUDE=""; DECKLINK_INCLUDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --force) FORCE=1 ;;
    --clean) CLEAN=1; FORCE=1 ;;
    --check) CHECK_ONLY=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --exclusions) SHOW_EXCLUSIONS=1 ;;
    --include)
      [ $# -ge 2 ] || die_usage "--include needs an option name, e.g. --include libflite"
      name="${2#--with-}"
      is_excluded "$name" || die_usage "'$name' is not in the exclusions list (see --exclusions)"
      is_included "$name" || INCLUDE="$INCLUDE $name"
      FORCE=1; shift ;;
    --decklink-sdk)
      [ $# -ge 2 ] || die_usage "--decklink-sdk needs the SDK folder, e.g. --decklink-sdk ~/Downloads/Blackmagic_DeckLink_SDK"
      for dir in "$2" "$2/Mac/include" "$2/include"; do
        if [ -f "$dir/DeckLinkAPI.h" ]; then DECKLINK_INCLUDE="$(cd "$dir" && pwd)"; break; fi
      done
      [ -n "$DECKLINK_INCLUDE" ] || die_usage "No DeckLinkAPI.h in '$2' or its Mac/include folder."
      is_included decklink || INCLUDE="$INCLUDE decklink"
      FORCE=1; shift ;;
    --require-encoders|--require-decoders|--require-filters)
      [ $# -ge 2 ] || die_usage "$1 needs a list, e.g. $1 \"name1 name2\" (or none)"
      list="$2"; [ "$list" = "none" ] && list=""
      case "$1" in
        --require-encoders) REQUIRE_ENCODERS="$list" ;;
        --require-decoders) REQUIRE_DECODERS="$list" ;;
        --require-filters)  REQUIRE_FILTERS="$list" ;;
      esac
      shift ;;
    *) { echo "Unknown option: $1"; echo; usage; } >&2; exit 2 ;;
  esac
  shift
done
if is_included decklink && [ -z "$DECKLINK_INCLUDE" ]; then
  die_usage "DeckLink needs its SDK headers: use --decklink-sdk <SDK folder> rather than --include decklink."
fi

# Names are matched against ffmpeg's lists, so allow only the characters they use.
# (set -f: a name like '*' must not expand to file names before it is checked.)
set -f
for list in "$REQUIRE_ENCODERS" "$REQUIRE_DECODERS" "$REQUIRE_FILTERS"; do
  for feature in $list; do
    [[ "$feature" =~ ^[A-Za-z0-9_]+$ ]] || die_usage "'$feature' isn't a valid encoder, decoder or filter name"
  done
done
set +f

# Colour on a terminal only (the log gets the text without it).
if [ -t 1 ]; then
  C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RED=$'\033[1;31m'; C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'; C_BLUE=$'\033[1;34m'; C_OFF=$'\033[0m'
else
  C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_OFF=""
fi

# Find Homebrew even when PATH doesn't include it (e.g. under launchd or cron), and check
# Homebrew's ffmpeg by its full path rather than whichever ffmpeg is first on PATH.
if ! command -v brew >/dev/null; then
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$candidate" ]; then eval "$("$candidate" shellenv)"; break; fi
  done
fi
command -v brew >/dev/null || { echo "Homebrew not found (looked on PATH, in /opt/homebrew and /usr/local)." >&2; exit 1; }
PREFIX="$(brew --prefix)"
FFMPEG="$PREFIX/opt/ffmpeg/bin/ffmpeg"
FFPROBE="$PREFIX/opt/ffmpeg/bin/ffprobe"
FFPLAY="$PREFIX/opt/ffmpeg/bin/ffplay"
FPCALC="$PREFIX/opt/chromaprint/bin/fpcalc"

# The stable version Homebrew currently offers for a formula (empty if unknown).
available_version() {
  # The first line is "==> name: stable 1.2", or "==> name: 1.1 → stable 1.2" when outdated.
  brew info "$1" 2>/dev/null | sed -nE '1s/.*[: ]stable ([^ ,]+).*/\1/p'
}

# The installed version of a formula (empty if not installed).
installed_version() { brew list --versions "$1" 2>/dev/null | awk '{print $NF}'; }

# True if version $1 is newer than version $2.
newer_than() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

# For each exclusion caused by a broken library, say whether anything has changed since.
check_watched() {
  local ffmpeg_now option formula broken broken_ffmpeg last_good since reason now any=0
  ffmpeg_now="$(available_version "$FORMULA")"
  while IFS='|' read -r option formula broken broken_ffmpeg last_good since reason; do
    [ -n "$formula" ] || continue
    any=1
    now="$(available_version "$formula")"
    if [ -z "$now" ] || [ -z "$ffmpeg_now" ]; then
      echo "  $option: couldn't get current versions from Homebrew"
    elif newer_than "$now" "$broken" || newer_than "$ffmpeg_now" "$broken_ffmpeg"; then
      echo "  $option: ${C_YELLOW}WORTH TRYING AGAIN${C_OFF} - now $formula $now with ffmpeg $ffmpeg_now" \
           "(broke with $formula $broken and ffmpeg $broken_ffmpeg)."
      echo "    Try: $0 --include $option"
    else
      echo "  $option: still excluded - $formula $now and ffmpeg $ffmpeg_now are the versions that broke."
    fi
  done <<<"$EXCLUSIONS"
  [ $any -eq 1 ] || echo "  No exclusion is waiting on a library version."
}

show_exclusions() {
  local option formula broken broken_ffmpeg last_good since reason
  echo "Excluded ffmpeg options (edit EXCLUSIONS in $0):"
  while IFS='|' read -r option formula broken broken_ffmpeg last_good since reason; do
    echo
    echo "${C_BOLD}--with-$option${C_OFF}"
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

# Only one run at a time: two rebuilds would collide, and a check during a rebuild would
# find ffmpeg missing. A lock left by a run that no longer exists is taken over.
LOCK="${TMPDIR:-/tmp}/ffmpeg_brew_update.lock"
HAVE_LOCK=0
if ! mkdir "$LOCK" 2>/dev/null; then
  lock_pid="$(cat "$LOCK/pid" 2>/dev/null)"
  if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
    echo "Another run of this script is in progress (process $lock_pid). Wait for it to finish." >&2
    exit 1
  fi
  rm -rf "$LOCK"
  mkdir "$LOCK" 2>/dev/null || { echo "Couldn't create the lock $LOCK" >&2; exit 1; }
fi
echo $$ >"$LOCK/pid"
HAVE_LOCK=1

# Log everything, without colour codes, and keep the last LOG_KEEP logs. The logger ignores
# Ctrl-C so that the message printed on the way out still reaches the terminal and the log.
LOG="$HOME/Library/Logs/ffmpeg_brew_update_$(date -u +%Y%m%dT%H%M%SZ).log"
: >>"$LOG"   # create it now, so the pruning below counts it
if [ -t 1 ]; then
  exec > >(trap '' INT; tee /dev/tty | sed -l $'s/\033\\[[0-9;]*m//g' >>"$LOG") 2>&1
else
  exec > >(trap '' INT; sed -l $'s/\033\\[[0-9;]*m//g' | tee -a "$LOG") 2>&1
fi
# shellcheck disable=SC2012
ls -1t "$HOME"/Library/Logs/ffmpeg_brew_update_*.log 2>/dev/null | tail -n +$((LOG_KEEP + 1)) \
  | while IFS= read -r old; do rm -f "$old"; done

# Uninstalling ffmpeg otherwise makes Homebrew autoremove every library only ffmpeg used
# (sdl2-compat, sdl3 and others), which are then reinstalled moments later.
export HOMEBREW_NO_AUTOREMOVE=1
# Upgrading a library otherwise makes Homebrew upgrade its outdated dependents too, which can
# pull in homebrew-core's ffmpeg (chromaprint depends on it) or rebuild the tap's ffmpeg itself.
# This script rebuilds ffmpeg and chromaprint itself, so it doesn't need that.
export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1

# Steps are timed for the summary at the end.
STEP_NAME=""; STEP_START=$SECONDS; STEP_TIMES=""
fmt_secs() {
  if [ "$1" -ge 60 ]; then printf '%dm %02ds' $(($1 / 60)) $(($1 % 60)); else printf '%ds' "$1"; fi
}
end_step() {
  [ -n "$STEP_NAME" ] && STEP_TIMES="$STEP_TIMES$(fmt_secs $((SECONDS - STEP_START)))|$STEP_NAME"$'\n'
  STEP_NAME=""
}
step() {
  end_step
  STEP_NAME="$*"; STEP_START=$SECONDS
  echo; echo "${C_BLUE}==>${C_OFF} ${C_BOLD}$*${C_OFF} ${C_DIM}($(date +%H:%M:%S))${C_OFF}"
}
fail() {
  echo; echo "${C_RED}FAILED:${C_OFF} $*"
  echo "Log: $LOG"
  exit 1
}
notify() {
  osascript -e "display notification \"$1\" with title \"ffmpeg_brew_update\"" >/dev/null 2>&1 || true
}

# DeckLink headers are copied into Homebrew's include folder (where the tap's formula looks
# for them) just for the build; only files this run copied are removed again.
DECKLINK_COPIED=""
remove_decklink_headers() {
  local base
  for base in $DECKLINK_COPIED; do rm -f "$PREFIX/include/$base"; done
  DECKLINK_COPIED=""
}

REBUILDING=0; REMOVED_FFMPEG=0
on_exit() {
  local rc=$?
  trap - EXIT
  [ -n "$DECKLINK_COPIED" ] && remove_decklink_headers
  if [ $REMOVED_FFMPEG -eq 1 ] && [ ! -x "$FFMPEG" ]; then
    echo
    echo "${C_RED}ffmpeg is not installed right now:${C_OFF} this run stopped after removing the old one."
    echo "Run this script again to build it."
  fi
  if [ $REBUILDING -eq 1 ]; then
    if [ $rc -eq 0 ]; then notify "ffmpeg rebuilt and working."; else notify "ffmpeg rebuild FAILED - see the log."; fi
  fi
  [ $HAVE_LOCK -eq 1 ] && rm -rf "$LOCK"
  exit $rc
}
trap on_exit EXIT
trap 'exit 130' INT TERM

# Does ffmpeg run, link cleanly, and have the required features?
# Returns 0 if all is well, 1 if ffmpeg is broken, 4 if it works but a required feature is missing.
check_ffmpeg() {
  local ok=0 missing=0
  if [ ! -x "$FFMPEG" ] || [ ! -x "$FFPROBE" ]; then
    echo "ffmpeg or ffprobe is not installed (looked in $PREFIX/opt/ffmpeg/bin)"; return 1
  fi
  local on_path; on_path="$(command -v ffmpeg 2>/dev/null)"
  if [ -n "$on_path" ] && [ "$on_path" != "$PREFIX/bin/ffmpeg" ]; then
    echo "Note: 'ffmpeg' on your PATH is $on_path, not Homebrew's. This script checks Homebrew's."
  fi
  "$FFMPEG" -hide_banner -version 2>&1 | head -1
  "$FFPROBE" -hide_banner -version 2>&1 | head -1
  if ! "$FFMPEG" -hide_banner -version >/dev/null 2>&1; then echo "ffmpeg does not start"; return 1; fi
  if ! "$FFPROBE" -hide_banner -version >/dev/null 2>&1; then echo "ffprobe does not start"; return 1; fi
  if [ -x "$FFPLAY" ] && ! "$FFPLAY" -hide_banner -version >/dev/null 2>&1; then
    echo "ffplay does not start (ffmpeg and ffprobe are unaffected):"
    "$FFPLAY" -hide_banner -version 2>&1 | grep -m1 'Library not loaded'
    ok=1
  fi
  # A leftover link from the old sdl2 formula makes builds pick up a library that's gone
  # (see "ffplay fails with libSDL2-2.0.0.dylib not found" in the README).
  local sdl="$PREFIX/lib/libSDL2-2.0.0.dylib"
  if [ -L "$sdl" ] && ! readlink "$sdl" | grep -q 'sdl2-compat'; then
    echo "Note: $sdl points to $(readlink "$sdl"), not sdl2-compat; ffplay may break. See the README."
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
    list="$("$FFMPEG" -hide_banner -encoders 2>/dev/null)"
    for feature in $REQUIRE_ENCODERS; do
      grep -qE "^ [A-Z.]{6} $feature " <<<"$list" || { echo "missing encoder: $feature"; missing=1; }
    done
  else
    echo "Required encoders: none checked"
  fi
  if [ -n "${REQUIRE_DECODERS// /}" ]; then
    echo "Required decoders: $REQUIRE_DECODERS"
    list="$("$FFMPEG" -hide_banner -decoders 2>/dev/null)"
    for feature in $REQUIRE_DECODERS; do
      grep -qE "^ [A-Z.]{6} $feature " <<<"$list" || { echo "missing decoder: $feature"; missing=1; }
    done
  else
    echo "Required decoders: none checked"
  fi
  if [ -n "${REQUIRE_FILTERS// /}" ]; then
    echo "Required filters: $REQUIRE_FILTERS"
    list="$("$FFMPEG" -hide_banner -filters 2>/dev/null)"
    for feature in $REQUIRE_FILTERS; do
      grep -qE "^ [A-Z.|]{2,3} $feature " <<<"$list" || { echo "missing filter: $feature"; missing=1; }
    done
  else
    echo "Required filters: none checked"
  fi
  # A real round trip: one second of generated tone to WAV and back.
  local tmp; tmp="$(mktemp -d)"
  if ! "$FFMPEG" -nostdin -hide_banner -loglevel error -f lavfi -i "sine=frequency=440:duration=1" "$tmp/t.wav" \
     || ! "$FFPROBE" -hide_banner -loglevel error -show_entries format=duration -of csv=p=0 "$tmp/t.wav" >/dev/null; then
    echo "test encode failed"; ok=1
  fi
  rm -rf "$tmp"
  [ $ok -ne 0 ] && return 1
  [ $missing -ne 0 ] && return 4
  return 0
}

# Work out the options to build with: every --with- option the tap offers, minus the
# exclusions, plus anything put back with --include. Sets TAP_OPTIONS, OPTIONS, SKIPPED
# and PUT_BACK. Returns 1 if the tap's options can't be read.
choose_options() {
  local opt name
  TAP_OPTIONS="$(brew options "$FORMULA" 2>/dev/null | grep -E -- '^--with-' | awk '{print $1}')"
  [ -n "$TAP_OPTIONS" ] || return 1
  OPTIONS=""; SKIPPED=""; PUT_BACK=""
  for opt in $TAP_OPTIONS; do
    name="${opt#--with-}"
    if is_excluded "$name"; then
      if is_included "$name"; then PUT_BACK="$PUT_BACK $opt"; OPTIONS="$OPTIONS $opt"
      else SKIPPED="$SKIPPED $opt"; fi
    else
      OPTIONS="$OPTIONS $opt"
    fi
  done
}

count_words() { echo $#; }

print_options() {
  # shellcheck disable=SC2086
  echo "  Including $(count_words $OPTIONS) options:"
  fold -s -w 84 <<<"${OPTIONS# }" | sed 's/^/    /'
  [ -n "$PUT_BACK" ] && echo "  Put back with --include for this run:$PUT_BACK"
  [ -n "$SKIPPED" ] && echo "  Skipping (in EXCLUSIONS):$SKIPPED"
  local name
  while IFS='|' read -r name _; do
    grep -qx -- "--with-$name" <<<"$TAP_OPTIONS" \
      || echo "  ${C_YELLOW}note:${C_OFF} excluded option --with-$name no longer exists in the tap; remove it from EXCLUSIONS"
  done <<<"$EXCLUSIONS"
}

# Work out which installed dependencies to upgrade or reinstall. Only ffmpeg's runtime and
# optional libraries (all the way down) and its own direct build tools count: the build
# tools of those libraries (node, rust, llvm, Python and so on) aren't needed, because the
# libraries come as bottles. Libraries of excluded options are left alone (unless put back
# with --include): ffmpeg isn't built against them, and upgrading one can break things.
# Sets DEPS, UPGRADE and REINSTALL. Returns 1 if the dependencies can't be listed.
plan_deps() {
  local all skip="" option formula dep outdated installed
  all="$( { brew deps --include-optional "$FORMULA"; brew deps --1 --include-build "$FORMULA"; } 2>/dev/null | sort -u)"
  [ -n "$all" ] || return 1
  while IFS='|' read -r option formula _; do
    is_included "$option" && continue
    skip="$skip $option $formula"
  done <<<"$EXCLUSIONS"
  DEPS=""
  for dep in $all; do
    case " $skip " in
      *" $dep "*) echo "  leaving $dep alone (its option is excluded)" ;;
      *) DEPS="$DEPS $dep" ;;
    esac
  done
  outdated="$(brew outdated --formula --quiet 2>/dev/null)"
  installed="$(brew list --formula -1 2>/dev/null)"
  UPGRADE=""; REINSTALL=""
  for dep in $DEPS; do
    grep -qx -- "$dep" <<<"$outdated" && UPGRADE="$UPGRADE $dep"
    # Installed but with its files missing (as happened to openapv once).
    if grep -qx -- "$dep" <<<"$installed" && [ ! -e "$PREFIX/opt/$dep" ]; then REINSTALL="$REINSTALL $dep"; fi
  done
  return 0
}

# Is the installed ffmpeg the build from the tap, and the version the tap currently offers?
# Also reports options the tap has added since this build. Prints why not and returns 1 if
# it isn't the tap build, 3 if it's outdated, else 0.
check_install() {
  if ! brew list --formula --full-name 2>/dev/null | grep -qx -- "$FORMULA"; then
    echo "The installed ffmpeg is not the $FORMULA build."
    return 1
  fi
  # 'brew outdated' prints e.g. "homebrew-ffmpeg/ffmpeg/ffmpeg (9.0.1) < 9.1" when a newer
  # version is available, and nothing when it's current.
  local outdated
  outdated="$(brew outdated --formula --verbose "$FORMULA" 2>/dev/null)"
  if [ -n "$outdated" ]; then
    echo "ffmpeg is outdated: $outdated"
    return 3
  fi
  echo "ffmpeg is the latest version the tap offers ($(installed_version ffmpeg))."
  # The options this build was made with are the receipt's "used_options" (it also lists
  # "unused_options", so read just that key; plutil reads JSON).
  local receipt="$PREFIX/opt/ffmpeg/INSTALL_RECEIPT.json" built opt new="" extra=""
  if [ -f "$receipt" ] && choose_options \
     && built="$(plutil -extract used_options json -o - "$receipt" 2>/dev/null | grep -oE '"--with-[^"]+"' | tr -d '"')" \
     && [ -n "$built" ]; then
    for opt in $OPTIONS; do grep -qx -- "$opt" <<<"$built" || new="$new $opt"; done
    for opt in $built; do is_excluded "${opt#--with-}" && ! is_included "${opt#--with-}" && extra="$extra $opt"; done
    [ -n "$new" ] && echo "${C_YELLOW}The tap offers options this build doesn't have:${C_OFF}$new (run with --force to add them)."
    [ -n "$extra" ] && echo "This build has options that are in EXCLUSIONS:$extra (if they're wanted, remove them from EXCLUSIONS)."
  fi
  return 0
}

echo "ffmpeg_brew_update: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Log: $LOG"
FF_BEFORE="$(installed_version ffmpeg)"

step "Checking the current ffmpeg"
check_ffmpeg
status=$?
if [ $status -ne 1 ]; then
  check_install
  case $? in
    1) status=1 ;;
    3) status=3 ;;  # a newer version is reason enough to rebuild, even with a feature missing
  esac
fi
WHY=""
case $status in
  0) echo "${C_GREEN}ffmpeg is working.${C_OFF}"
     [ $FORCE -eq 1 ] || WHY="Nothing to do (use --force to rebuild anyway)." ;;
  3) echo "ffmpeg works, but a newer version is available." ;;
  4) # ffmpeg itself works, so don't rebuild on the strength of a feature that may be
     # misspelt or never part of this build.
     echo "ffmpeg works, but a required feature is missing."
     [ $FORCE -eq 1 ] || WHY="Not rebuilding: check the names, then use --force if a rebuild should add them." ;;
  *) echo "${C_RED}ffmpeg needs rebuilding.${C_OFF}" ;;
esac

if [ $CHECK_ONLY -eq 1 ]; then
  case $status in
    1) echo "Run without --check to rebuild it." ;;
    3) echo "Run without --check to update it." ;;
  esac
  exit $status
fi

if [ $DRY_RUN -eq 1 ]; then
  step "Dry run: what a rebuild would do (nothing is changed)"
  if [ -n "$WHY" ]; then
    echo "A run with these options would not rebuild. $WHY"
    echo "With --force, it would do the following."
  else
    echo "A run with these options would rebuild ffmpeg, as follows."
  fi
  echo "(Versions are as Homebrew knows them now; a real run updates Homebrew first.)"
  echo
  [ $CLEAN -eq 1 ] && echo "Force-uninstall chromaprint and zvbi, then reinstall them."
  echo "Options:"
  if choose_options; then print_options; else echo "  Couldn't read the tap's options: is $FORMULA tapped?"; fi
  [ -n "$DECKLINK_INCLUDE" ] && echo "Copy the DeckLink headers from $DECKLINK_INCLUDE into $PREFIX/include for the build, then remove them."
  echo "Dependencies:"
  if plan_deps; then
    if [ -n "$UPGRADE" ]; then echo "  Would upgrade:$UPGRADE"; else echo "  All installed dependencies are up to date."; fi
    [ -n "$REINSTALL" ] && echo "  Would reinstall (files missing):$REINSTALL"
  else
    echo "  Couldn't list ffmpeg's dependencies (brew deps)."
  fi
  echo "Then: uninstall ffmpeg ${FF_BEFORE:-(not installed)}, build $FORMULA $(available_version "$FORMULA") with the options above, check it, and install chromaprint."
  exit 0
fi

if [ -n "$WHY" ]; then
  echo "$WHY"
  exit $status
fi

# From here on ffmpeg is being rebuilt: keep the Mac awake until this script exits, and
# send a notification at the end.
REBUILDING=1
caffeinate -i -w $$ >/dev/null 2>&1 &

xcode-select -p >/dev/null 2>&1 \
  || fail "the Xcode Command Line Tools are needed to compile ffmpeg: run 'xcode-select --install'"

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

# chromaprint is installed after the build: it depends on ffmpeg, so installing or upgrading
# it now would make Homebrew fetch homebrew-core's ffmpeg in place of the tap's.
step "Installing zvbi"
brew tap lescanauxdiscrets/tap || fail "tap lescanauxdiscrets/tap"
brew install lescanauxdiscrets/tap/zvbi || fail "zvbi"

step "Choosing options"
choose_options || fail "no options found (is the tap trusted and tapped?)"
print_options

step "Removing the old ffmpeg"
# This must come before the dependency upgrade: while the tap's ffmpeg is installed, upgrading
# its libraries can make Homebrew try to upgrade ffmpeg too (to homebrew-core's bottle, which
# fails). Choosing the options above only reads, so it is done first.
REMOVED_FFMPEG=1
brew uninstall --force --ignore-dependencies ffmpeg 2>/dev/null || true

step "Bringing ffmpeg's dependencies up to date"
# Out-of-date or half-upgraded libraries are the usual cause of a broken build or a
# 'Library not loaded' crash, so upgrade the dependencies before compiling against them.
# Only what is already installed; the ffmpeg install below adds anything missing.
plan_deps || fail "couldn't list ffmpeg's dependencies (brew deps)"
if [ -n "$UPGRADE" ]; then
  echo "Upgrading:$UPGRADE"
  # shellcheck disable=SC2086
  brew upgrade $UPGRADE || fail "upgrading dependencies"
else
  echo "All installed dependencies are up to date."
fi
for dep in $REINSTALL; do
  echo "Reinstalling $dep (installed but its files are missing)"
  brew reinstall "$dep" || fail "reinstalling $dep"
done

if [ -n "$DECKLINK_INCLUDE" ]; then
  step "Copying the DeckLink SDK headers"
  for f in "$DECKLINK_INCLUDE"/*; do
    [ -f "$f" ] || continue
    base="${f##*/}"
    if [ -e "$PREFIX/include/$base" ]; then echo "  $base is already in $PREFIX/include; leaving it"; continue; fi
    cp "$f" "$PREFIX/include/$base" || fail "copying $base into $PREFIX/include"
    DECKLINK_COPIED="$DECKLINK_COPIED $base"
  done
  echo "Copied:$DECKLINK_COPIED (removed again after the build)"
  echo "Note: DeckLink makes this a 'nonfree' ffmpeg build, which can't be redistributed."
fi

step "Building ffmpeg (this takes a while)"
# shellcheck disable=SC2086
if ! brew install "$FORMULA" $OPTIONS; then
  [ -n "$INCLUDE" ] && echo "The build included:$INCLUDE - rerun without it to build without."
  fail "building ffmpeg"
fi
[ -n "$DECKLINK_COPIED" ] && remove_decklink_headers

step "Checking the new ffmpeg"
check_ffmpeg
case $? in
  0) ;;
  4) fail "ffmpeg built and works, but a required feature is missing (see above)" ;;
  *) fail "ffmpeg built but the checks did not pass" ;;
esac

step "Installing chromaprint (fpcalc)"
# --ignore-dependencies: chromaprint's only dependency is ffmpeg, which is the one just built.
# Without it Homebrew would replace that with homebrew-core's ffmpeg. Homebrew warns that
# the option is unsupported; that's expected.
brew install --ignore-dependencies chromaprint \
  || fail "installing chromaprint (ffmpeg itself is installed and working)"
"$FPCALC" -version 2>&1 | head -1
"$FPCALC" -version >/dev/null 2>&1 \
  || fail "fpcalc (chromaprint) does not start (ffmpeg itself is installed and working)"
end_step

echo
echo "${C_BLUE}==>${C_OFF} ${C_BOLD}Summary${C_OFF}"
# shellcheck disable=SC2086
{
  echo "  ffmpeg:        ${FF_BEFORE:-not installed} -> $(installed_version ffmpeg)"
  echo "  options:       $(count_words $OPTIONS) included, $(count_words $SKIPPED) skipped${PUT_BACK:+ (put back:$PUT_BACK)}"
  echo "  dependencies:  $(count_words $UPGRADE) upgraded, $(count_words $REINSTALL) reinstalled"
  echo "  chromaprint:   $(installed_version chromaprint)"
}
echo "  time:"
while IFS='|' read -r took name; do
  [ -n "$name" ] && printf '    %-8s %s\n' "$took" "$name"
done <<<"$STEP_TIMES"
printf '    %-8s %s\n' "$(fmt_secs $SECONDS)" "total"

echo
echo "${C_GREEN}Done: ffmpeg is installed and working.${C_OFF}"
if [ -n "$INCLUDE" ]; then
  echo "It built with:$INCLUDE. If you want to keep that, remove those entries from EXCLUSIONS."
fi
echo "Note: a later 'brew upgrade' can update a library ffmpeg was built against and break it again."
echo "Run '$0 --check' after upgrading, and this script again if the check fails."
echo "Log: $LOG"
