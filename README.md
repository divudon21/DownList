# DownList

DownList is a Flutter Android app for managing downloads and uploads on your own compatible server.

## Features

- Start remote downloads and URL-to-GoFile transfers.
- Upload files from your device and follow live task progress.
- Browse history and stream media in an installed player.
- Configure notifications, server connection, and app update preferences.

## Getting started

1. Download an APK from [Releases](https://github.com/divudon21/DownList/releases).
2. Install it on your Android device.
3. Open **Settings → Server** and enter your own server URL.

A compatible server is required; no server address is preconfigured. Changing the Android package name installs this version as a separate app, so previous local settings are not transferred.

## Development

Install Flutter and the Android SDK, then run:

```sh
flutter pub get
flutter test
flutter run
```

Release APKs must use the same Android signing key to update an existing installation. The release workflow supports a persistent key through GitHub Actions secrets; temporary-key builds require reinstalling if their signatures differ.
