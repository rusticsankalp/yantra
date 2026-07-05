#!/usr/bin/env python3
"""Health check runner for yantra services.

CLI:
  healthcheck.py port        --host <h> --port <p> [--timeout 30]
  healthcheck.py http        --url <u> [--expect <pattern>] [--timeout 30]
  healthcheck.py log_pattern --session <s> --window <w> --pane <p> --pattern <pat> [--timeout 60]

Exit codes:
  0 = ready / healthy
  1 = timeout
  2 = error / bad config
"""

import argparse
import re
import socket
import sys
import time


# ---------------------------------------------------------------------------
# Port check
# ---------------------------------------------------------------------------

def poll_port(host, port, timeout):
    """Poll TCP port until it accepts a connection or timeout."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection((host, port), timeout=2):
                print("READY", flush=True)
                return True
        except (ConnectionRefusedError, OSError):
            print(".", end="", flush=True, file=sys.stderr)
            time.sleep(2)
    print("", file=sys.stderr)  # newline after dots
    print("TIMEOUT", flush=True)
    return False


# ---------------------------------------------------------------------------
# HTTP check
# ---------------------------------------------------------------------------

def poll_http(url, expect_pattern, timeout):
    """Poll HTTP endpoint until status 200 (and optional body pattern match)."""
    try:
        import requests
    except ImportError:
        print("requests not installed — run: pip3 install requests", file=sys.stderr)
        sys.exit(2)

    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            resp = requests.get(url, timeout=5)
            if resp.status_code == 200:
                if expect_pattern and not re.search(expect_pattern, resp.text):
                    print(".", end="", flush=True, file=sys.stderr)
                    time.sleep(2)
                    continue
                print("READY", flush=True)
                return True
        except Exception:
            pass
        print(".", end="", flush=True, file=sys.stderr)
        time.sleep(2)
    print("", file=sys.stderr)
    print("TIMEOUT", flush=True)
    return False


# ---------------------------------------------------------------------------
# Log pattern check
# ---------------------------------------------------------------------------

def poll_log_pattern(session, window, pane_index, pattern, timeout):
    """Poll a tmux pane's captured content for a regex pattern."""
    try:
        import libtmux
    except ImportError:
        print("libtmux not installed — run: pip3 install libtmux", file=sys.stderr)
        sys.exit(2)

    server = libtmux.Server()
    deadline = time.time() + timeout

    while time.time() < deadline:
        try:
            sess = server.sessions.get(session_name=session)
            if sess:
                win = sess.windows.get(window_name=window)
                if win and pane_index < len(win.panes):
                    content = win.panes[pane_index].capture_pane()
                    for line in (content or []):
                        if re.search(pattern, line):
                            print("READY", flush=True)
                            return True
        except Exception as e:
            print(f"\nerror: {e}", file=sys.stderr)
        print(".", end="", flush=True, file=sys.stderr)
        time.sleep(2)

    print("", file=sys.stderr)
    print("TIMEOUT", flush=True)
    return False


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        prog="healthcheck.py",
        description="yantra service health check runner",
    )
    sub = parser.add_subparsers(dest="check_type", metavar="<type>")
    sub.required = True

    p = sub.add_parser("port", help="TCP port connectivity check")
    p.add_argument("--host", default="localhost")
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--timeout", type=int, default=30)

    p = sub.add_parser("http", help="HTTP endpoint check")
    p.add_argument("--url", required=True)
    p.add_argument("--expect", metavar="PATTERN", help="Regex pattern to require in response body")
    p.add_argument("--timeout", type=int, default=30)

    p = sub.add_parser("log_pattern", help="Tmux pane log pattern check")
    p.add_argument("--session", required=True, help="Tmux session name")
    p.add_argument("--window", required=True, help="Tmux window name")
    p.add_argument("--pane", default="0", help="Pane index (default: 0)")
    p.add_argument("--pattern", required=True, help="Regex pattern to find in pane output")
    p.add_argument("--timeout", type=int, default=60)

    args = parser.parse_args()

    if args.check_type == "port":
        ok = poll_port(args.host, args.port, args.timeout)
    elif args.check_type == "http":
        ok = poll_http(args.url, args.expect, args.timeout)
    elif args.check_type == "log_pattern":
        ok = poll_log_pattern(args.session, args.window, int(args.pane), args.pattern, args.timeout)
    else:
        print(f"Unknown check type: {args.check_type}", file=sys.stderr)
        sys.exit(2)

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
