# YtToPdf

A native macOS app that turns YouTube videos into clean, timestamped transcripts and well-designed PDFs.
Everything runs locally: captions come from YouTube via yt-dlp, and videos without captions are
transcribed on-device with whisper.cpp.

## Status

Early development.

## Requirements

- macOS 27 and Xcode 27
- `brew install yt-dlp ffmpeg whisper-cpp`

## License

MIT, see [LICENSE](LICENSE).
