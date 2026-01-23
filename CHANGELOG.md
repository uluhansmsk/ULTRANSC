# ULTRANSC Changelog

## v0.5 Stable (2026-01-23)

Fixed broken v0.5.0 release. Reverted to stable v0.3.3 codebase with minimal improvements.

**Changes:**

- Restored working two-stage adaptive audio processing
- Added optional config file support (config/default.conf)
- Added segments.json output for keyword extraction tools
- Fixed environment check crashes
- Removed overcomplicated features that didn't work

## v0.5.0 (2026-01-07) - BROKEN

Attempted "intelligent pipeline" with chunking, crash recovery, and memory management.
Multiple bugs made it unusable. Do not use this version.

## v0.3.3b (2025-12-XX)

Stable release with adaptive speech boost.

**Features:**

- Two-stage audio processing with blank detection
- Automatic gain adjustment based on mean volume
- Queue system (incoming, processing, done)
- Model auto-selection based on RAM
- Local yt-dlp download
- Up to 3-hour file support

## v0.3.x - v0.1

Early development versions.
