# FFmpeg Brew Update (macOS)

A script to build FFmpeg on macOS through Homebrew with almost every optional codec and feature switched on, check that the result actually works, and repair it when a Homebrew upgrade breaks it.

Homebrew's own `ffmpeg` is a ready-made build with a fixed set of features. The [`homebrew-ffmpeg/ffmpeg`](https://github.com/homebrew-ffmpeg/homebrew-ffmpeg) tap offers dozens of extra `--with-*` options instead, but then FFmpeg is compiled on your Mac. This script turns on every option except a documented list of exclusions, and looks after the problems a compiled build brings with it.

## 🚀 Quick start

```bash
chmod +x ffmpeg_brew_update.sh
./ffmpeg_brew_update.sh --help      # how to use it
./ffmpeg_brew_update.sh             # check FFmpeg; rebuild only if it's broken or missing
```

After any `brew upgrade`:

```bash
./ffmpeg_brew_update.sh --check     # is FFmpeg still working?
./ffmpeg_brew_update.sh --force     # if not, rebuild it
```

## 🧭 Options

| Command | What it does |
|---|---|
| `./ffmpeg_brew_update.sh` | Checks the installed FFmpeg. Rebuilds only if it's missing or fails the checks. |
| `--check` | Only runs the checks and changes nothing. Exits with `0` if FFmpeg is working and `1` if not, so it can be used in other scripts. |
| `--force` | Rebuilds even if FFmpeg is working: after a `brew upgrade`, or to pick up options newly added to the tap. |
| `--clean` | Like `--force`, but first force-uninstalls and reinstalls `chromaprint` and `zvbi`. Use it if the rebuild fails at the dependency step. |
| `--exclusions` | Lists every excluded option and why it's excluded, then asks Homebrew whether a library that broke the build has had a new release worth trying. |
| `--include <option>` | Used with `--force`: puts one excluded option back for this run only, to test whether it builds now. Can be repeated. Example: `--force --include openapv`. |
| `--require-encoders "<names>"` | The encoders FFmpeg must have, replacing the defaults. `none` checks none. See [Required features](#required-features). |
| `--require-decoders "<names>"` | The decoders FFmpeg must have. None are checked by default. |
| `--require-filters "<names>"` | The filters FFmpeg must have, replacing the defaults. `none` checks none. |
| `--help`, `-h` | Shows the usage summary. |

Options are checked when the script starts, so a misspelt option, an `--include` name that isn't in the exclusions list, or a feature name containing anything other than letters, digits and `_` is refused before anything changes.

## 📝 What a rebuild does

1. **Checks the current FFmpeg** (see [The checks](#-the-checks)). Without `--force`, it stops here if everything passes, and also if FFmpeg works but only a required feature is missing.
2. **Updates Homebrew** (`brew update`), trusts the `homebrew-ffmpeg/ffmpeg` tap (recent Homebrew versions require this for third-party taps) and taps it.
3. **Checks the exclusions** for any broken library that has a newer version since (see [Watching broken libraries](#-watching-broken-libraries)).
4. **Installs `chromaprint` and `zvbi`**, the latter from the `lescanauxdiscrets/tap` tap.
5. **Uninstalls the old FFmpeg**, without removing its dependencies.
6. **Chooses the options:** every `--with-*` option the tap offers, except those listed in `EXCLUSIONS`. It prints each option as `include` or `skip`, and warns if an excluded option no longer exists in the tap.
7. **Brings FFmpeg's dependencies up to date** before compiling:
   - upgrades every installed dependency that is out of date;
   - reinstalls any dependency Homebrew lists as installed whose files are missing.
8. **Builds FFmpeg** with the chosen options.
9. **Checks the new FFmpeg**, and reports failure if any check fails.

## ✅ The checks

A build that compiles can still be broken, so the script checks what matters in use:

- `ffmpeg` and `ffprobe` are installed and start.
- `ffplay` starts, if installed. It needs SDL, which the other tools don't use.
- `brew linkage --test ffmpeg` finds no broken or missing libraries. Its "Indirect dependencies with linkage" notice is shown but isn't a failure: it only means FFmpeg uses libraries it doesn't list as direct dependencies.
- A real round trip works: it generates a one-second tone, writes it as a WAV file and reads it back with `ffprobe`.
- The required encoders, decoders and filters are present (see below).

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

**A missing feature is treated differently from a broken FFmpeg.** If FFmpeg runs but a required feature is missing, the script reports it and exits with `1`, but doesn't start a rebuild: the name may be misspelt, or the feature may never have been part of this build. Check the names, and use `--force` if a rebuild should add the feature (for example after removing an option from `EXCLUSIONS`). If a required feature is still missing after a rebuild, the run fails with `ffmpeg built and works, but a required feature is missing`.

To see which option provides a feature, look for it in `ffmpeg -hide_banner -buildconf` or the tap's `brew options homebrew-ffmpeg/ffmpeg/ffmpeg`.

## 🚫 Exclusions

The options left out of the build are kept in one table, `EXCLUSIONS`, near the top of the script. Each line has seven fields separated by `|`:

```
option|formula|broken|ffmpeg|last good|since|reason
```

| Field | Meaning |
|---|---|
| `option` | The option name without `--with-`, e.g. `openapv`. It must match the tap's option name exactly. |
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
| `decklink` | Needs the Blackmagic DeckLink SDK installed by hand. Without it, configure stops with `ERROR: DeckLinkAPI.h not found`. |
| `libflite` | The tap's option doesn't install the flite library, so configure stops with `ERROR: libflite not found`. It may build after `brew install flite` (untested). |
| `openapv` | openapv 1.1.1.0 changed the arguments of `oapvm_create()`, so FFmpeg 9.0.1 fails to compile against it. The upgrade from 0.3.0.0 also broke the existing FFmpeg, which could no longer find `liboapv.3.dylib`. |

`game-music-emu`, `openvino`, `whisper-cpp` and `librsvg` used to be excluded too, with no reason recorded. Each was test-built on its own on 17 September 2026 with FFmpeg 9.0.1: all four built and passed the checks, so they are now included. `openvino` and `whisper-cpp` bring in large dependencies (OpenVINO, whisper.cpp, llama.cpp, ONNX, OpenBLAS). To leave either out, add it back to `EXCLUSIONS` with that as the reason.

Run `./ffmpeg_brew_update.sh --exclusions` for the full, current list.

### 🔭 Watching broken libraries

For an exclusion with `formula` filled in, `--exclusions` and every rebuild compare the versions Homebrew offers now with the ones recorded as broken:

- **Neither the library nor FFmpeg has a newer version:** it stays excluded.
- **Either has a newer version:** it reports `WORTH TRYING AGAIN` and gives the command to test it, e.g.
  ```bash
  ./ffmpeg_brew_update.sh --force --include openapv
  ```

If that build works, delete the line from `EXCLUSIONS`. If it fails, run `--force` without `--include` to go back to a working build, then update the `broken` and `ffmpeg` fields to the versions you just tried.

### Adding an exclusion

When a new option breaks the build, add a line to `EXCLUSIONS`. Fill in `formula`, `broken`, `ffmpeg` and `last good` when a library version is to blame, so the script can tell you when it's worth trying again. The last good version is in Homebrew's history for that formula, e.g. `https://github.com/Homebrew/homebrew-core/commits/master/Formula/o/openapv.rb`.

## 🩺 Troubleshooting

### `Library not loaded: …dylib` after a `brew upgrade`

This is the most common breakage. Because FFmpeg from this tap is compiled on your Mac, Homebrew doesn't rebuild it when one of its libraries gets a new version. FFmpeg then looks for a library file that no longer exists. Run `--check` to confirm, then `--force` to rebuild. If the same library keeps breaking FFmpeg, consider adding it to `EXCLUSIONS`.

### Libraries disappear when FFmpeg is uninstalled

By default, uninstalling FFmpeg makes Homebrew autoremove every library only FFmpeg used, then reinstall them moments later. That's slow, and an interrupted run can leave a library half-removed. The script sets `HOMEBREW_NO_AUTOREMOVE=1` to prevent this.

### `ffplay` fails with `libSDL2-2.0.0.dylib` not found

Homebrew has replaced `sdl2` with `sdl2-compat`, the SDL project's SDL2 compatibility layer built on SDL3. An old `sdl2` install left linked in `/opt/homebrew/lib` makes FFmpeg's build pick up a path that no longer exists. To fix it:

```bash
brew unlink sdl2                     # removes the old SDL2's links only
brew link --overwrite sdl2-compat
brew cleanup sdl2-compat             # deletes the old SDL2 install
ls -l /opt/homebrew/lib/libSDL2-2.0.0.dylib   # should point into Cellar/sdl2-compat
./ffmpeg_brew_update.sh --force
```

`brew list --versions sdl2-compat` isn't a reliable check here, because it doesn't show the old `sdl2` install. Check where the library link points instead.

### The build fails

The script stops at the first failed step and prints `FAILED: <step>`. Homebrew's own build logs are in `~/Library/Logs/Homebrew/ffmpeg/`: `01.configure.log` and `02.make.log`. A compiler error in one codec, such as the `openapv` one, usually means excluding that option.

### Decklink

Download and install the Blackmagic DeckLink SDK, then:

```bash
export HOMEBREW_EXTRA_CFLAGS="-I$HOME/Documents/Blackmagic-DeckLink-SDK-16.0/Mac/include"
export HOMEBREW_EXTRA_LDFLAGS="-L$HOME/Documents/Blackmagic-DeckLink-SDK-16.0/Mac/include"
./ffmpeg_brew_update.sh --force --include decklink
```

## 📄 Logs

Every run except `--help` and `--exclusions` writes a full log, including Homebrew's output, to:

```
~/Library/Logs/ffmpeg_brew_update_<UTC date and time>.log
```

The path is printed at the start and end of the run, and with any failure.

## 🛠 Requirements

- **macOS** on Apple Silicon or Intel.
- **[Homebrew](https://brew.sh)**, a version with `brew trust` (needed for third-party taps).
- **Time and disk space:** a rebuild takes a few minutes once dependencies are installed. The first build installs a large set of libraries.
