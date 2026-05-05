# Decklink requires you to download and install decklinkSDK from Blackmagic as it just doesn't work, but even then - I can't get it to work.

#tidying up by forcefully uninstalling stuff…
brew uninstall --force --ignore-dependencies ffmpeg
brew uninstall --force chromaprint amiaopensource/amiaos/decklinksdk
brew uninstall zvbi
#Do some installs for dependencies…
brew install chromaprint 
#Since I can't get decklinksdk to include properly, I've commented this line out…
#brew install amiaopensource/amiaos/decklinksdk
brew tap lescanauxdiscrets/tap && brew install lescanauxdiscrets/tap/zvbi
#Oddly I have a double attempt to install chromaprint, just in case…
brew install chromaprint
#Now forcefully uninstall ffmpeg but ignore dependencies (so it doesn't uninstall things we need later)…
brew uninstall --force --ignore-dependencies ffmpeg
#Tap the ffmpeg in case we haven't got that already…
brew tap homebrew-ffmpeg/ffmpeg

#For Decklink, we apparently need these two environment variables, and then the decklink install is on line 22 - but line 24 is currently our main FFMPEG install without decklink support.
#HOMEBREW_EXTRA_CFLAGS="-I$HOME/Documents/Blackmagic-DeckLink-SDK-16.0/Mac/include"
#HOMEBREW_EXTRA_LDFLAGS="-L$HOME/Documents/Blackmagic-DeckLink-SDK-16.0/Mac/include"
#brew install homebrew-ffmpeg/ffmpeg/ffmpeg $(brew options homebrew-ffmpeg/ffmpeg/ffmpeg | grep -vE '\s' | grep -- '--with-' | grep -vi chromaprint | grep -vi alt-name | grep -vi game-music-emu | grep -vi openvino | grep -vi whisper | grep -vi librsvg | grep -vi libflite | tr '\n' ' ')

brew install homebrew-ffmpeg/ffmpeg/ffmpeg $(brew options homebrew-ffmpeg/ffmpeg/ffmpeg | grep -vE '\s' | grep -- '--with-' | grep -vi chromaprint | grep -vi alt-name | grep -vi game-music-emu | grep -vi decklink | grep -vi openvino | grep -vi whisper | grep -vi librsvg | grep -vi libflite | tr '\n' ' ')

