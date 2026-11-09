# Ok-AI & AI Agent Downloader

This repository contains:
1. **Ok-AI Backend (`app.py`, `Dockerfile`, `requirements.txt`)** — FastAPI AI agent backend server.
2. **AI Agent Downloader (`lib/`, `android/`, `pubspec.yaml`)** — Material 3 Flutter Android client app for downloading, streaming, and tracking server tasks with a configurable server URL.
3. **Automated Android APK Release Workflow (`.github/workflows/android-apk.yml`)** — Builds signed release APKs (`arm64-v8a`, `armeabi-v7a`, `x86_64`, and `universal`) via GitHub Actions and publishes them directly to **GitHub Releases**.

## App Screens (Material 3)

| Tab | Description |
|-----|-------------|
| **Home** | Submit any file URL to start a server-side download (`POST /start_download`) |
| **Task** | Live progress, speed, downloaded/total bytes, and ETA for active downloads (`GET /status/{id}`) |
| **History** | Completed & failed downloads with file info, link copy, external player streaming, and status badges |
| **Upload** | Placeholder screen |
| **Settings** | Configure & persist custom server URL on-device via `SharedPreferences` |
