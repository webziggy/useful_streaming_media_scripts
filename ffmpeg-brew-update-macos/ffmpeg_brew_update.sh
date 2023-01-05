brew uninstall --force --ignore-dependencies ffmpeg
brew uninstall --force chromaprint amiaopensource/amiaos/decklinksdk
#brew install chromaprint amiaopensource/amiaos/decklinksdk
brew uninstall zvbi
brew tap lescanauxdiscrets/tap && brew install lescanauxdiscrets/tap/zvbi
brew install chromaprint
brew uninstall --force --ignore-dependencies ffmpeg
brew tap homebrew-ffmpeg/ffmpeg
brew install homebrew-ffmpeg/ffmpeg/ffmpeg $(brew options homebrew-ffmpeg/ffmpeg/ffmpeg | grep -vE '\s' | grep -- '--with-' | grep -vi chromaprint | grep -vi game-music-emu | grep -vi decklink | grep -vi librsvg | tr '\n' ' ')
