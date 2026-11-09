# Android release signing

Android accepts an in-place update only when its package ID and signing certificate match the installed app and its version code is newer. Keep the release keystore private and backed up securely. Never commit it, upload it as an artifact, or share it in chat.

The repository owner must generate or obtain a persistent release keystore **on their own machine**, save a secure backup, and configure these repository Actions secrets in GitHub Settings:

- `ANDROID_SIGNING_KEY_BASE64`: base64-encoded keystore file
- `ANDROID_KEYSTORE_PASSWORD`: keystore password
- `ANDROID_KEY_ALIAS`: signing key alias
- `ANDROID_KEY_PASSWORD`: key password

The workflow uses a temporary key for branch test builds when secrets are unavailable, but refuses to publish them. Publishing requires the persistent key and verifies its certificate against the latest published DownList release. If a key change is intentional, a repository owner can run the workflow on `main` with **allow_signing_migration** enabled. Do this only after notifying users that Android requires reinstalling across a signing-key change, which deletes local app data.

Older releases made with temporary keys cannot be updated in place with a new persistent key; their keys were not retained. Users of those releases need a one-time uninstall and install of the newly signed version, after saving any important settings. Once the persistent key is in use, future releases must keep using that same key and a higher version code.
