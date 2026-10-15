# Third-Party Notices

## Bundled with the app

### Inter typeface

- Files: `YtToPdf/Resources/Fonts/Inter-*.ttf`, `InterDisplay-*.ttf`
- Copyright (c) 2016 The Inter Project Authors (https://github.com/rsms/inter)
- Licence: SIL Open Font License, Version 1.1. The full licence is in
  [`YtToPdf/Resources/Fonts/Inter-OFL.txt`](YtToPdf/Resources/Fonts/Inter-OFL.txt).

Inter is embedded (subset) in exported PDFs, as the Open Font License permits.

## Used at runtime, not bundled

YtToPdf runs these tools from your own Homebrew installation. They are not distributed with this
repository or the app.

| Component | Purpose | Licence |
|---|---|---|
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | Video info, captions, audio | The Unlicense |
| [FFmpeg](https://ffmpeg.org) | Audio conversion | LGPL 2.1+ (GPL for some builds) |
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp) | Local speech recognition | MIT |
| [Whisper models](https://huggingface.co/ggerganov/whisper.cpp) | Speech recognition weights, downloaded on first use | MIT (OpenAI) |
| [Deno](https://deno.com) *(optional)* | JavaScript runtime used by yt-dlp | MIT |
