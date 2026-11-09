# DownList

Material 3 Flutter Android client for remote server downloads, multi-file streaming uploads, live task monitoring, and external media player streaming.

## Features

- **Manual Server Configuration (`Settings`)** — Enter and save your own server URL on-device via `SharedPreferences` (nothing hardcoded).
- **Remote Downloads (`Home`)** — Paste any file URL and start server-side downloads via `POST /start_download`.
- **Multi-File Streaming Uploads (`Upload`)** — Select single or multiple files simultaneously, view file sizes, live upload speed, uploaded/total bytes, ETA, and cancel individual or all active uploads (`POST /upload`).
- **Live Task Tracking (`Task`)** — Real-time monitoring of both active server downloads (`GET /history` & `GET /status/{id}`) and active file uploads.
- **Full Installed Video Player Chooser (`History` / `Upload`)** — Discovers all installed Android video/media players on the device (with real app icons and browser filtering) and launches streams (`GET /stream/{id}`) directly in your chosen player.
- **Black & White Liquid Glass Adaptive Icon** — Crisp monochrome Liquid Glass launcher icon across adaptive (`anydpi-v26`), themed monochrome (`drawable/ic_launcher_monochrome`), and legacy mipmap densities.
- **Automated Signed APK Releases (`.github/workflows/android-apk.yml`)** — Builds signed `arm64-v8a`, `armeabi-v7a`, `x86_64`, and `universal` APKs via GitHub Actions and publishes them to GitHub Releases.
