#!/usr/bin/env python3
"""Runs a command, streaming output live, and emits GitHub Check Run error annotations on failure."""

import subprocess
import sys


def escape_gha(text: str) -> str:
    return (
        text.replace("%", "%25")
        .replace("\r", "%0D")
        .replace("\n", "%0A")
    )


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: run_with_annotations.py <command...>", file=sys.stderr)
        return 2

    cmd = sys.argv[1:]
    print(f"+ {' '.join(cmd)}", flush=True)
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
        bufsize=1,
    )

    lines: list[str] = []
    assert proc.stdout is not None
    for line in proc.stdout:
        sys.stdout.write(line)
        sys.stdout.flush()
        lines.append(line.rstrip("\r\n"))

    rc = proc.wait()
    if rc != 0:
        err_lines = [
            ln for ln in lines
            if any(k in ln.lower() for k in ("error:", "exception", "failure", "failed", "what went wrong", "caused by"))
        ]
        if err_lines:
            summary = "\n".join(err_lines[-40:])[:3500]
            print(f"::error title=CompilerOrGradleErrors::{escape_gha(summary)}", flush=True)
        tail = "\n".join(lines[-60:])[:3500]
        print(f"::error title=BuildLogTail::{escape_gha(tail)}", flush=True)
    return rc


if __name__ == "__main__":
    sys.exit(main())
