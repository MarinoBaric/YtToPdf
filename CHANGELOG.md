# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-10-15

### Added
- Transcripts from YouTube links in every common form (watch, youtu.be, shorts, live, embed).
- Caption pipeline that prefers manual captions, falls back to automatic ones, removes rolling-caption
  repeats and annotations, and builds punctuated sentences and paragraphs with word-level timing.
- Local transcription with whisper.cpp for videos without captions, with verified model downloads
  (Base, Small, Medium), FFmpeg audio conversion and step-by-step progress.
- Main window with Liquid Glass controls: link field with clipboard detection, video card, options,
  progress, cancellation, transcript preview with search, Copy All and word count.
- History sidebar backed by SwiftData: search by title, channel or text, reopen offline, delete with undo.
- The Speech Fingerprint: a deterministic, per-video pattern of speech density.
- Editorial A4 PDF export with embedded Inter, running headers and footers, page numbers,
  a "you are here" fingerprint on every page and clickable timestamps, plus a PDFKit preview.
- Plain text, Markdown and SRT exports.
- Settings: default options, PDF accent colour (automatic from the thumbnail or custom), logo upload,
  Whisper model management.
- Setup screen with exact install commands when yt-dlp, FFmpeg or whisper.cpp is missing.
- Clear, typed error handling for invalid links, private, age-restricted and members-only videos,
  network problems, outdated yt-dlp and refused downloads (retried automatically).
- App icon, build-and-install script, unit tests and opt-in live YouTube tests.

[Unreleased]: https://github.com/MarinoBaric/YtToPdf/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/MarinoBaric/YtToPdf/releases/tag/v1.0.0
