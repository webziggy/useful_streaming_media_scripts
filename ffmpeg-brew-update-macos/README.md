# FFmpeg Brew Update (macOS)

A script to build FFmpeg on macOS through Homebrew with almost every optional codec and feature switched on, check that the result actually works, and repair or update it when Homebrew moves on.

Homebrew's own `ffmpeg` is a ready-made build with a fixed set of features. The [`homebrew-ffmpeg/ffmpeg`](https://github.com/homebrew-ffmpeg/homebrew-ffmpeg) tap offers dozens of extra `--with-*` options instead, but then FFmpeg is compiled on your Mac. This script turns on every option except a documented list of exclusions, and looks after the problems a compiled build brings with it.

## 🚀 Quick start

```bash
chmod +x ffmpeg_brew_update.sh
./ffmpeg_brew_update.sh --help      # how to use it
./ffmpeg_brew_update.sh             # check FFmpeg; rebuild only if it's broken, missing or outdated
```

After any `brew upgrade`, run it again with no options. It checks FFmpeg and rebuilds only if a library upgrade broke it or the tap now offers a newer version. To see what it would do first:

```bash
./ffmpeg_brew_update.sh --check     # is FFmpeg working and up to date? (changes nothing)
./ffmpeg_brew_update.sh --dry-run   # what would a rebuild do? (changes nothing)
```

## 🧭 Options

| Command | What it does |
|---|---|
| `./ffmpeg_brew_update.sh` | Checks the installed FFmpeg. Rebuilds only if it's missing, fails the checks, isn't the tap's build, or the tap offers a newer version. |
| `--check` | Only runs the checks and changes nothing. See [Exit codes](#exit-codes). |
| `--dry-run` | Runs the checks, then shows what a rebuild would do: the options, which dependencies would be upgraded or reinstalled, and the version it would build. Changes nothing. Combine it with the other options to preview them, e.g. `--dry-run --include libflite`. |
| `--force` | Rebuilds even if FFmpeg is working and up to date, e.g. to add options the tap has added. |
| `--clean` | Like `--force`, but first force-uninstalls and reinstalls `chromaprint` and `zvbi`. Use it if the rebuild fails at the dependency step. |
| `--exclusions` | Lists every excluded option and why it's excluded, then asks Homebrew whether a library that broke the build has had a new release worth trying. |
| `--include <option>` | Rebuilds with one excluded option put back, for this run only, to test whether it builds now. Can be repeated. Example: `--include libflite`. |
| `--decklink-sdk <folder>` | Rebuilds with DeckLink support, using the headers from the Blackmagic DeckLink SDK in that folder. Untested; see [Decklink](#decklink). |
| `--require-encoders "<names>"` | The encoders FFmpeg must have, replacing the defaults. `none` checks none. See [Required features](#required-features). |
| `--require-decoders "<names>"` | The decoders FFmpeg must have. None are checked by default. |
| `--require-filters "<names>"` | The filters FFmpeg must have, replacing the defaults. `none` checks none. |
| `--help`, `-h` | Shows the usage summary. |

Options are checked when the script starts, so a misspelt option, an `--include` name that isn't in the exclusions list, a `--decklink-sdk` folder without `DeckLinkAPI.h`, or a feature name containing anything other than letters, digits and `_` is refused before anything changes.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | FFmpeg is working and up to date, or was rebuilt successfully. |
| `1` | FFmpeg is broken, missing or not the tap's build, or the rebuild failed. Also: another run is in progress. |
| `2` | Bad arguments. |
| `3` | FFmpeg works, but the tap offers a newer version (`--check` only; a normal run rebuilds). |
| `4` | FFmpeg works, but a required feature is missing. |

## 📝 What a rebuild does

1. **Checks the current FFmpeg** (see [The checks](#-the-checks)). Without `--force`, it stops here if everything passes, and also if FFmpeg works but only a required feature is missing. It carries on if FFmpeg is broken, isn't the tap's build, or is older than the version the tap now offers.
2. **Keeps the Mac awake** (`caffeinate`) until the run ends, and checks that the Xcode Command Line Tools are installed.
3. **Updates Homebrew** (`brew update`), trusts the `homebrew-ffmpeg/ffmpeg` tap (recent Homebrew versions require this for third-party taps) and taps it.
4. **Checks the exclusions** for any broken library that has a newer version since (see [Watching broken libraries](#-watching-broken-libraries)).
5. **Installs `zvbi`** from the `lescanauxdiscrets/tap` tap.
6. **Chooses the options:** every `--with-*` option the tap offers, except those listed in `EXCLUSIONS`. It lists the options it includes, any put back with `--include`, and those it skips, and warns if an excluded option no longer exists in the tap.
7. **Uninstalls the old FFmpeg**, without removing its dependencies. This has to come before the next step: while the tap's FFmpeg is installed, upgrading its libraries can make Homebrew try to replace it with homebrew-core's FFmpeg, which fails.
8. **Brings FFmpeg's dependencies up to date** before compiling:
   - upgrades the installed dependencies that are out of date: FFmpeg's libraries (all the way down) and FFmpeg's own build tools, but not the tools used to build those libraries (such as node, rust, llvm and Python), which bottles don't need;
   - reinstalls any dependency Homebrew lists as installed whose files are missing;
   - leaves alone the libraries of excluded options, unless put back with `--include`. FFmpeg isn't built against them, and upgrading one can break things.
9. **Builds FFmpeg** with the chosen options. With `--decklink-sdk`, the SDK's headers are copied into Homebrew's `include` folder just for the build.
10. **Checks the new FFmpeg**, and reports failure if any check fails.
11. **Installs or upgrades `chromaprint`** (for `fpcalc`) and checks that it starts. This comes last, and skips chromaprint's dependencies, because chromaprint depends on FFmpeg: installing it any earlier makes Homebrew fetch homebrew-core's FFmpeg in place of the tap's.
12. **Prints a summary:** FFmpeg's version before and after, how many options were included and skipped, how many dependencies were upgraded or reinstalled, chromaprint's version, and how long each step took. A macOS notification says whether the rebuild worked.

Each step's heading shows the time it started. If the run is interrupted or fails after step 7, it says that FFmpeg is not installed right now and that running the script again will build it.

Only one run can happen at a time. A second run, even `--check`, stops with "Another run of this script is in progress". A lock left behind by a run that was killed is taken over automatically.

## ✅ The checks

A build that compiles can still be broken, so the script checks what matters in use. It checks Homebrew's FFmpeg by its full path (`$(brew --prefix)/opt/ffmpeg/bin`), so it works under launchd or cron, where `PATH` doesn't include Homebrew, and it notes if a different `ffmpeg` comes first on your `PATH`.

- `ffmpeg` and `ffprobe` are installed and start.
- `ffplay` starts, if installed. It needs SDL, which the other tools don't use. A leftover link from the old `sdl2` formula is reported (see [Troubleshooting](#ffplay-fails-with-libsdl2-200dylib-not-found)).
- `brew linkage --test ffmpeg` finds no broken or missing libraries. Its "Indirect dependencies with linkage" notice is shown but isn't a failure: it only means FFmpeg uses libraries it doesn't list as direct dependencies.
- A real round trip works: it generates a one-second tone, writes it as a WAV file and reads it back with `ffprobe`.
- The required encoders, decoders and filters are present (see below).
- The installed FFmpeg is the `homebrew-ffmpeg/ffmpeg` build, and `brew outdated` doesn't list a newer version of it. An outdated FFmpeg that works is rebuilt on a normal run; `--check` reports it and exits with `3`.
- The options in the build's install receipt match what the script would choose now. If the tap has added options, it says so and suggests `--force`; it doesn't rebuild on its own, because a new option can break the build. It also notes any option in the build that is in `EXCLUSIONS`, e.g. after a successful `--include`.

### Required features

The script checks for the encoders, decoders and filters you need, so that a build missing one counts as a failure. The defaults suit a transcription workflow: WAV and AAC audio, silence detection, trimming, waveform images and hardware H.264 encoding.

| Kind | Default |
|---|---|
| Encoders | `aac pcm_s16le h264_videotoolbox` |
| Decoders | none |
| Filters | `silencedetect atrim showwavespic` |

Names are space-separated and must match what `ffmpeg -encoders`, `ffmpeg -decoders` and `ffmpeg -filters` list. There are three ways to change the lists, and a later one replaces an earlier one:

1. **Permanently:** edit `REQUIRE_ENCODERS`, `REQUIRE_DECODERS` and `REQUIRE_FILTERS` near the top of the script.
2. **With environment variables,** e.g. in your shell profile:
   ```bash
   export FFMPEG_REQUIRE_ENCODERS="aac libx264 libmp3lame"
   export FFMPEG_REQUIRE_FILTERS="loudnorm ebur128"
   ```
   Setting one to empty (`export FFMPEG_REQUIRE_FILTERS=`) checks none of that kind.
3. **For one run:**
   ```bash
   ./ffmpeg_brew_update.sh --check --require-encoders "aac libx264" --require-filters none
   ```

Every check prints the lists it used, e.g. `Required filters: silencedetect atrim showwavespic`, or `none checked`.

**A missing feature is treated differently from a broken FFmpeg.** If FFmpeg runs but a required feature is missing, the script reports it and exits with `4`, but doesn't start a rebuild: the name may be misspelt, or the feature may never have been part of this build. Check the names, and use `--force` if a rebuild should add the feature (for example after removing an option from `EXCLUSIONS`). If FFmpeg is also outdated, it is rebuilt anyway. If a required feature is still missing after a rebuild, the run fails with `ffmpeg built and works, but a required feature is missing`.

To see which option provides a feature, look for it in `ffmpeg -hide_banner -buildconf` or the tap's `brew options homebrew-ffmpeg/ffmpeg/ffmpeg`.

## 🚫 Exclusions

The options left out of the build are kept in one table, `EXCLUSIONS`, near the top of the script. Each line has seven fields separated by `|`:

```
option|formula|broken|ffmpeg|last good|since|reason
```

| Field | Meaning |
|---|---|
| `option` | The option name without `--with-`, e.g. `libflite`. It must match the tap's option name exactly. |
| `formula` | For a library that broke the build: its Homebrew formula. Empty for anything excluded for another reason. |
| `broken` | The version of that formula that broke the build. |
| `ffmpeg` | The FFmpeg version it broke with. |
| `last good` | The last version of the formula known to build. |
| `since` | When the option was excluded (`YYYY-MM-DD`). |
| `reason` | Why, in plain words. |

The current exclusions:

| Option | Why |
|---|---|
| `chromaprint` | chromaprint itself depends on FFmpeg, so building FFmpeg with it would be circular. It's installed separately instead. |
| `alt-name` | Not a library: it installs the tools as `ffmpeg-alt`, `ffprobe-alt` and so on. |
| `decklink` | Needs the Blackmagic DeckLink SDK (a manual download) and DeckLink hardware to be of any use. Without the SDK, configure stops with `ERROR: DeckLinkAPI.h not found`. See [Decklink](#decklink). |
| `libflite` | The tap's option doesn't install the flite library, so configure stops with `ERROR: libflite not found`. It may build after `brew install flite` (untested). |

`game-music-emu`, `openvino`, `whisper-cpp` and `librsvg` used to be excluded too, with no reason recorded. Each was test-built on its own on 17 September 2026 with FFmpeg 9.0.1: all four built and passed the checks, so they are now included. `openvino` and `whisper-cpp` bring in large dependencies (OpenVINO, whisper.cpp, llama.cpp, ONNX, OpenBLAS). To leave either out, add it back to `EXCLUSIONS` with that as the reason.

`openapv` was excluded from 16 September 2026: openapv 1.1.1.0 changed the arguments of `oapvm_create()`, so FFmpeg 9.0.1 failed to compile against it, and the upgrade from 0.3.0.0 also broke the existing FFmpeg (`liboapv.3.dylib` not found). On 24 November 2026 it built with openapv 1.1.3.0 and FFmpeg 9.1, passed the checks and encoded a test APV file, so it is now included.

No exclusion currently has a `formula` to watch. Run `./ffmpeg_brew_update.sh --exclusions` for the full, current list.

### 🔭 Watching broken libraries

For an exclusion with `formula` filled in, `--exclusions` and every rebuild compare the versions Homebrew offers now with the ones recorded as broken:

- **Neither the library nor FFmpeg has a newer version:** it stays excluded.
- **Either has a newer version:** it reports `WORTH TRYING AGAIN` and gives the command to test it, e.g.
  ```bash
  ./ffmpeg_brew_update.sh --include <option>
  ```

If that build works, delete the line from `EXCLUSIONS` (the next `--check` reminds you if you don't). If it fails, run `--force` without `--include` to go back to a working build, then update the `broken` and `ffmpeg` fields to the versions you just tried.

### Adding an exclusion

When a new option breaks the build, add a line to `EXCLUSIONS`. Fill in `formula`, `broken`, `ffmpeg` and `last good` when a library version is to blame, so the script can tell you when it's worth trying again. The last good version is in Homebrew's history for that formula, e.g. `https://github.com/Homebrew/homebrew-core/commits/master/Formula/o/openapv.rb`.

## 🩺 Troubleshooting

### `Library not loaded: …dylib` after a `brew upgrade`

This is the most common breakage. Because FFmpeg from this tap is compiled on your Mac, Homebrew doesn't rebuild it when one of its libraries gets a new version. FFmpeg then looks for a library file that no longer exists. Run the script with no options: the checks find this and it rebuilds. If the same library keeps breaking FFmpeg, consider adding it to `EXCLUSIONS`.

### The run was interrupted and FFmpeg is gone

The old FFmpeg is uninstalled shortly before the build (step 7), so stopping the run between then and the end of the build leaves no FFmpeg. The script says so as it exits. Run it again to build FFmpeg.

### Warnings from Homebrew during a rebuild

These are expected:

- `--ignore-dependencies is an unsupported Homebrew developer option`: used when installing chromaprint, so that Homebrew doesn't replace the tap's FFmpeg with homebrew-core's (step 11).
- `$HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK is set`: the script sets this so that upgrading a library doesn't make Homebrew also upgrade the formulae that use it. Otherwise Homebrew can try to upgrade the tap's FFmpeg, or pull in homebrew-core's FFmpeg for chromaprint. The script rebuilds both itself.

Upgrading dependencies can still upgrade libraries that other software uses too. That's normal for Homebrew, but check the summary and log if something else changes behaviour afterwards.

### Libraries disappear when FFmpeg is uninstalled

By default, uninstalling FFmpeg makes Homebrew autoremove every library only FFmpeg used, then reinstall them moments later. That's slow, and an interrupted run can leave a library half-removed. The script sets `HOMEBREW_NO_AUTOREMOVE=1` to prevent this.

### `ffplay` fails with `libSDL2-2.0.0.dylib` not found

Homebrew has replaced `sdl2` with `sdl2-compat`, the SDL project's SDL2 compatibility layer built on SDL3. An old `sdl2` install left linked in `/opt/homebrew/lib` makes FFmpeg's build pick up a path that no longer exists. The checks report this as a note. To fix it:

```bash
brew unlink sdl2                     # removes the old SDL2's links only
brew link --overwrite sdl2-compat
brew cleanup sdl2-compat             # deletes the old SDL2 install
ls -l /opt/homebrew/lib/libSDL2-2.0.0.dylib   # should point into Cellar/sdl2-compat
./ffmpeg_brew_update.sh --force
```

`brew list --versions sdl2-compat` isn't a reliable check here, because it doesn't show the old `sdl2` install. Check where the library link points instead.

### The build fails

The script stops at the first failed step and prints `FAILED: <step>`. Homebrew's own build logs are in `~/Library/Logs/Homebrew/ffmpeg/`: `01.configure.log` and `02.make.log`. A compiler error in one codec (as `openapv` once had) usually means excluding that option.

### Decklink

DeckLink support is excluded by default and untested. It's only worth building if you have Blackmagic DeckLink hardware with the Desktop Video drivers installed. It also needs the DeckLink SDK, a manual download from Blackmagic, and it makes FFmpeg a "nonfree" build that can't be redistributed.

The tap's formula looks for the SDK's headers in Homebrew's own `include` folder (it passes `--extra-cflags=-I$(brew --prefix)/include`), not in the SDK's folder, and Homebrew doesn't pass compiler flags through from the environment. So, with the SDK downloaded and unpacked:

```bash
./ffmpeg_brew_update.sh --dry-run --decklink-sdk ~/Downloads/Blackmagic_DeckLink_SDK   # preview
./ffmpeg_brew_update.sh --decklink-sdk ~/Downloads/Blackmagic_DeckLink_SDK
```

The folder can be the SDK's top folder or its `Mac/include` folder; it must contain `DeckLinkAPI.h`. The script copies the headers into `$(brew --prefix)/include` just for the build, then removes the files it copied (also if the build fails or is interrupted), because `brew doctor` warns about headers Homebrew didn't install. `--include decklink` on its own is refused, because the build can't work without the headers.

## 📄 Logs

Every run except `--help` and `--exclusions` writes a full log, including Homebrew's output, to:

```
~/Library/Logs/ffmpeg_brew_update_<UTC date and time>.log
```

The path is printed at the start and end of the run, and with any failure. The newest 20 logs are kept; older ones are deleted. On a terminal the output is coloured; the log has the same text without the colour codes.

## 🛠 Requirements

- **macOS** on Apple Silicon or Intel.
- **[Homebrew](https://brew.sh)**, a version with `brew trust` (needed for third-party taps). The script finds it in `/opt/homebrew` or `/usr/local` even if it isn't on `PATH`.
- **Xcode Command Line Tools** (`xcode-select --install`), to compile FFmpeg. The script checks for them before a rebuild.
- **Time and disk space:** a rebuild takes a few minutes once dependencies are installed. The first build installs a large set of libraries.
