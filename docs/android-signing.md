# Android release signing

Android accepts an in-place update only when the package ID and signing certificate match the installed app and the version code is newer. The release keystore must remain private and have a secure backup. Never commit it, upload it as a workflow artifact, or send it in chat.

## One-time setup by the repository owner

1. On your own computer, install a JDK and generate a key **outside the repository**. For example:

   ```sh
   keytool -genkeypair -v -keystore "$HOME/downlist-release.jks" -alias downlist -keyalg RSA -keysize 4096 -validity 10000
   ```

   Enter the requested passwords and certificate information locally. Securely back up the keystore and passwords; losing them prevents signing future in-place updates.

2. In GitHub, open **DownList → Settings → Secrets and variables → Actions → New repository secret**. Add the following secrets. Do not send their values in chat:

   - `ANDROID_SIGNING_KEY_BASE64`: the entire base64-encoded keystore. On your computer, `python3 -c 'import base64,pathlib; print(base64.b64encode((pathlib.Path.home()/"downlist-release.jks").read_bytes()).decode())'` prints the value to copy directly into GitHub. Keep your terminal private.
   - `ANDROID_KEYSTORE_PASSWORD`: the password set for the keystore.
   - `ANDROID_KEY_ALIAS`: the key alias (`downlist` if using the example above).
   - `ANDROID_KEY_PASSWORD`: the key password (often the same as the keystore password).

3. After the release changes are on `main`, open **Actions → Build APKs & Create Release → Run workflow**, select `main`, and enable **allow_signing_migration** only for the first deliberate switch to the new key. The workflow checks the installed package metadata and release signer before publishing.

## Important migration limitation

Older releases made with temporary keys cannot be updated in place with a new persistent key; those old keys were not retained. Users of those releases need a **one-time uninstall and install** of the newly signed version, after saving important settings. Uninstalling removes local app data. Once the persistent key is in use, future releases must keep using that same key and a higher version code.

Branch test builds may use a temporary key when secrets are unavailable, but publishing refuses temporary keys and refuses unexpected signing changes unless an owner explicitly approves the one-time migration.
