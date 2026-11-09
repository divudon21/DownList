# AI Agent Downloader

Material 3 Flutter Android client for remote server downloads, multi-file streaming uploads, live task monitoring, and external media player streaming.

## Features

- **Manual Server Configuration (`Settings`)** — Enter and save your own server URL on-device via `SharedPreferences` (no default or hardcoded server URL).
- **Remote Downloads (`Home`)** — Paste any file URL and start server-side downloads via `POST /start_download`.
- **Multi-File Streaming Uploads (`Upload`)** — Select one or multiple files simultaneously, view file sizes, live upload speed, uploaded/total bytes, ETA, and cancel individual or all active uploads at any time (`POST /upload`).
- **Live Task Tracking (`Task`)** — Real-time monitoring of both active server downloads (`GET /history` & `GET /status/{id}`) and active file uploads.
- **History & Direct Video Player Streaming (`History`)** — Browse completed & failed items, copy download links, inspect file metadata, and launch streams (`GET /stream/{id}`) directly in installed Android video/media players instead of the browser.
- **Automated Signed APK Releases (`.github/workflows/android-apk.yml`)** — Builds signed `arm64-v8a`, `armeabi-v7a`, `x86_64`, and `universal` APKs via GitHub Actions and publishes them to GitHub Releases.
