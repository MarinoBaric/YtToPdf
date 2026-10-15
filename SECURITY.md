# Security Policy

## Supported versions

Only the latest release of YtToPdf receives fixes.

## Reporting a vulnerability

Please don't open a public issue for security problems. Instead, use GitHub's
[private vulnerability reporting](https://github.com/MarinoBaric/YtToPdf/security/advisories/new)
for this repository, with a description, steps to reproduce and the impact you expect.

You can expect an acknowledgement within a week. Fixes are released as soon as practical and
credited to you unless you'd rather stay anonymous.

## Scope

YtToPdf runs yt-dlp, FFmpeg and whisper.cpp from your Homebrew installation. Vulnerabilities in those
tools should be reported to their own projects; keep them up to date with `brew upgrade`.
