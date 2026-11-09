# DownList server — Hugging Face Docker Space

Copy `app.py`, `Dockerfile`, and `requirements.txt` to the root of your Docker Space. Keep your Space README's YAML metadata (`sdk: docker` and `app_port: 7860`) intact. Rebuild the Space, then enter its URL manually in DownList Settings. No server URL is preconfigured in the app.

The server provides URL downloads, device uploads, status, delete, rename, cancel, ZIP listing/extraction, media information for supported formats, HTTP byte-range streaming, and URL-to-GoFile transfers. GoFile upload returns its share page (`gofile_url`); it depends on the external GoFile service and direct access to the source URL. Set the optional Space secret `GOFILE_TOKEN` if your GoFile account requires it. Anonymous uploads are subject to GoFile's own rules and retention policies.

## Limits and security

- **This server has no authentication.** Anyone who can reach the Space can download, delete, rename, cancel, and consume its resources. Use a private Space with an appropriate access layer; do not expose it to untrusted users or store sensitive files. The Android app does not currently send a Hugging Face token.
- Direct URLs and redirects are checked for private addresses, but DNS rebinding and network-level risks are not fully mitigated. Use network egress restrictions in addition to application checks. Do not set `ALLOW_PRIVATE_URLS=1` in production.
- `DATA_DIR` defaults to `/data`. On free Spaces this is **ephemeral**: files and task history can disappear after a restart, rebuild, or migration. State recovery only works when the data directory survives. Interrupted tasks are marked as failed, not resumed. Files and task history expire after 24 hours by default (`FILE_RETENTION_SECONDS`). A GoFile link stored only in history is also lost if that history expires; copy it elsewhere.
- `MAX_TOTAL_STORAGE` defaults to 45 GiB and `DISK_MARGIN` to 1 GiB. Quota checks are best effort, not a hard reservation; simultaneous transfers and multipart temporary files can exceed the limit. Leave extra headroom and limit concurrency. HF limits and available disk can vary.
- Media inspection currently covers MP4/MOV/M4V duration and dimensions, and PNG/JPEG/GIF dimensions when available; other formats may report unavailable. It is not a full media probe.
- Cancellation is cooperative; a blocked network operation may take time to stop. Retrying an upload after a network failure can create duplicate files on GoFile if the remote upload succeeded but its response was lost.
