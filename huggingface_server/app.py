"""
DownList Server — Production FastAPI Backend for Hugging Face Docker Spaces
===========================================================================
Drop-in replacement for app.py on Hugging Face Spaces (CPU Basic / 16 GB RAM /
50 GB ephemeral storage).

Key Engineering Guarantees:
1. Hugging Face Quota Safety: Enforces a 45 GiB storage budget (configurable via
   MAX_TOTAL_STORAGE) across downloads, uploads, and ZIP extractions so the
   container never crosses Hugging Face's 50 GB eviction threshold.
2. Low Memory Footprint: Uses 4 MB streaming buffers and drops Linux page cache
   every 256 MB via posix_fadvise(POSIX_FADV_DONTNEED) to avoid cgroup OOM kills.
3. True Container Telemetry: Reads Linux cgroup v1/v2 memory and CPU limits
   before falling back to /proc/meminfo so /server_status reports accurate
   container RAM, storage quota, CPU cores, active tasks, and uptime.
4. Full File Lifecycle: Supports parallel HTTP Range downloads, streaming
   uploads, RFC 7233 media streaming (GET + HEAD + suffix ranges), single-file
   delete, delete-all, active task cancellation, file rename, ZIP inspection &
   safe extraction, lightweight media resolution/duration probing, and streaming
   URL-to-GoFile transfers with live upload progress.
"""

from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
import gc
import http.client
import ipaddress
import json
import mimetypes
import os
import re
import shutil
import socket
import ssl
import struct
import threading
import time
import urllib.parse
import uuid
import zipfile
from typing import Any, Dict, List, Optional, Tuple

import urllib3
from urllib3.util import Timeout
from fastapi import BackgroundTasks, FastAPI, File, HTTPException, Request, Response, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse, StreamingResponse
from pydantic import BaseModel

SERVER_VERSION = "2.0.0"
SERVER_START_TIME = time.time()


def _resolve_data_dir() -> str:
    preferred = os.environ.get("DATA_DIR", "/data")
    try:
        os.makedirs(preferred, exist_ok=True)
        probe = os.path.join(preferred, ".write_test")
        with open(probe, "w", encoding="utf-8") as f:
            f.write("ok")
        os.remove(probe)
        return preferred
    except Exception:
        fallback = "/tmp/downlist_data"
        os.makedirs(fallback, exist_ok=True)
        return fallback


DATA_DIR = _resolve_data_dir()
STATE_FILE = os.path.join(DATA_DIR, ".tasks_state.json")

# Hugging Face free Docker Spaces enforce a strict 50 GB ephemeral rootfs cap.
MAX_TOTAL_STORAGE = int(os.environ.get("MAX_TOTAL_STORAGE", 45 * 1024 ** 3))
DISK_SAFETY_MARGIN = int(os.environ.get("DISK_MARGIN", 1 * 1024 ** 3))
FILE_RETENTION_SECONDS = int(os.environ.get("FILE_RETENTION_SECONDS", 86400))
ALLOW_PRIVATE_URLS = os.environ.get("ALLOW_PRIVATE_URLS", "0") == "1"
GOFILE_API_TOKEN = os.environ.get("GOFILE_TOKEN", "").strip()

FLUSH_EVERY = 256 * 1024 * 1024
CHUNK_SIZE = 4 * 1024 * 1024
GOFILE_CHUNK_SIZE = 1 * 1024 * 1024
CONNECT_TIMEOUT = 30
READ_TIMEOUT = 180
MAX_ATTEMPTS = 5
SEGMENTS = 8
MIN_SIZE_FOR_PARALLEL = 32 * 1024 * 1024

DEFAULT_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
    ),
    "Accept": "*/*",
}

urllib3.disable_warnings()
_http = urllib3.PoolManager(
    maxsize=32,
    block=True,
    headers=DEFAULT_HEADERS,
)

tasks: Dict[str, Dict[str, Any]] = {}
_tasks_lock = threading.RLock()
_save_lock = threading.Lock()


# ---------------------------------------------------------------------------
# Request Models
# ---------------------------------------------------------------------------

class DownloadRequest(BaseModel):
    url: str


class RenameRequest(BaseModel):
    new_name: str


# ---------------------------------------------------------------------------
# Utility Helpers
# ---------------------------------------------------------------------------

def format_bytes(num_bytes: int) -> str:
    if num_bytes <= 0:
        return "0 B"
    units = ["B", "KB", "MB", "GB", "TB"]
    value = float(num_bytes)
    idx = 0
    while value >= 1024.0 and idx < len(units) - 1:
        value /= 1024.0
        idx += 1
    return f"{value:.2f} {units[idx]}" if idx >= 2 else f"{value:.1f} {units[idx]}"


def sanitize_filename(raw_name: Optional[str], fallback: str = "downloaded_file.bin") -> str:
    if not raw_name:
        return fallback
    decoded = urllib.parse.unquote(raw_name).strip()
    decoded = decoded.replace("\\", "/").split("/")[-1]
    decoded = re.sub(r"[\x00-\x1f\x7f]+", "", decoded)
    decoded = re.sub(r'[<>:"|?*]+', "_", decoded).strip(" .")
    if not decoded or decoded in {".", ".."}:
        return fallback

    stem, dot, ext = decoded.rpartition(".")
    if not dot:
        stem, ext = decoded, ""
    else:
        ext = f".{ext[:20]}"

    # Keep UTF-8 encoded filename well below Linux 255-byte limit (including "{uuid}_" prefix).
    max_stem_bytes = 160
    encoded_stem = stem.encode("utf-8", errors="ignore")
    if len(encoded_stem) > max_stem_bytes:
        stem = encoded_stem[:max_stem_bytes].decode("utf-8", errors="ignore").rstrip(" ._-")
    if not stem:
        stem = "file"
    return f"{stem}{ext}"


def clean_filename_from_url(url: str) -> str:
    try:
        parsed = urllib.parse.urlsplit(url)
        tail = parsed.path.rsplit("/", 1)[-1]
        if tail and "." in tail:
            return sanitize_filename(tail, fallback="downloaded_file.bin")
    except Exception:
        pass
    return "downloaded_file.bin"


def filename_from_content_disposition(cd: Optional[str]) -> Optional[str]:
    if not cd:
        return None
    # RFC 5987 filename*=UTF-8''...
    star_match = re.search(r"filename\*\s*=\s*(?:UTF-8''|utf-8'')([^;\r\n]+)", cd)
    if star_match:
        candidate = star_match.group(1).strip().strip('"')
        return sanitize_filename(candidate)
    quoted = re.search(r'filename\s*=\s*"([^"]+)"', cd, flags=re.IGNORECASE)
    if quoted:
        return sanitize_filename(quoted.group(1))
    plain = re.search(r"filename\s*=\s*([^;\r\n]+)", cd, flags=re.IGNORECASE)
    if plain:
        return sanitize_filename(plain.group(1).strip().strip("'\""))
    return None


def guess_media_type(filename: str) -> str:
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    explicit = {
        "mp4": "video/mp4",
        "m4v": "video/mp4",
        "mkv": "video/x-matroska",
        "webm": "video/webm",
        "mov": "video/quicktime",
        "avi": "video/x-msvideo",
        "flv": "video/x-flv",
        "ts": "video/mp2t",
        "m2ts": "video/mp2t",
        "3gp": "video/3gpp",
        "mp3": "audio/mpeg",
        "m4a": "audio/mp4",
        "aac": "audio/aac",
        "flac": "audio/flac",
        "ogg": "audio/ogg",
        "opus": "audio/ogg",
        "wav": "audio/wav",
        "zip": "application/zip",
        "pdf": "application/pdf",
    }
    if ext in explicit:
        return explicit[ext]
    guessed, _ = mimetypes.guess_type(filename)
    return guessed or "application/octet-stream"


def validate_remote_url(raw_url: str) -> str:
    url = (raw_url or "").strip()
    if not url:
        raise ValueError("Please provide a valid file URL.")
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme.lower() not in {"http", "https"}:
        raise ValueError("Invalid URL scheme. Only http:// and https:// links are supported.")
    if not parsed.hostname:
        raise ValueError("Invalid URL: missing hostname.")

    if not ALLOW_PRIVATE_URLS:
        host = parsed.hostname.lower()
        if host in {"localhost", "0.0.0.0"} or host.endswith(".local") or host.endswith(".internal"):
            raise ValueError("Downloads from local or internal network addresses are not permitted.")
        try:
            infos = socket.getaddrinfo(parsed.hostname, None)
            for info in infos:
                ip_str = info[4][0]
                ip_obj = ipaddress.ip_address(ip_str)
                if (
                    ip_obj.is_loopback
                    or ip_obj.is_private
                    or ip_obj.is_link_local
                    or ip_obj.is_multicast
                    or ip_obj.is_reserved
                ):
                    raise ValueError(
                        "Downloads from private or reserved IP addresses are not permitted."
                    )
        except socket.gaierror as exc:
            raise ValueError(
                f"Could not resolve server hostname '{parsed.hostname}'. Please check the URL."
            ) from exc

    return url


def remote_request(method: str, url: str, **kwargs):
    """Follow redirects only after validating each destination."""
    for _ in range(6):
        validate_remote_url(url)
        response = _http.request(method, url, redirect=False, **kwargs)
        if response.status not in (301, 302, 303, 307, 308):
            return response
        location = response.headers.get("Location")
        response.close()
        response.release_conn()
        if not location:
            raise RuntimeError("Remote server returned a redirect without a destination.")
        url = urllib.parse.urljoin(url, location)
    raise RuntimeError("Remote server returned too many redirects.")


def format_http_status_error(status: int) -> str:
    if status in (401, 403):
        return (
            f"Access denied by the remote server (HTTP {status}). "
            "Please provide a direct, publicly accessible download URL."
        )
    if status == 404:
        return "The requested file was not found on the remote server (HTTP 404)."
    if status == 410:
        return "This download link has expired and is no longer available (HTTP 410)."
    if status == 429:
        return "The remote server rate-limited this request (HTTP 429). Please try again later."
    if status >= 500:
        return f"The remote server encountered an internal error (HTTP {status}). Please try again later."
    return f"The remote server rejected the request with HTTP status {status}."


def drop_page_cache(fd: int) -> None:
    try:
        os.fsync(fd)
        if hasattr(os, "posix_fadvise") and hasattr(os, "POSIX_FADV_DONTNEED"):
            os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_DONTNEED)
    except Exception:
        pass


def calculate_storage_bytes(root: str = DATA_DIR) -> int:
    total_bytes = 0
    try:
        for dirpath, _, filenames in os.walk(root):
            for fname in filenames:
                if fname.startswith(".tasks_state.json") or fname == ".write_test":
                    continue
                fpath = os.path.join(dirpath, fname)
                try:
                    if not os.path.islink(fpath):
                        total_bytes += os.path.getsize(fpath)
                except OSError:
                    pass
    except OSError:
        pass
    return total_bytes


def check_storage_quota(required_bytes: int) -> None:
    if required_bytes <= 0:
        return
    used_bytes = calculate_storage_bytes(DATA_DIR)
    available_budget = max(0, MAX_TOTAL_STORAGE - used_bytes)
    if required_bytes > available_budget:
        raise RuntimeError(
            f"Insufficient server storage quota: this file requires {format_bytes(required_bytes)}, "
            f"but only {format_bytes(available_budget)} of the {format_bytes(MAX_TOTAL_STORAGE)} "
            f"server storage limit is currently free. Delete older files from History and try again."
        )
    try:
        free_disk = shutil.disk_usage(DATA_DIR).free
        if free_disk < required_bytes + DISK_SAFETY_MARGIN:
            raise RuntimeError(
                f"Insufficient disk space on server: requires {format_bytes(required_bytes)}, "
                f"available {format_bytes(max(0, free_disk - DISK_SAFETY_MARGIN))}."
            )
    except RuntimeError:
        raise
    except Exception:
        pass


def remove_task_artifacts(task_id: str, file_path: Optional[str] = None, extract_path: Optional[str] = None) -> None:
    candidates = []
    if file_path:
        candidates.append(file_path)
    if extract_path:
        candidates.append(extract_path)
    candidates.append(os.path.join(DATA_DIR, f"extracted_{task_id}"))

    for path in candidates:
        if not path:
            continue
        try:
            if os.path.isfile(path) or os.path.islink(path):
                os.remove(path)
            elif os.path.isdir(path):
                shutil.rmtree(path, ignore_errors=True)
        except OSError:
            pass


def public_task_dict(task: Dict[str, Any]) -> Dict[str, Any]:
    return {k: v for k, v in task.items() if not k.startswith("_")}


def save_state() -> None:
    with _save_lock:
        try:
            with _tasks_lock:
                snapshot = {
                    tid: public_task_dict(tval)
                    for tid, tval in tasks.items()
                }
            tmp_path = f"{STATE_FILE}.{uuid.uuid4().hex}.tmp"
            with open(tmp_path, "w", encoding="utf-8") as f:
                json.dump(snapshot, f)
            os.replace(tmp_path, STATE_FILE)
        except Exception:
            pass


def load_state_on_startup() -> None:
    loaded: Dict[str, Any] = {}
    if os.path.isfile(STATE_FILE):
        try:
            with open(STATE_FILE, "r", encoding="utf-8") as f:
                raw = json.load(f)
                if isinstance(raw, dict):
                    loaded = raw
        except Exception:
            loaded = {}

    active_states = {"downloading", "uploading_to_gofile", "extracting", "queued", "pending"}
    with _tasks_lock:
        tasks.clear()
        for tid, tdata in loaded.items():
            if not isinstance(tdata, dict):
                continue
            status = str(tdata.get("status", "")).lower()
            fpath = tdata.get("file_path")
            if status in active_states:
                remove_task_artifacts(tid, fpath, tdata.get("extract_path"))
                tdata["status"] = "error"
                tdata["speed"] = 0.0
                tdata["error"] = (
                    "The transfer was interrupted because the server restarted. Please start it again."
                )
            elif status in {"completed", "extracted"}:
                has_gofile = bool(tdata.get("gofile_url"))
                if not has_gofile and fpath and not os.path.isfile(fpath):
                    # Ephemeral file was wiped by container rebuild; skip stale entry
                    continue
            tasks[tid] = tdata
    save_state()


# ---------------------------------------------------------------------------
# Pure-Python Lightweight Media Metadata Inspector (<64 KB read, zero deps)
# ---------------------------------------------------------------------------

def _parse_mp4_metadata(file_path: str, file_size: int) -> Dict[str, Any]:
    info: Dict[str, Any] = {}
    with open(file_path, "rb") as f:
        def scan_boxes(start: int, end: int, depth: int = 0) -> None:
            if depth > 6:
                return
            pos = start
            containers = {b"moov", b"trak", b"mdia", b"minf", b"stbl"}
            while pos + 8 <= end:
                f.seek(pos)
                hdr = f.read(16)
                if len(hdr) < 8:
                    break
                size, box_type = struct.unpack(">I4s", hdr[:8])
                header_len = 8
                if size == 1:
                    if len(hdr) < 16:
                        break
                    size = struct.unpack(">Q", hdr[8:16])[0]
                    header_len = 16
                elif size == 0:
                    size = end - pos
                if size < header_len or pos + size > end:
                    break

                if box_type == b"mvhd":
                    f.seek(pos + header_len)
                    mvhd = f.read(32)
                    if len(mvhd) >= 24:
                        version = mvhd[0]
                        if version == 1 and len(mvhd) >= 32:
                            timescale, duration = struct.unpack(">IQ", mvhd[20:32])
                        else:
                            timescale, duration = struct.unpack(">II", mvhd[12:20])
                        if timescale > 0 and duration > 0:
                            info["duration_seconds"] = round(duration / timescale, 1)
                elif box_type == b"tkhd":
                    f.seek(pos + header_len)
                    tkhd = f.read(96)
                    if len(tkhd) >= 84:
                        version = tkhd[0]
                        offset = 88 if version == 1 else 76
                        if len(tkhd) >= offset + 8:
                            w_fixed, h_fixed = struct.unpack(">II", tkhd[offset:offset + 8])
                            w, h = w_fixed >> 16, h_fixed >> 16
                            if w > 0 and h > 0 and w > info.get("width", 0):
                                info["width"] = w
                                info["height"] = h
                elif box_type in containers:
                    scan_boxes(pos + header_len, pos + size, depth + 1)

                if "width" in info and "duration_seconds" in info:
                    return
                pos += size

        scan_boxes(0, file_size, 0)
    return info


def _parse_image_dimensions(file_path: str) -> Dict[str, Any]:
    with open(file_path, "rb") as f:
        head = f.read(64)
        if len(head) >= 24 and head.startswith(b"\x89PNG\r\n\x1a\n") and head[12:16] == b"IHDR":
            w, h = struct.unpack(">II", head[16:24])
            return {"width": w, "height": h}
        if len(head) >= 10 and head[:6] in (b"GIF87a", b"GIF89a"):
            w, h = struct.unpack("<HH", head[6:10])
            return {"width": w, "height": h}
        if head.startswith(b"\xff\xd8"):
            f.seek(2)
            for _ in range(256):
                marker_prefix = f.read(1)
                if not marker_prefix:
                    break
                if marker_prefix != b"\xff":
                    continue
                marker = f.read(1)
                while marker == b"\xff":
                    marker = f.read(1)
                if not marker:
                    break
                m = marker[0]
                if m in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                    seg = f.read(7)
                    if len(seg) == 7:
                        h, w = struct.unpack(">HH", seg[3:7])
                        return {"width": w, "height": h}
                    break
                if m in (0xD8, 0xD9) or 0xD0 <= m <= 0xD7:
                    continue
                len_bytes = f.read(2)
                if len(len_bytes) < 2:
                    break
                seg_len = struct.unpack(">H", len_bytes)[0]
                if seg_len < 2:
                    break
                f.seek(seg_len - 2, os.SEEK_CUR)
    return {}


def inspect_media_metadata(file_path: str, filename: str) -> Dict[str, Any]:
    if not file_path or not os.path.isfile(file_path):
        return {}
    try:
        file_size = os.path.getsize(file_path)
        ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
        meta: Dict[str, Any] = {}
        if ext in {"mp4", "m4v", "mov"}:
            meta = _parse_mp4_metadata(file_path, file_size)
        elif ext in {"png", "jpg", "jpeg", "gif"}:
            meta = _parse_image_dimensions(file_path)

        dur = meta.get("duration_seconds")
        if dur and dur > 0 and file_size > 0:
            meta["bitrate_bps"] = int((file_size * 8) / dur)
        if "width" in meta and "height" in meta:
            meta["resolution"] = f"{meta['width']}x{meta['height']}"
        return meta
    except Exception:
        return {}


# ---------------------------------------------------------------------------
# Cgroup-Aware Container Telemetry (Accurate RAM & CPU on Hugging Face Spaces)
# ---------------------------------------------------------------------------

def _read_int_file(path: str) -> Optional[int]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            txt = f.read().strip()
        if not txt or txt == "max":
            return None
        val = int(txt)
        # Ignore unbounded kernel sentinel values (~2^63)
        if val <= 0 or val > (1 << 50):
            return None
        return val
    except Exception:
        return None


def get_memory_metrics() -> Tuple[int, int, int, float]:
    host_total = 0
    host_avail = 0
    try:
        mem: Dict[str, int] = {}
        with open("/proc/meminfo", "r", encoding="utf-8") as f:
            for line in f:
                if ":" in line:
                    k, v = line.split(":", 1)
                    parts = v.strip().split()
                    if parts and parts[0].isdigit():
                        mem[k.strip()] = int(parts[0]) * 1024
        host_total = mem.get("MemTotal", 0)
        host_avail = mem.get("MemAvailable", 0)
    except Exception:
        pass

    # Cgroup v2 check
    cg2_max = _read_int_file("/sys/fs/cgroup/memory.max")
    cg2_cur = _read_int_file("/sys/fs/cgroup/memory.current")
    if cg2_max and cg2_cur is not None:
        inactive_file = 0
        try:
            with open("/sys/fs/cgroup/memory.stat", "r", encoding="utf-8") as f:
                for line in f:
                    parts = line.split()
                    if len(parts) == 2 and parts[0] == "inactive_file":
                        inactive_file = int(parts[1])
                        break
        except Exception:
            pass
        total = min(cg2_max, host_total) if host_total else cg2_max
        used = max(0, cg2_cur - inactive_file)
        free = max(0, total - used)
        pct = round((used / total * 100.0) if total else 0.0, 1)
        return total, used, free, pct

    # Cgroup v1 check
    cg1_max = _read_int_file("/sys/fs/cgroup/memory/memory.limit_in_bytes")
    cg1_cur = _read_int_file("/sys/fs/cgroup/memory/memory.usage_in_bytes")
    if cg1_max and cg1_cur is not None:
        cache = 0
        try:
            with open("/sys/fs/cgroup/memory/memory.stat", "r", encoding="utf-8") as f:
                for line in f:
                    parts = line.split()
                    if len(parts) == 2 and parts[0] == "total_inactive_file":
                        cache = int(parts[1])
                        break
        except Exception:
            pass
        total = min(cg1_max, host_total) if host_total else cg1_max
        used = max(0, cg1_cur - cache)
        free = max(0, total - used)
        pct = round((used / total * 100.0) if total else 0.0, 1)
        return total, used, free, pct

    # Host /proc/meminfo fallback
    used = max(0, host_total - host_avail)
    free = max(0, host_avail)
    pct = round((used / host_total * 100.0) if host_total else 0.0, 1)
    return host_total, used, free, pct


def get_effective_cpu_cores() -> float:
    # Cgroup v2 cpu.max: "<quota> <period>"
    try:
        with open("/sys/fs/cgroup/cpu.max", "r", encoding="utf-8") as f:
            parts = f.read().strip().split()
            if len(parts) == 2 and parts[0] != "max":
                quota, period = int(parts[0]), int(parts[1])
                if quota > 0 and period > 0:
                    return round(quota / period, 2)
    except Exception:
        pass

    # Cgroup v1
    quota = _read_int_file("/sys/fs/cgroup/cpu/cpu.cfs_quota_us")
    period = _read_int_file("/sys/fs/cgroup/cpu/cpu.cfs_period_us")
    if quota and period and quota > 0 and period > 0:
        return round(quota / period, 2)

    return float(os.cpu_count() or 1)


# ---------------------------------------------------------------------------
# Remote Download Engine (Probe + Parallel Range + Single-Stream Fallback)
# ---------------------------------------------------------------------------

def probe_url(url: str) -> Dict[str, Any]:
    info: Dict[str, Any] = {
        "total": 0,
        "ranges": False,
        "filename": None,
        "status": None,
        "content_type": None,
    }
    sizes: List[int] = []

    try:
        r = remote_request(
            "HEAD",
            url,
            preload_content=False,
            timeout=Timeout(connect=CONNECT_TIMEOUT, read=45),
            retries=urllib3.Retry(total=2, redirect=5),
        )
        info["status"] = r.status
        info["content_type"] = r.headers.get("Content-Type")
        if r.status < 400:
            cl = r.headers.get("Content-Length")
            if cl and cl.isdigit():
                sizes.append(int(cl))
            ar = r.headers.get("Accept-Ranges", "")
            if "bytes" in ar.lower():
                info["ranges"] = True
            info["filename"] = filename_from_content_disposition(
                r.headers.get("Content-Disposition")
            )
        r.release_conn()
    except Exception as exc:
        info["head_error"] = str(exc)

    try:
        r = remote_request(
            "GET",
            url,
            headers={**DEFAULT_HEADERS, "Range": "bytes=0-0"},
            preload_content=False,
            timeout=Timeout(connect=CONNECT_TIMEOUT, read=45),
            retries=urllib3.Retry(total=2, redirect=5),
        )
        info["status"] = r.status
        info["content_type"] = r.headers.get("Content-Type") or info.get("content_type")
        if r.status in (404, 410):
            r.close()
            r.release_conn()
            info["http_error"] = format_http_status_error(r.status)
            return info
        if r.status >= 400:
            # Some presigned S3/CDN URLs reject Range headers with 400/403/416
            # while allowing a standard GET without Range; let _download_single try plain GET.
            r.close()
            r.release_conn()
            info["ranges"] = False
            return info

        cr = r.headers.get("Content-Range", "")
        if r.status == 206 and "/" in cr:
            info["ranges"] = True
            tail = cr.rsplit("/", 1)[-1].strip()
            if tail.isdigit():
                sizes.append(int(tail))
            r.read(64)
            r.release_conn()
        else:
            # Server ignored Range and returned 200 for full body — close immediately without draining!
            info["ranges"] = False
            cl = r.headers.get("Content-Length")
            if cl and cl.isdigit():
                sizes.append(int(cl))
            if not info["filename"]:
                info["filename"] = filename_from_content_disposition(
                    r.headers.get("Content-Disposition")
                )
            r.close()
            r.release_conn()
            info["total"] = max(sizes) if sizes else 0
            return info

        if not info["filename"]:
            info["filename"] = filename_from_content_disposition(
                r.headers.get("Content-Disposition")
            )
    except Exception as exc:
        info["probe_error"] = str(exc)

    info["total"] = max(sizes) if sizes else 0
    return info


def _download_range(
    url: str,
    path: str,
    start: int,
    end: int,
    seg_progress: List[int],
    idx: int,
    cancel: threading.Event,
) -> str:
    pos = start
    attempt = 0
    fd = os.open(path, os.O_WRONLY)
    try:
        while pos <= end and attempt < MAX_ATTEMPTS and not cancel.is_set():
            r = None
            try:
                r = remote_request(
                    "GET",
                    url,
                    headers={**DEFAULT_HEADERS, "Range": f"bytes={pos}-{end}"},
                    preload_content=False,
                    retries=urllib3.Retry(total=0, redirect=5),
                    timeout=Timeout(connect=CONNECT_TIMEOUT, read=READ_TIMEOUT),
                )
                if r.status >= 400:
                    r.release_conn()
                    return f"http_{r.status}"
                if r.status != 206:
                    r.close()
                    r.release_conn()
                    return "no_resume"
                match = re.fullmatch(r"bytes (\d+)-(\d+)/(\d+|\*)", r.headers.get("Content-Range", ""))
                if not match or int(match.group(1)) != pos or int(match.group(2)) != end:
                    r.close()
                    r.release_conn()
                    return "no_resume"

                last_flush = pos
                for chunk in r.stream(CHUNK_SIZE):
                    if cancel.is_set():
                        r.release_conn()
                        return "cancelled"
                    if not chunk:
                        break
                    if len(chunk) > end - pos + 1:
                        r.close()
                        r.release_conn()
                        return "no_resume"
                    os.pwrite(fd, chunk, pos)
                    pos += len(chunk)
                    seg_progress[idx] = pos - start
                    if pos - last_flush >= FLUSH_EVERY:
                        drop_page_cache(fd)
                        last_flush = pos

                drop_page_cache(fd)
                r.release_conn()
                r = None
                if pos > end:
                    return "done"
                attempt += 1
                time.sleep(min(2 * attempt, 15))
            except Exception:
                if r is not None:
                    try:
                        r.release_conn()
                    except Exception:
                        pass
                attempt += 1
                if not cancel.is_set():
                    time.sleep(min(2 * attempt, 15))

        if cancel.is_set():
            return "cancelled"
        return "done" if pos > end else "failed"
    finally:
        os.close(fd)


def _download_parallel(
    url: str,
    path: str,
    total: int,
    seg_progress: List[int],
    cancel: threading.Event,
) -> List[str]:
    seg_len = total // SEGMENTS
    bounds: List[Tuple[int, int]] = []
    for i in range(SEGMENTS):
        s = i * seg_len
        e = (total - 1) if i == SEGMENTS - 1 else (s + seg_len - 1)
        bounds.append((s, e))

    # Every segment starts at 0 downloaded bytes so total progress increases monotonically
    seg_progress[:] = [0] * SEGMENTS
    results: List[str] = ["failed"] * SEGMENTS
    threads: List[threading.Thread] = []

    def runner(index: int, start_b: int, end_b: int) -> None:
        results[index] = _download_range(url, path, start_b, end_b, seg_progress, index, cancel)

    for i, (s, e) in enumerate(bounds):
        t = threading.Thread(target=runner, args=(i, s, e), daemon=True)
        t.start()
        threads.append(t)

    for t in threads:
        t.join()
    return results


def _download_single(
    url: str,
    path: str,
    task_id: str,
    state: Dict[str, Any],
    cancel: threading.Event,
) -> str:
    attempt = 0
    last_error: Optional[str] = None
    while attempt < MAX_ATTEMPTS and not cancel.is_set():
        pos = 0
        r = None
        try:
            r = remote_request(
                "GET",
                url,
                headers=DEFAULT_HEADERS,
                preload_content=False,
                retries=urllib3.Retry(total=0, redirect=5),
                timeout=Timeout(connect=CONNECT_TIMEOUT, read=READ_TIMEOUT),
            )
            if r.status >= 400:
                status_code = r.status
                r.close()
                r.release_conn()
                r = None
                err_msg = format_http_status_error(status_code)
                if status_code in (429, 500, 502, 503, 504) and attempt + 1 < MAX_ATTEMPTS:
                    last_error = err_msg
                    attempt += 1
                    time.sleep(min(2 * attempt, 15))
                    continue
                raise RuntimeError(err_msg)

            cl_header = r.headers.get("Content-Length")
            cl = int(cl_header) if (cl_header and cl_header.isdigit()) else 0
            expected = tasks.get(task_id, {}).get("total_size", 0) or 0

            if cl and expected and cl != expected:
                r.release_conn()
                raise RuntimeError(
                    f"Remote file size changed during download (expected {format_bytes(expected)}, "
                    f"received {format_bytes(cl)}). The download link may have expired or returned an error page."
                )

            if cl and not expected:
                check_storage_quota(cl)
                tasks[task_id]["total_size"] = cl

            cd_name = filename_from_content_disposition(r.headers.get("Content-Disposition"))
            if cd_name and tasks[task_id].get("original_filename") == "downloaded_file.bin":
                tasks[task_id]["original_filename"] = cd_name

            with open(path, "r+b") as f:
                f.seek(0)
                f.truncate(0)
                last_flush = 0
                for chunk in r.stream(CHUNK_SIZE):
                    if cancel.is_set():
                        r.release_conn()
                        return "cancelled"
                    if not chunk:
                        break
                    f.write(chunk)
                    pos += len(chunk)
                    state["pos"] = pos
                    if not cl and pos % (64 * 1024 * 1024) < CHUNK_SIZE:
                        # Enforce storage quota dynamically on chunked streams without Content-Length
                        if calculate_storage_bytes(DATA_DIR) > MAX_TOTAL_STORAGE:
                            r.release_conn()
                            raise RuntimeError(
                                f"Download exceeded the {format_bytes(MAX_TOTAL_STORAGE)} server storage limit."
                            )
                    if pos - last_flush >= FLUSH_EVERY:
                        drop_page_cache(f.fileno())
                        last_flush = pos
                drop_page_cache(f.fileno())

            r.release_conn()
            r = None
            total = tasks.get(task_id, {}).get("total_size", 0) or 0
            if total == 0 or pos >= total:
                return "done"
            last_error = (
                f"Download incomplete: received {format_bytes(pos)} of {format_bytes(total)}. "
                "The remote server closed the connection prematurely."
            )
            attempt += 1
            time.sleep(min(2 * attempt, 15))
        except RuntimeError as exc:
            state["fatal_error"] = str(exc)
            return "fatal"
        except Exception as exc:
            if r is not None:
                try:
                    r.release_conn()
                except Exception:
                    pass
            last_error = f"Network error while downloading from remote host: {exc}"
            attempt += 1
            if not cancel.is_set():
                time.sleep(min(2 * attempt, 15))

    if cancel.is_set():
        return "cancelled"
    if last_error:
        state["fatal_error"] = last_error
    return "failed"


def run_download_to_disk(task_id: str, url: str, cancel: threading.Event) -> bool:
    """
    Downloads `url` into `tasks[task_id]['file_path']`.
    Returns True on verified success, False if failed or cancelled (updating task status/error).
    """
    stop_ticker = threading.Event()
    file_path = tasks[task_id]["file_path"]
    try:
        validated_url = validate_remote_url(url)
        info = probe_url(validated_url)

        if info.get("http_error"):
            raise RuntimeError(info["http_error"])
        if info.get("probe_error") and not info.get("total") and not info.get("status"):
            raise RuntimeError(
                "Unable to connect to the remote server. Please verify the URL and try again."
            )

        total = int(info.get("total") or 0)
        if info.get("filename"):
            safe_name = sanitize_filename(info["filename"])
            tasks[task_id]["original_filename"] = safe_name
            file_path = os.path.join(DATA_DIR, f"{task_id}_{safe_name}")
            tasks[task_id]["file_path"] = file_path

        tasks[task_id]["total_size"] = total
        tasks[task_id]["resumable"] = bool(info.get("ranges"))

        if total > 0:
            check_storage_quota(total)

        single_state: Dict[str, Any] = {"pos": 0}
        seg_progress: List[int] = [0]
        use_parallel = bool(info.get("ranges")) and total >= MIN_SIZE_FOR_PARALLEL

        def ticker() -> None:
            last_bytes = 0
            last_t = time.time()
            last_save = last_t
            while not stop_ticker.wait(1.0):
                try:
                    if task_id not in tasks:
                        break
                    done = sum(seg_progress) if tasks[task_id].get("_parallel_active") else single_state.get("pos", 0)
                    now = time.time()
                    dt = now - last_t
                    if dt > 0:
                        speed = max(0.0, (done - last_bytes) / dt)
                        tasks[task_id]["speed"] = speed
                        tsize = tasks[task_id].get("total_size", 0) or 0
                        if speed > 0 and tsize > done:
                            tasks[task_id]["eta_seconds"] = int((tsize - done) / speed)
                        else:
                            tasks[task_id]["eta_seconds"] = 0
                    tasks[task_id]["downloaded"] = done
                    last_bytes, last_t = done, now
                    if now - last_save >= 3.0:
                        save_state()
                        last_save = now
                except Exception:
                    pass

        threading.Thread(target=ticker, daemon=True).start()

        with open(file_path, "wb"):
            pass

        if use_parallel:
            seg_progress = [0] * SEGMENTS
            tasks[task_id]["_parallel_active"] = True
            res = _download_parallel(validated_url, file_path, total, seg_progress, cancel)
            if "cancelled" in res or cancel.is_set():
                result = "cancelled"
            elif "no_resume" in res:
                tasks[task_id]["resumable"] = False
                tasks[task_id]["_parallel_active"] = False
                with open(file_path, "r+b") as f:
                    f.truncate(0)
                result = _download_single(validated_url, file_path, task_id, single_state, cancel)
            elif any(r.startswith("http_") for r in res):
                code = int(next(r.split("_")[1] for r in res if r.startswith("http_")))
                raise RuntimeError(format_http_status_error(code))
            elif "failed" in res:
                result = "failed"
            else:
                result = "done"
        else:
            tasks[task_id]["_parallel_active"] = False
            result = _download_single(validated_url, file_path, task_id, single_state, cancel)

        stop_ticker.set()

        if result == "cancelled" or cancel.is_set():
            remove_task_artifacts(task_id, file_path)
            if task_id in tasks:
                tasks[task_id]["status"] = "cancelled"
                tasks[task_id]["speed"] = 0.0
                tasks[task_id]["error"] = "Task was cancelled by user."
            return False

        if result == "fatal":
            raise RuntimeError(single_state.get("fatal_error") or "Download failed.")

        if result != "done":
            raise RuntimeError(
                single_state.get("fatal_error")
                or "Download failed after multiple retry attempts due to unstable remote connection."
            )

        actual = os.path.getsize(file_path)
        expected_final = tasks[task_id].get("total_size", 0) or 0
        tasks[task_id]["downloaded"] = actual
        if expected_final and actual != expected_final:
            raise RuntimeError(
                f"Download incomplete: received {format_bytes(actual)} of {format_bytes(expected_final)}. "
                "The remote server closed the connection before the file finished transferring."
            )
        if actual == 0:
            raise RuntimeError("The remote URL returned an empty file (0 bytes).")

        tasks[task_id]["total_size"] = actual
        tasks[task_id]["speed"] = 0.0
        tasks[task_id]["eta_seconds"] = 0
        tasks[task_id]["verified"] = True
        return True

    except Exception as exc:
        stop_ticker.set()
        remove_task_artifacts(task_id, file_path)
        if task_id in tasks:
            if cancel.is_set():
                tasks[task_id]["status"] = "cancelled"
                tasks[task_id]["error"] = "Task was cancelled by user."
            else:
                tasks[task_id]["status"] = "error"
                tasks[task_id]["error"] = str(exc)
            tasks[task_id]["speed"] = 0.0
            tasks[task_id]["eta_seconds"] = 0
        return False


def sync_download_worker(task_id: str, url: str) -> None:
    cancel = tasks[task_id].get("_cancel") or threading.Event()
    tasks[task_id]["_cancel"] = cancel
    try:
        ok = run_download_to_disk(task_id, url, cancel)
        if ok and task_id in tasks:
            fpath = tasks[task_id]["file_path"]
            fname = tasks[task_id]["original_filename"]
            media_meta = inspect_media_metadata(fpath, fname)
            if media_meta:
                tasks[task_id]["media_info"] = media_meta
            tasks[task_id]["status"] = "completed"
    finally:
        save_state()
        gc.collect()


# ---------------------------------------------------------------------------
# Streaming GoFile Uploader (Exact Content-Length, Zero RAM Bloat, Live Speed)
# ---------------------------------------------------------------------------

def _discover_gofile_endpoints() -> List[Tuple[str, int, str, bool]]:
    """
    Returns ordered list of (host, port, path, use_tls) upload targets.
    Supports custom GOFILE_UPLOAD_ENDPOINT override for testing.
    """
    override = os.environ.get("GOFILE_UPLOAD_ENDPOINT", "").strip()
    if override:
        parsed = urllib.parse.urlsplit(override)
        use_tls = parsed.scheme.lower() == "https"
        port = parsed.port or (443 if use_tls else 80)
        return [(parsed.hostname or "localhost", port, parsed.path or "/uploadfile", use_tls)]

    targets: List[Tuple[str, int, str, bool]] = [
        ("upload.gofile.io", 443, "/uploadfile", True),
    ]
    try:
        r = _http.request(
            "GET",
            "https://api.gofile.io/servers",
            timeout=Timeout(connect=15, read=20),
            retries=1,
        )
        if r.status == 200:
            payload = json.loads(r.data.decode("utf-8", errors="replace"))
            servers = payload.get("data", {}).get("servers", [])
            for srv in servers[:2]:
                name = srv.get("name")
                if name:
                    targets.append((f"{name}.gofile.io", 443, "/contents/uploadfile", True))
                    targets.append((f"{name}.gofile.io", 443, "/uploadFile", True))
    except Exception:
        pass
    return targets


def _stream_file_to_gofile_target(
    host: str,
    port: int,
    path: str,
    use_tls: bool,
    file_path: str,
    filename: str,
    progress_cb,
    cancel: threading.Event,
) -> Dict[str, Any]:
    file_size = os.path.getsize(file_path)
    boundary = f"----DownListGoFileBoundary{uuid.uuid4().hex}"
    safe_header_name = filename.replace('"', "_").replace("\r", "").replace("\n", "")
    mime_type = guess_media_type(safe_header_name)

    preamble = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{safe_header_name}"\r\n'
        f"Content-Type: {mime_type}\r\n\r\n"
    ).encode("utf-8")
    epilogue = f"\r\n--{boundary}--\r\n".encode("utf-8")
    content_length = len(preamble) + file_size + len(epilogue)

    if use_tls:
        ctx = ssl.create_default_context()
        conn: http.client.HTTPConnection = http.client.HTTPSConnection(
            host, port, timeout=180, context=ctx
        )
    else:
        conn = http.client.HTTPConnection(host, port, timeout=180)

    try:
        conn.putrequest("POST", path, skip_host=True)
        conn.putheader("Host", host if port in (80, 443) else f"{host}:{port}")
        conn.putheader("User-Agent", DEFAULT_HEADERS["User-Agent"])
        conn.putheader("Accept", "application/json")
        conn.putheader("Content-Type", f"multipart/form-data; boundary={boundary}")
        conn.putheader("Content-Length", str(content_length))
        if GOFILE_API_TOKEN:
            conn.putheader("Authorization", f"Bearer {GOFILE_API_TOKEN}")
        conn.endheaders()

        conn.send(preamble)
        sent_file_bytes = 0
        last_flush = 0
        with open(file_path, "rb") as f:
            while True:
                if cancel.is_set():
                    raise InterruptedError("Upload cancelled by user.")
                chunk = f.read(GOFILE_CHUNK_SIZE)
                if not chunk:
                    break
                conn.send(chunk)
                sent_file_bytes += len(chunk)
                progress_cb(sent_file_bytes)
                if sent_file_bytes - last_flush >= FLUSH_EVERY:
                    drop_page_cache(f.fileno())
                    last_flush = sent_file_bytes
            drop_page_cache(f.fileno())

        conn.send(epilogue)
        resp = conn.getresponse()
        raw_body = resp.read().decode("utf-8", errors="replace")
        if resp.status >= 400:
            raise RuntimeError(f"GoFile server responded with HTTP {resp.status}.")
        parsed = json.loads(raw_body)
        if parsed.get("status") != "ok":
            err_detail = parsed.get("status") or "unknown error"
            raise RuntimeError(f"GoFile rejected the upload ({err_detail}).")
        data = parsed.get("data") or {}
        download_page = data.get("downloadPage")
        parsed_link = urllib.parse.urlsplit(str(download_page or ""))
        if parsed_link.scheme != "https" or parsed_link.hostname != "gofile.io" or not parsed_link.path.startswith("/d/"):
            raise RuntimeError("GoFile did not return a valid shareable download link.")
        return data
    finally:
        try:
            conn.close()
        except Exception:
            pass


def upload_local_file_to_gofile(task_id: str, file_path: str, filename: str, cancel: threading.Event) -> str:
    file_size = os.path.getsize(file_path)
    tasks[task_id]["status"] = "uploading_to_gofile"
    tasks[task_id]["total_size"] = file_size
    tasks[task_id]["downloaded"] = 0
    tasks[task_id]["speed"] = 0.0
    tasks[task_id]["eta_seconds"] = 0
    save_state()

    upload_pos = {"bytes": 0}
    stop_ticker = threading.Event()

    def ticker() -> None:
        last_b = 0
        last_t = time.time()
        while not stop_ticker.wait(1.0):
            if task_id not in tasks:
                break
            done = upload_pos["bytes"]
            now = time.time()
            dt = now - last_t
            if dt > 0:
                sp = max(0.0, (done - last_b) / dt)
                tasks[task_id]["speed"] = sp
                if sp > 0 and file_size > done:
                    tasks[task_id]["eta_seconds"] = int((file_size - done) / sp)
                else:
                    tasks[task_id]["eta_seconds"] = 0
            tasks[task_id]["downloaded"] = done
            last_b, last_t = done, now

    threading.Thread(target=ticker, daemon=True).start()

    try:
        targets = _discover_gofile_endpoints()
        last_exc: Optional[Exception] = None
        for host, port, path, use_tls in targets:
            if cancel.is_set():
                raise InterruptedError("Cancelled")
            upload_pos["bytes"] = 0
            try:
                result_data = _stream_file_to_gofile_target(
                    host=host,
                    port=port,
                    path=path,
                    use_tls=use_tls,
                    file_path=file_path,
                    filename=filename,
                    progress_cb=lambda b: upload_pos.__setitem__("bytes", b),
                    cancel=cancel,
                )
                tasks[task_id]["downloaded"] = file_size
                tasks[task_id]["speed"] = 0.0
                tasks[task_id]["eta_seconds"] = 0
                if result_data.get("code"):
                    tasks[task_id]["gofile_code"] = result_data["code"]
                return str(result_data["downloadPage"])
            except InterruptedError:
                raise
            except Exception as exc:
                last_exc = exc
                time.sleep(2)

        raise RuntimeError(
            f"Failed to upload file to GoFile: {last_exc or 'All GoFile upload servers were unreachable.'}"
        )
    finally:
        stop_ticker.set()


def sync_gofile_transfer_worker(task_id: str, url: str) -> None:
    cancel = tasks[task_id].get("_cancel") or threading.Event()
    tasks[task_id]["_cancel"] = cancel
    try:
        ok = run_download_to_disk(task_id, url, cancel)
        if not ok or task_id not in tasks:
            return

        file_path = tasks[task_id]["file_path"]
        filename = tasks[task_id]["original_filename"]

        gofile_link = upload_local_file_to_gofile(task_id, file_path, filename, cancel)

        # Persist the share link before deleting the temporary file.
        if task_id in tasks:
            tasks[task_id]["gofile_url"] = gofile_link
            tasks[task_id]["status"] = "completed"
            tasks[task_id]["speed"] = 0.0
            tasks[task_id]["eta_seconds"] = 0
            save_state()
            remove_task_artifacts(task_id, file_path)
            tasks[task_id]["local_deleted"] = not os.path.exists(file_path)
    except InterruptedError:
        if task_id in tasks:
            remove_task_artifacts(task_id, tasks[task_id].get("file_path"))
            tasks[task_id]["status"] = "cancelled"
            tasks[task_id]["speed"] = 0.0
            tasks[task_id]["error"] = "GoFile transfer was cancelled by user."
    except Exception as exc:
        if task_id in tasks:
            remove_task_artifacts(task_id, tasks[task_id].get("file_path"))
            tasks[task_id]["status"] = "error"
            tasks[task_id]["speed"] = 0.0
            tasks[task_id]["error"] = str(exc)
    finally:
        save_state()
        gc.collect()


# ---------------------------------------------------------------------------
# FastAPI Lifespan & Background Cleanup
# ---------------------------------------------------------------------------

async def _periodic_cleanup_loop() -> None:
    while True:
        await asyncio.sleep(3600)
        try:
            now = time.time()
            with _tasks_lock:
                expired_ids = [
                    tid
                    for tid, tinfo in tasks.items()
                    if tinfo.get("status") in {"completed", "extracted", "error", "cancelled"}
                    and (now - float(tinfo.get("timestamp") or now)) > FILE_RETENTION_SECONDS
                ]
                for tid in expired_ids:
                    tinfo = tasks.pop(tid, None)
                    if tinfo:
                        remove_task_artifacts(tid, tinfo.get("file_path"), tinfo.get("extract_path"))

                referenced_files = {
                    path for tinfo in tasks.values()
                    for path in (tinfo.get("file_path"), tinfo.get("extract_path")) if path
                }
            for fname in os.listdir(DATA_DIR):
                if fname.startswith(".tasks_state.json") or fname == ".write_test":
                    continue
                fpath = os.path.join(DATA_DIR, fname)
                try:
                    if fpath not in referenced_files and (now - os.path.getmtime(fpath)) > FILE_RETENTION_SECONDS:
                        if os.path.isfile(fpath):
                            os.remove(fpath)
                        elif os.path.isdir(fpath):
                            shutil.rmtree(fpath, ignore_errors=True)
                except OSError:
                    pass
            save_state()
        except Exception:
            pass


@asynccontextmanager
async def lifespan(_app: FastAPI):
    load_state_on_startup()
    cleanup_task = asyncio.create_task(_periodic_cleanup_loop())
    try:
        yield
    finally:
        cleanup_task.cancel()


app = FastAPI(
    title="DownList Server",
    version=SERVER_VERSION,
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# API Endpoints
# ---------------------------------------------------------------------------

@app.get("/")
@app.get("/health")
async def health_check():
    return {
        "status": "ok",
        "service": "DownList Server",
        "version": SERVER_VERSION,
        "server_online": True,
        "timestamp": time.time(),
    }


@app.post("/start_download")
async def start_download(req: DownloadRequest, background_tasks: BackgroundTasks):
    try:
        validated_url = validate_remote_url(req.url)
    except ValueError as exc:
        return JSONResponse(status_code=400, content={"error": str(exc)})

    task_id = str(uuid.uuid4())
    filename = clean_filename_from_url(validated_url)
    cancel_ev = threading.Event()
    with _tasks_lock:
        tasks[task_id] = {
            "task_id": task_id,
            "task_type": "download",
            "url": validated_url,
            "status": "downloading",
            "total_size": 0,
            "downloaded": 0,
            "speed": 0.0,
            "eta_seconds": 0,
            "file_path": os.path.join(DATA_DIR, f"{task_id}_{filename}"),
            "original_filename": filename,
            "resumable": None,
            "timestamp": int(time.time()),
            "_cancel": cancel_ev,
        }
    save_state()

    async def runner():
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(None, sync_download_worker, task_id, validated_url)

    background_tasks.add_task(runner)
    return {"task_id": task_id}


@app.post("/start_gofile_transfer")
async def start_gofile_transfer(req: DownloadRequest, background_tasks: BackgroundTasks):
    try:
        validated_url = validate_remote_url(req.url)
    except ValueError as exc:
        return JSONResponse(status_code=400, content={"error": str(exc)})

    task_id = str(uuid.uuid4())
    filename = clean_filename_from_url(validated_url)
    cancel_ev = threading.Event()
    with _tasks_lock:
        tasks[task_id] = {
            "task_id": task_id,
            "task_type": "gofile",
            "url": validated_url,
            "status": "downloading",
            "total_size": 0,
            "downloaded": 0,
            "speed": 0.0,
            "eta_seconds": 0,
            "file_path": os.path.join(DATA_DIR, f"{task_id}_{filename}"),
            "original_filename": filename,
            "gofile_url": None,
            "local_deleted": False,
            "timestamp": int(time.time()),
            "_cancel": cancel_ev,
        }
    save_state()

    async def runner():
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(None, sync_gofile_transfer_worker, task_id, validated_url)

    background_tasks.add_task(runner)
    return {"task_id": task_id}


@app.post("/upload_to_gofile/{task_id}")
async def upload_existing_task_to_gofile(task_id: str, background_tasks: BackgroundTasks):
    if task_id not in tasks:
        return JSONResponse(status_code=404, content={"error": "Task not found on server."})
    task = tasks[task_id]
    if task.get("gofile_url"):
        return {"status": "completed", "task_id": task_id, "gofile_url": task["gofile_url"]}

    file_path = task.get("file_path")
    if not file_path or not os.path.isfile(file_path):
        return JSONResponse(
            status_code=400,
            content={"error": "The local file is no longer available on the server."},
        )

    cancel_ev = threading.Event()
    task["_cancel"] = cancel_ev
    task["status"] = "uploading_to_gofile"
    save_state()

    def worker():
        try:
            link = upload_local_file_to_gofile(
                task_id, file_path, task.get("original_filename") or "file.bin", cancel_ev
            )
            task["gofile_url"] = link
            task["status"] = "completed"
        except Exception as exc:
            task["status"] = "error"
            task["error"] = str(exc)
        finally:
            save_state()

    async def runner():
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(None, worker)

    background_tasks.add_task(runner)
    return {"status": "uploading_to_gofile", "task_id": task_id}


@app.get("/status/{task_id}")
async def get_status(task_id: str):
    if task_id not in tasks:
        return JSONResponse(status_code=404, content={"error": "Task not found on server."})
    return public_task_dict(tasks[task_id])


@app.get("/history")
async def get_history():
    with _tasks_lock:
        items = [public_task_dict(t) for t in tasks.values()]
    items.sort(key=lambda x: float(x.get("timestamp") or 0), reverse=True)
    return {"history": items}


@app.get("/file_info/{task_id}")
async def get_file_info(task_id: str):
    if task_id not in tasks:
        return JSONResponse(status_code=404, content={"error": "Task not found on server."})
    task = tasks[task_id]
    fpath = task.get("file_path")
    fname = task.get("original_filename") or "file.bin"
    if not task.get("media_info") and fpath and os.path.isfile(fpath):
        meta = inspect_media_metadata(fpath, fname)
        if meta:
            task["media_info"] = meta
            save_state()
    return public_task_dict(task)


@app.get("/download/{task_id}")
@app.get("/download/{task_id}/{filename}")
async def download_file_endpoint(task_id: str, filename: Optional[str] = None):
    if task_id not in tasks:
        return JSONResponse(status_code=404, content={"error": "Task not found on server."})
    task = tasks[task_id]
    if task.get("status") not in {"completed", "extracted"}:
        return JSONResponse(status_code=400, content={"error": "File is not ready for download yet."})

    file_path = task.get("file_path")
    if (not file_path or not os.path.isfile(file_path)) and task.get("gofile_url"):
        return RedirectResponse(url=task["gofile_url"], status_code=302)
    if not file_path or not os.path.isfile(file_path):
        return JSONResponse(status_code=404, content={"error": "File is no longer present on the server."})

    out_name = task.get("original_filename") or filename or "downloaded_file"
    return FileResponse(
        file_path,
        filename=out_name,
        media_type=guess_media_type(out_name),
    )


@app.api_route("/stream/{task_id}", methods=["GET", "HEAD"])
@app.api_route("/stream/{task_id}/{filename}", methods=["GET", "HEAD"])
async def stream_file_endpoint(task_id: str, request: Request, filename: Optional[str] = None):
    if task_id not in tasks:
        return JSONResponse(status_code=404, content={"error": "Task not found on server."})
    task = tasks[task_id]
    if task.get("status") not in {"completed", "extracted"}:
        return JSONResponse(status_code=400, content={"error": "File is not ready for streaming yet."})

    file_path = task.get("file_path")
    if not file_path or not os.path.isfile(file_path):
        return JSONResponse(status_code=404, content={"error": "File is not stored on this server."})

    file_size = os.path.getsize(file_path)
    out_name = task.get("original_filename") or filename or "stream.bin"
    media_type = guess_media_type(out_name)
    encoded_name = urllib.parse.quote(out_name)
    base_headers = {
        "Accept-Ranges": "bytes",
        "Content-Disposition": f"inline; filename*=UTF-8''{encoded_name}",
    }

    range_header = request.headers.get("Range") or request.headers.get("range")

    def file_iterator(start_pos: int, total_len: int):
        with open(file_path, "rb") as f:
            f.seek(start_pos)
            remaining = total_len
            while remaining > 0:
                data = f.read(min(1024 * 1024, remaining))
                if not data:
                    break
                yield data
                remaining -= len(data)

    if range_header and range_header.strip().lower().startswith("bytes="):
        spec = range_header.strip()[6:].split(",", 1)[0].strip()
        if "-" not in spec:
            return Response(status_code=416, headers={"Content-Range": f"bytes */{file_size}"})
        left, right = spec.split("-", 1)
        try:
            if left == "":
                # Suffix byte-range (e.g. bytes=-65536 for MP4/MKV end-of-file index)
                suffix_len = int(right)
                if suffix_len <= 0:
                    return Response(status_code=416, headers={"Content-Range": f"bytes */{file_size}"})
                start_b = max(0, file_size - suffix_len)
                end_b = file_size - 1
            else:
                start_b = int(left)
                end_b = int(right) if right else (file_size - 1)
        except ValueError:
            return Response(status_code=416, headers={"Content-Range": f"bytes */{file_size}"})

        if file_size == 0 or start_b < 0 or start_b >= file_size or start_b > end_b:
            return Response(status_code=416, headers={"Content-Range": f"bytes */{file_size}"})

        end_b = min(end_b, file_size - 1)
        length = end_b - start_b + 1
        headers = {
            **base_headers,
            "Content-Range": f"bytes {start_b}-{end_b}/{file_size}",
            "Content-Length": str(length),
        }
        if request.method == "HEAD":
            return Response(status_code=206, headers=headers, media_type=media_type)
        return StreamingResponse(
            file_iterator(start_b, length),
            status_code=206,
            headers=headers,
            media_type=media_type,
        )

    headers = {
        **base_headers,
        "Content-Length": str(file_size),
    }
    if request.method == "HEAD":
        return Response(status_code=200, headers=headers, media_type=media_type)
    return StreamingResponse(
        file_iterator(0, file_size),
        status_code=200,
        headers=headers,
        media_type=media_type,
    )


@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    task_id = str(uuid.uuid4())
    original_filename = sanitize_filename(file.filename, fallback="uploaded_file.bin")
    file_path = os.path.join(DATA_DIR, f"{task_id}_{original_filename}")

    used_before = calculate_storage_bytes(DATA_DIR)
    available_budget = max(0, MAX_TOTAL_STORAGE - used_before)
    if available_budget <= 0:
        await file.close()
        return JSONResponse(
            status_code=507,
            content={
                "error": (
                    f"Server storage quota ({format_bytes(MAX_TOTAL_STORAGE)}) is full. "
                    "Please delete existing files before uploading."
                )
            },
        )

    written = 0
    last_flush = 0
    try:
        with open(file_path, "wb") as buffer:
            while True:
                chunk = await file.read(CHUNK_SIZE)
                if not chunk:
                    break
                written += len(chunk)
                if written > available_budget:
                    raise RuntimeError(
                        f"Upload exceeds the remaining {format_bytes(available_budget)} server storage quota."
                    )
                buffer.write(chunk)
                if written - last_flush >= FLUSH_EVERY:
                    drop_page_cache(buffer.fileno())
                    last_flush = written
            drop_page_cache(buffer.fileno())
    except Exception as exc:
        await file.close()
        remove_task_artifacts(task_id, file_path)
        return JSONResponse(status_code=400, content={"error": str(exc)})

    await file.close()
    file_size = os.path.getsize(file_path)
    media_meta = inspect_media_metadata(file_path, original_filename)

    with _tasks_lock:
        tasks[task_id] = {
            "task_id": task_id,
            "task_type": "upload",
            "url": "local_upload",
            "status": "completed",
            "total_size": file_size,
            "downloaded": file_size,
            "speed": 0.0,
            "eta_seconds": 0,
            "file_path": file_path,
            "original_filename": original_filename,
            "verified": True,
            "media_info": media_meta or None,
            "timestamp": int(time.time()),
        }
    save_state()
    return {"task_id": task_id}


@app.post("/cancel/{task_id}")
async def cancel_task(task_id: str):
    with _tasks_lock:
        task = tasks.get(task_id)
        if not task:
            return JSONResponse(status_code=404, content={"error": "Task not found on server."})
        if task.get("status") not in {"downloading", "uploading_to_gofile", "extracting", "queued", "pending"}:
            return JSONResponse(status_code=409, content={"error": "This task is not active."})
        previous_status = task.get("status")
        cancel_ev = task.get("_cancel")
        if isinstance(cancel_ev, threading.Event):
            cancel_ev.set()
        if previous_status in {"downloading", "uploading_to_gofile", "extracting", "queued", "pending"}:
            task["status"] = "cancelled"
            task["speed"] = 0.0
            task["eta_seconds"] = 0
            task["error"] = "Task was cancelled by user."
            if previous_status == "extracting":
                shutil.rmtree(task.get("extract_path") or os.path.join(DATA_DIR, f"extracted_{task_id}"), ignore_errors=True)
            else:
                remove_task_artifacts(task_id, task.get("file_path"), task.get("extract_path"))
    save_state()
    return {"status": "cancelled", "task_id": task_id}


@app.api_route("/delete/{task_id}", methods=["DELETE", "POST"])
async def delete_single_task(task_id: str):
    with _tasks_lock:
        task = tasks.pop(task_id, None)
    if not task:
        return JSONResponse(status_code=404, content={"error": "Task not found on server."})

    cancel_ev = task.get("_cancel")
    if isinstance(cancel_ev, threading.Event):
        cancel_ev.set()

    remove_task_artifacts(task_id, task.get("file_path"), task.get("extract_path"))
    save_state()
    gc.collect()
    stored_now = calculate_storage_bytes(DATA_DIR)
    return {
        "status": "success",
        "deleted_task_id": task_id,
        "storage_free": max(0, MAX_TOTAL_STORAGE - stored_now),
    }


@app.post("/rename/{task_id}")
async def rename_task_file(task_id: str, req: RenameRequest):
    with _tasks_lock:
        task = tasks.get(task_id)
        if not task:
            return JSONResponse(status_code=404, content={"error": "Task not found on server."})

        if task.get("status") not in {"completed", "extracted", "error", "cancelled"}:
            return JSONResponse(
                status_code=400,
                content={"error": "Cannot rename a file while it is actively transferring."},
            )

        requested = (req.new_name or "").strip()
        if not requested:
            return JSONResponse(status_code=400, content={"error": "New filename cannot be empty."})

        old_name = task.get("original_filename") or "file.bin"
        old_ext = old_name.rsplit(".", 1)[-1] if "." in old_name else ""
        if old_ext and "." not in requested:
            requested = f"{requested}.{old_ext}"

        safe_new_name = sanitize_filename(requested, fallback="")
        if not safe_new_name:
            return JSONResponse(status_code=400, content={"error": "Please enter a valid filename."})

        old_path = task.get("file_path")
        new_path = os.path.join(DATA_DIR, f"{task_id}_{safe_new_name}")

        if old_path and os.path.isfile(old_path) and old_path != new_path:
            try:
                os.replace(old_path, new_path)
            except OSError as exc:
                return JSONResponse(
                    status_code=500,
                    content={"error": f"Failed to rename file on disk: {exc}"},
                )
            task["file_path"] = new_path

        task["original_filename"] = safe_new_name

    save_state()
    return {"status": "success", "task": public_task_dict(task)}


@app.api_route("/delete_all", methods=["POST", "DELETE"])
async def delete_all_tasks():
    with _tasks_lock:
        for t in tasks.values():
            ev = t.get("_cancel")
            if isinstance(ev, threading.Event):
                ev.set()
        tasks.clear()

    for fname in os.listdir(DATA_DIR):
        if fname.startswith(".tasks_state.json") or fname == ".write_test":
            continue
        fpath = os.path.join(DATA_DIR, fname)
        try:
            if os.path.isfile(fpath) or os.path.islink(fpath):
                os.remove(fpath)
            elif os.path.isdir(fpath):
                shutil.rmtree(fpath, ignore_errors=True)
        except OSError:
            pass

    save_state()
    gc.collect()
    return {"status": "success"}


@app.get("/storage")
async def get_storage():
    disk_total, disk_used, disk_free = shutil.disk_usage(DATA_DIR)
    stored = calculate_storage_bytes(DATA_DIR)
    effective_total = min(disk_total, MAX_TOTAL_STORAGE)
    effective_free = min(disk_free, max(0, effective_total - stored))
    return {
        "total": effective_total,
        "used": stored,
        "free": effective_free,
        "host_disk_total": disk_total,
        "host_disk_used": disk_used,
        "host_disk_free": disk_free,
        "our_files_bytes": stored,
        "our_budget_bytes": MAX_TOTAL_STORAGE,
        "budget_left_bytes": max(0, MAX_TOTAL_STORAGE - stored),
    }


@app.get("/server_status")
async def get_server_status():
    ram_total, ram_used, ram_free, ram_pct = get_memory_metrics()

    stored_bytes = calculate_storage_bytes(DATA_DIR)
    try:
        disk_total, _, disk_free = shutil.disk_usage(DATA_DIR)
    except Exception:
        disk_total, disk_free = MAX_TOTAL_STORAGE, max(0, MAX_TOTAL_STORAGE - stored_bytes)

    storage_total = min(disk_total, MAX_TOTAL_STORAGE)
    storage_used = min(stored_bytes, storage_total)
    storage_free = min(disk_free, max(0, storage_total - storage_used))
    storage_pct = round((storage_used / storage_total * 100.0) if storage_total else 0.0, 1)

    active_states = {"downloading", "uploading_to_gofile", "extracting", "queued", "pending"}
    with _tasks_lock:
        all_tasks = list(tasks.values())
    active_count = sum(1 for t in all_tasks if str(t.get("status", "")).lower() in active_states)
    completed_count = sum(
        1 for t in all_tasks if str(t.get("status", "")).lower() in {"completed", "extracted"}
    )
    failed_count = sum(
        1 for t in all_tasks if str(t.get("status", "")).lower() in {"error", "failed", "extraction_error"}
    )

    try:
        load_1m = round(os.getloadavg()[0], 2)
    except Exception:
        load_1m = 0.0

    uptime_secs = max(0, int(time.time() - SERVER_START_TIME))

    return {
        "server_online": True,
        "server_version": SERVER_VERSION,
        "ram_total": ram_total,
        "ram_used": ram_used,
        "ram_free": ram_free,
        "ram_percent": ram_pct,
        "storage_total": storage_total,
        "storage_used": storage_used,
        "storage_free": storage_free,
        "storage_percent": storage_pct,
        "cpu_cores": get_effective_cpu_cores(),
        "load_avg": load_1m,
        "active_tasks": active_count,
        "completed_tasks": completed_count,
        "failed_tasks": failed_count,
        "total_tasks": len(all_tasks),
        "uptime_seconds": uptime_secs,
        "uptime": uptime_secs,
        "retention_hours": round(FILE_RETENTION_SECONDS / 3600, 1),
        "temperature": -1,
        "ping_ms": -1,
    }


# ---------------------------------------------------------------------------
# Safe ZIP Listing & Extraction (Zip-Slip & Quota Protected)
# ---------------------------------------------------------------------------

@app.get("/list_zip/{task_id}")
async def list_zip_contents(task_id: str):
    if task_id not in tasks:
        return JSONResponse(status_code=404, content={"error": "Task not found on server."})
    file_path = tasks[task_id].get("file_path")
    if not file_path or not os.path.isfile(file_path):
        return JSONResponse(status_code=404, content={"error": "ZIP file does not exist on the server."})
    if not zipfile.is_zipfile(file_path):
        return JSONResponse(status_code=400, content={"error": "This file is not a valid ZIP archive."})

    try:
        with zipfile.ZipFile(file_path, "r") as zf:
            entries = [
                {
                    "index": idx,
                    "filename": info.filename,
                    "file_size": info.file_size,
                    "file_size_mb": round(info.file_size / (1024 * 1024), 2),
                    "is_dir": info.is_dir(),
                }
                for idx, info in enumerate(zf.infolist())
            ]
        return {
            "task_id": task_id,
            "total_files": len(entries),
            "files": entries,
        }
    except Exception as exc:
        return JSONResponse(status_code=400, content={"error": f"Failed to read ZIP archive: {exc}"})


def _safe_extract_zip_worker(task_id: str, zip_path: str, target_dir: str) -> None:
    try:
        real_target = os.path.realpath(target_dir)
        with zipfile.ZipFile(zip_path, "r") as zf:
            total_uncompressed = sum(i.file_size for i in zf.infolist() if not i.is_dir())
            check_storage_quota(total_uncompressed)

            for member in zf.infolist():
                dest = os.path.realpath(os.path.join(real_target, member.filename))
                if not (dest == real_target or dest.startswith(real_target + os.sep)):
                    raise RuntimeError("Archive contains unsafe relative paths (Zip-Slip blocked).")
            cancel = tasks.get(task_id, {}).get("_cancel")
            for member in zf.infolist():
                if cancel and cancel.is_set():
                    raise InterruptedError("Extraction was cancelled.")
                dest = os.path.join(real_target, member.filename)
                if member.is_dir():
                    os.makedirs(dest, exist_ok=True)
                    continue
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                with zf.open(member) as source, open(dest, "wb") as output:
                    while True:
                        if cancel and cancel.is_set():
                            raise InterruptedError("Extraction was cancelled.")
                        chunk = source.read(1024 * 1024)
                        if not chunk:
                            break
                        output.write(chunk)

        if task_id in tasks and not (cancel and cancel.is_set()):
            tasks[task_id]["status"] = "extracted"
    except Exception as exc:
        shutil.rmtree(target_dir, ignore_errors=True)
        if task_id in tasks and tasks[task_id].get("status") != "cancelled":
            tasks[task_id]["status"] = "extraction_error"
            tasks[task_id]["error"] = str(exc)
    finally:
        save_state()


@app.post("/extract_zip/{task_id}")
async def extract_zip_file(task_id: str, background_tasks: BackgroundTasks):
    if task_id not in tasks:
        return JSONResponse(status_code=404, content={"error": "Task not found on server."})
    file_path = tasks[task_id].get("file_path")
    if not file_path or not os.path.isfile(file_path):
        return JSONResponse(status_code=404, content={"error": "ZIP file does not exist on the server."})
    if not zipfile.is_zipfile(file_path):
        return JSONResponse(status_code=400, content={"error": "This file is not a valid ZIP archive."})

    if tasks[task_id].get("status") not in {"completed", "extracted", "extraction_error", "cancelled"}:
        return JSONResponse(status_code=409, content={"error": "The task is already active."})
    tasks[task_id]["_cancel"] = threading.Event()
    extract_folder = os.path.join(DATA_DIR, f"extracted_{task_id}")
    shutil.rmtree(extract_folder, ignore_errors=True)
    os.makedirs(extract_folder, exist_ok=True)
    tasks[task_id]["status"] = "extracting"
    tasks[task_id]["extract_path"] = extract_folder
    save_state()

    async def runner():
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(None, _safe_extract_zip_worker, task_id, file_path, extract_folder)

    background_tasks.add_task(runner)
    return {"status": "extraction_started", "task_id": task_id}


@app.get("/extracted_files/{task_id}")
async def list_extracted_files(task_id: str):
    if task_id not in tasks:
        return JSONResponse(status_code=404, content={"error": "Task not found on server."})
    extract_folder = tasks[task_id].get("extract_path") or os.path.join(DATA_DIR, f"extracted_{task_id}")
    if not os.path.isdir(extract_folder):
        return JSONResponse(status_code=404, content={"error": "No extracted files found for this archive."})

    out = []
    for root_dir, _, fnames in os.walk(extract_folder):
        for fn in sorted(fnames):
            full = os.path.join(root_dir, fn)
            rel = os.path.relpath(full, extract_folder)
            out.append({"path": rel, "size": os.path.getsize(full)})
    return {"task_id": task_id, "files": out}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "7860")))
