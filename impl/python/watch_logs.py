#!/usr/bin/env python3
"""Log watcher for yantra. Reads watchers.yml, monitors log streams, writes to bubble pane.

CLI:
  watch_logs.py --config <path/watchers.yml> --instance <name> --context-dir <path>

watchers.yml shape:
  watchers:
    <id>:
      source:
        type: service|file|ssh_pipe|op
        service: <svc_id>       # for type: service
        path: <file_path>       # for type: file
        host: <user@host>       # for type: ssh_pipe
        cmd:  <remote_cmd>      # for type: ssh_pipe
      keywords:
        - pattern: "ERROR"
          level: error
          actions: [bubble, log]
        - pattern: "WARN"
          level: warn
          actions: [bubble]
"""

import argparse
import re
import select
import subprocess
import sys
import time
from pathlib import Path


# ---------------------------------------------------------------------------
# YAML loader
# ---------------------------------------------------------------------------

def load_watchers(config_path):
    """Parse watchers.yml and return the watchers dict."""
    import yaml

    with open(config_path) as f:
        data = yaml.safe_load(f) or {}
    return data.get("watchers", {})


# ---------------------------------------------------------------------------
# Tmux helpers
# ---------------------------------------------------------------------------

def _get_tmux_server():
    import libtmux
    return libtmux.Server()


def _get_pane(server, instance, window_name, pane_index=0):
    """Retrieve a specific tmux pane, or None if not found."""
    try:
        sess = server.sessions.get(session_name=instance)
        if not sess:
            return None
        win = sess.windows.get(window_name=window_name)
        if not win:
            return None
        return win.panes[pane_index] if pane_index < len(win.panes) else None
    except Exception:
        return None


def _send_to_bubble(server, instance, text):
    """Write a formatted line to the bubble pane (echo into it)."""
    pane = _get_pane(server, instance, "bubble")
    if pane:
        # Escape single quotes to avoid shell breakage
        safe = text.replace("'", "'\\''")
        pane.send_keys(f"echo '{safe}'", enter=True)


# ---------------------------------------------------------------------------
# Source handlers — each returns a list of new lines
# ---------------------------------------------------------------------------

def _watch_tmux_pane(watcher_id, source, instance, server, pane_state):
    """Capture tmux pane content and return lines not seen before."""
    service_id = source.get("service", watcher_id)
    pane = _get_pane(server, instance, service_id)
    if not pane:
        return []

    try:
        lines = pane.capture_pane() or []
    except Exception:
        return []

    # Dedup against previously seen lines (last 300)
    prev = pane_state.get(watcher_id, set())
    new_lines = [l for l in lines if l.strip() and l not in prev]
    pane_state[watcher_id] = set(lines[-300:])
    return new_lines


def _watch_file(watcher_id, source, context_dir, file_state):
    """Tail a local file and return new lines since last read."""
    raw_path = source.get("path", "")
    if not raw_path:
        return []

    path = Path(raw_path)
    if not path.is_absolute():
        path = Path(context_dir) / raw_path

    if not path.exists():
        return []

    key = str(path)
    last_pos = file_state.get(key, 0)

    try:
        with open(path) as f:
            f.seek(last_pos)
            chunk = f.read()
            file_state[key] = f.tell()
        return chunk.splitlines() if chunk else []
    except OSError:
        return []


def _watch_ssh_pipe(watcher_id, source, proc_state):
    """Read non-blocking from an SSH subprocess pipe."""
    if watcher_id not in proc_state:
        host = source.get("host", "")
        cmd = source.get("cmd", "")
        if not host or not cmd:
            return []
        try:
            proc = subprocess.Popen(
                ["ssh", "-o", "BatchMode=yes", host, cmd],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
            )
            proc_state[watcher_id] = proc
        except Exception as e:
            print(f"[{watcher_id}] ssh pipe error: {e}", file=sys.stderr)
            return []

    proc = proc_state[watcher_id]
    if proc.poll() is not None:
        # Process ended; remove so it can be restarted next cycle
        del proc_state[watcher_id]
        return []

    lines = []
    try:
        while True:
            ready, _, _ = select.select([proc.stdout], [], [], 0)
            if not ready:
                break
            line = proc.stdout.readline()
            if not line:
                break
            lines.append(line.rstrip())
    except Exception:
        pass
    return lines


# ---------------------------------------------------------------------------
# Pattern matching
# ---------------------------------------------------------------------------

def match_keywords(watcher, line):
    """Check line against watcher keyword patterns.
    Returns (matched: bool, level: str, actions: list)."""
    for kw in watcher.get("keywords", []):
        pattern = kw.get("pattern", "")
        if not pattern:
            continue
        if re.search(pattern, line, re.IGNORECASE):
            return True, kw.get("level", "info"), kw.get("actions", [])
    return False, None, []


def format_bubble_line(watcher_id, level, line):
    now = time.strftime("%H:%M")
    return f"[{now}] [{watcher_id}] {level.upper()}: {line}"


# ---------------------------------------------------------------------------
# Main watch loop
# ---------------------------------------------------------------------------

def run_watchers(watchers, instance, context_dir):
    """Main polling loop over all configured watchers."""
    try:
        server = _get_tmux_server()
    except ImportError:
        print("libtmux not available — tmux-based watching disabled", file=sys.stderr)
        server = None

    pane_state = {}   # watcher_id -> set of seen lines
    file_state = {}   # file path -> last byte offset
    proc_state = {}   # watcher_id -> subprocess (ssh_pipe)

    print(f"[yantra] watching {len(watchers)} watcher(s) — instance: {instance}", file=sys.stderr)

    while True:
        for watcher_id, watcher in watchers.items():
            source = watcher.get("source", {})
            source_type = source.get("type", "service")

            if source_type in ("service", "op") and server:
                new_lines = _watch_tmux_pane(watcher_id, source, instance, server, pane_state)
            elif source_type == "file":
                new_lines = _watch_file(watcher_id, source, context_dir, file_state)
            elif source_type == "ssh_pipe":
                new_lines = _watch_ssh_pipe(watcher_id, source, proc_state)
            else:
                new_lines = []

            for line in new_lines:
                # Always echo to stderr so the watcher's own pane shows it
                print(f"[{watcher_id}] {line}", file=sys.stderr)

                matched, level, actions = match_keywords(watcher, line)
                if matched:
                    bubble_text = format_bubble_line(watcher_id, level, line)
                    if "bubble" in actions and server:
                        _send_to_bubble(server, instance, bubble_text)
                    if "log" in actions:
                        # Print to stdout for pipe capture
                        print(bubble_text, flush=True)

        time.sleep(0.5)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        prog="watch_logs.py",
        description="yantra log watcher",
    )
    parser.add_argument("--config", required=True, help="Path to watchers.yml")
    parser.add_argument("--instance", required=True, help="Tmux session / instance name")
    parser.add_argument("--context-dir", required=True, help="Context directory path")
    args = parser.parse_args()

    try:
        import yaml  # noqa: F401
    except ImportError:
        print("pyyaml not installed — run: pip3 install pyyaml", file=sys.stderr)
        sys.exit(2)

    config_path = Path(args.config)
    if not config_path.exists():
        print(f"watchers.yml not found: {config_path}", file=sys.stderr)
        sys.exit(2)

    watchers = load_watchers(str(config_path))
    if not watchers:
        print("No watchers defined in config — nothing to do.", file=sys.stderr)
        sys.exit(0)

    try:
        run_watchers(watchers, args.instance, args.context_dir)
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    main()
