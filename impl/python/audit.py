#!/usr/bin/env python3
"""Audit log reader/writer for yantra.

CLI:
  audit.py write  --instance n --cmd "..." --exit 0 --duration 0
                  [--type auto|manual|system] [--summary "..."] [--window w] [--pane p] [--blast high|medium|low]
  audit.py note   --instance n --text "..."
  audit.py query  --instance n [--since 2h|YYYY-MM-DD] [--type t] [--search s]
                  [--blast h|m|l] [--exit code] [--annotated] [--json]
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone, timedelta
from itertools import groupby
from pathlib import Path


# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------

def get_yantra_config():
    return os.environ.get("YANTRA_CONFIG", str(Path.home() / ".config" / "yantra"))


def get_yantra_home():
    return os.environ.get(
        "YANTRA_HOME",
        str(Path(__file__).parent.parent.parent.resolve()),
    )


# ---------------------------------------------------------------------------
# File path helpers
# ---------------------------------------------------------------------------

def get_audit_dir(instance):
    """Return Path to audit dir for instance."""
    return Path(get_yantra_config()) / "audit" / instance


def get_audit_file(instance, date=None):
    """Return Path to daily JSONL file."""
    if date is None:
        date = datetime.now(timezone.utc).date()
    return get_audit_dir(instance) / f"{date.isoformat()}.jsonl"


# ---------------------------------------------------------------------------
# Read / Write
# ---------------------------------------------------------------------------

def write_record(record):
    """Append JSON line to the daily audit file, creating dirs as needed."""
    instance = record.get("instance", "unknown")
    audit_file = get_audit_file(instance)
    audit_file.parent.mkdir(parents=True, exist_ok=True)
    with open(audit_file, "a") as f:
        f.write(json.dumps(record) + "\n")


def load_records(instance, since_date=None, until_date=None):
    """Read all relevant JSONL files for an instance."""
    audit_dir = get_audit_dir(instance)
    if not audit_dir.exists():
        return []

    records = []
    for jsonl_file in sorted(audit_dir.glob("*.jsonl")):
        try:
            file_date = datetime.fromisoformat(jsonl_file.stem).date()
        except ValueError:
            continue
        if since_date and file_date < since_date:
            continue
        if until_date and file_date > until_date:
            continue
        try:
            with open(jsonl_file) as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        records.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
        except OSError:
            continue

    return records


# ---------------------------------------------------------------------------
# Filter helpers
# ---------------------------------------------------------------------------

def parse_since(since_str):
    """Parse --since value: '2h', '1d', '3w', 'YYYY-MM-DD'."""
    if not since_str:
        return None

    m = re.match(r"^(\d+)([hdwm])$", since_str.lower())
    if m:
        amount = int(m.group(1))
        unit = m.group(2)
        now = datetime.now(timezone.utc)
        delta = {"h": timedelta(hours=amount), "d": timedelta(days=amount),
                 "w": timedelta(weeks=amount), "m": timedelta(days=amount * 30)}.get(unit)
        if delta:
            return (now - delta).date()

    try:
        return datetime.fromisoformat(since_str).date()
    except ValueError:
        print(f"Invalid --since value: {since_str!r}", file=sys.stderr)
        return None


def apply_filters(records, type_filter=None, search=None, blast=None, exit_code=None, annotated=False):
    """Filter records list by various criteria."""
    out = []
    for r in records:
        if type_filter and r.get("type") != type_filter:
            continue
        if search and search.lower() not in r.get("cmd", "").lower():
            continue
        if blast and r.get("blast_radius") != blast:
            continue
        if exit_code is not None and r.get("exit") != exit_code:
            continue
        if annotated and not r.get("summary"):
            continue
        out.append(r)
    return out


# ---------------------------------------------------------------------------
# Note (annotate last record)
# ---------------------------------------------------------------------------

def note_last(instance, text):
    """Read last line of today's file, update summary field, rewrite."""
    audit_file = get_audit_file(instance)
    if not audit_file.exists():
        print(f"No audit file for today: {audit_file}", file=sys.stderr)
        sys.exit(1)

    raw = audit_file.read_text().strip().splitlines()
    if not raw:
        print("Audit file is empty", file=sys.stderr)
        sys.exit(1)

    try:
        last = json.loads(raw[-1])
    except json.JSONDecodeError:
        print("Could not parse last record", file=sys.stderr)
        sys.exit(1)

    last["summary"] = text
    raw[-1] = json.dumps(last)
    audit_file.write_text("\n".join(raw) + "\n")


# ---------------------------------------------------------------------------
# Pattern matching
# ---------------------------------------------------------------------------

def match_audit_patterns(cmd):
    """Load _base/audit-patterns.yml, return (summary, blast_radius) if matched."""
    import fnmatch
    yantra_home = get_yantra_home()
    patterns_file = Path(yantra_home) / "contexts" / "_base" / "audit-patterns.yml"
    if not patterns_file.exists():
        return None, None

    try:
        import yaml
        with open(patterns_file) as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        return None, None

    for entry in data.get("patterns", []):
        glob = entry.get("match", "")
        if glob and fnmatch.fnmatch(cmd, glob):
            return entry.get("summary"), entry.get("blast_radius")

    return None, None


# ---------------------------------------------------------------------------
# Display helpers
# ---------------------------------------------------------------------------

def _rich_available():
    try:
        import rich  # noqa: F401
        return True
    except ImportError:
        return False


def format_duration(ms):
    if ms is None:
        return ""
    if ms < 1000:
        return f"{ms}ms"
    return f"{ms / 1000:.1f}s"


def _group_key(record):
    ts = record.get("ts", "")
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        return dt.date().isoformat(), record.get("instance", "")
    except Exception:
        return "unknown", record.get("instance", "")


def format_record_plain(record):
    ts = record.get("ts", "")
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        time_str = dt.strftime("%H:%M:%S")
    except Exception:
        time_str = ts

    rec_type = record.get("type", "manual")
    window = record.get("window", "")
    pane = record.get("pane", "")
    location = f"{window}/{pane}" if window and pane else window or pane
    cmd_val = record.get("cmd", "")
    exit_code = record.get("exit", 0)
    duration = format_duration(record.get("duration_ms"))
    status = "✓" if exit_code == 0 else "✗"
    blast = record.get("blast_radius")
    blast_str = f"  [{blast}]" if blast else ""
    summary = record.get("summary", "")

    line = f"  {time_str}  {rec_type:<6}  {location:<16}  {cmd_val:<40}  {status}  {duration}{blast_str}"
    if summary:
        line += f"\n                    {summary}"
    return line


def format_records_plain(records):
    """Group by date+instance and format as plain text."""
    records = sorted(records, key=lambda r: r.get("ts", ""))
    lines = []
    for (date, inst), grp in groupby(records, key=_group_key):
        lines.append(f"\n{date}  {inst}")
        lines.append("─" * 70)
        for r in grp:
            lines.append(format_record_plain(r))
    return "\n".join(lines)


def format_records_rich(records):
    from rich.console import Console

    console = Console()
    records = sorted(records, key=lambda r: r.get("ts", ""))

    for (date, inst), grp in groupby(records, key=_group_key):
        console.print(f"\n[bold]{date}  {inst}[/bold]")
        console.print("─" * 70)
        for r in grp:
            ts = r.get("ts", "")
            try:
                dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                time_str = dt.strftime("%H:%M:%S")
            except Exception:
                time_str = ts

            rec_type = r.get("type", "manual")
            window = r.get("window", "")
            pane = r.get("pane", "")
            location = f"{window}/{pane}" if window and pane else window or pane
            cmd_val = r.get("cmd", "")
            exit_code = r.get("exit", 0)
            duration = format_duration(r.get("duration_ms"))
            status_str = "[green]✓[/green]" if exit_code == 0 else "[red]✗[/red]"
            blast = r.get("blast_radius")
            blast_str = f"  [yellow][{blast}][/yellow]" if blast else ""
            summary = r.get("summary", "")

            console.print(
                f"  {time_str}  [cyan]{rec_type:<6}[/cyan]  "
                f"{location:<16}  {cmd_val:<40}  {status_str}  {duration}{blast_str}"
            )
            if summary:
                console.print(f"                    [dim]{summary}[/dim]")


# ---------------------------------------------------------------------------
# Command handlers
# ---------------------------------------------------------------------------

def cmd_write(args):
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    summary = args.summary
    blast = args.blast
    # Auto-fill from patterns if not explicitly provided
    if not blast or not summary:
        auto_summary, auto_blast = match_audit_patterns(args.cmd)
        if not summary:
            summary = auto_summary
        if not blast:
            blast = auto_blast

    record = {
        "ts": ts,
        "instance": args.instance,
        "context": os.environ.get("YANTRA_CONTEXT_TYPE", ""),
        "window": args.window or "",
        "pane": args.pane or "",
        "cmd": args.cmd,
        "exit": args.exit,
        "duration_ms": args.duration,
        "type": args.type or "manual",
        "summary": summary,
        "blast_radius": blast,
    }

    write_record(record)


def cmd_note(args):
    note_last(args.instance, args.text)


def cmd_query(args):
    since_date = parse_since(args.since) if args.since else None
    records = load_records(args.instance, since_date=since_date)

    records = apply_filters(
        records,
        type_filter=args.type,
        search=args.search,
        blast=args.blast,
        exit_code=args.exit_code,
        annotated=args.annotated,
    )

    if args.json:
        print(json.dumps(records))
        return

    if not records:
        print("No records found.")
        return

    if _rich_available():
        format_records_rich(records)
    else:
        print(format_records_plain(records))


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(prog="audit.py", description="yantra audit log")
    sub = parser.add_subparsers(dest="command", metavar="<command>")
    sub.required = True

    # write
    p = sub.add_parser("write", help="Write an audit record")
    p.add_argument("--instance", required=True)
    p.add_argument("--cmd", required=True)
    p.add_argument("--exit", type=int, default=0)
    p.add_argument("--duration", type=int, default=0)
    p.add_argument("--type", choices=["auto", "manual", "system"], default="manual")
    p.add_argument("--summary")
    p.add_argument("--window")
    p.add_argument("--pane")
    p.add_argument("--blast", choices=["high", "medium", "low"])

    # note
    p = sub.add_parser("note", help="Annotate last audit record")
    p.add_argument("--instance", required=True)
    p.add_argument("--text", required=True)

    # query
    p = sub.add_parser("query", help="Query audit log")
    p.add_argument("--instance", required=True)
    p.add_argument("--since", help="e.g. 2h, 1d, 3w, YYYY-MM-DD")
    p.add_argument("--type", choices=["auto", "manual", "system"])
    p.add_argument("--search", help="Search string in cmd")
    p.add_argument("--blast", choices=["high", "medium", "low"])
    p.add_argument("--exit", type=int, dest="exit_code", help="Filter by exit code")
    p.add_argument("--annotated", action="store_true", help="Only records with summary")
    p.add_argument("--json", action="store_true")

    args = parser.parse_args()

    dispatch = {"write": cmd_write, "note": cmd_note, "query": cmd_query}
    dispatch[args.command](args)


if __name__ == "__main__":
    main()
