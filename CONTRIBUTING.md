# Contributing to YtToPdf

Thanks for your interest in improving YtToPdf. Bug reports, ideas and pull requests are all welcome.

## Getting set up

1. Follow the [installation steps](README.md#installation) to install Xcode 27, Homebrew and the
   command-line tools (`brew install yt-dlp ffmpeg whisper-cpp deno`).
2. Clone the repository and open `YtToPdf.xcodeproj`.
3. Run the app with ⌘R and the tests with ⌘U.

## Before opening a pull request

- **Build without warnings.** The project uses Swift 6 strict concurrency; please keep it warning-free.
- **Run the unit tests:**
  ```bash
  xcodebuild test -project YtToPdf.xcodeproj -scheme YtToPdf -destination 'platform=macOS'
  ```
- **If you touched the YouTube, caption or Whisper pipeline, run the live tests too:**
  ```bash
  TEST_RUNNER_YTTOPDF_NETWORK_TESTS=1 xcodebuild test -project YtToPdf.xcodeproj -scheme YtToPdf -destination 'platform=macOS'
  ```
- **If you changed the PDF or the Speech Fingerprint,** render samples with
  `TEST_RUNNER_YTTOPDF_RENDER_DIR=/tmp/ytpdf-renders` and look at them.
- Add or update tests for the behaviour you changed. Test fixtures must be synthetic: please don't
  commit real transcripts or caption files from YouTube videos.

## Code style

- Follow the structure in [README › Project structure](README.md#project-structure): models are value
  types, services have no UI, views stay small and focused.
- No force unwraps in the pipeline; errors are typed (`YouTubeError`, `WhisperError`, `PipelineError`, …)
  and carry a user-facing description and, where possible, a fix.
- Long-running or CPU-heavy work runs off the main actor (`@concurrent`), and external tools always go
  through `ProcessRunner` so they can be cancelled.
- Liquid Glass is for controls and navigation only; content sits on opaque surfaces.
- Match the surrounding code's naming and comment style. Comments explain *why*, not *what*.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add Markdown export
fix(captions): keep genuine word repetition when deduplicating
docs: explain the Speech Fingerprint
```

Common types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`, `chore`.

## Reporting bugs

Open an issue using the **Bug report** template. Include your macOS version, the output of
`yt-dlp --version`, the steps to reproduce and, if possible, a link to a public video that shows the problem.

## Licence

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
