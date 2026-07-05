#!/usr/bin/env python3
"""Registry operations for yantra.

Standalone script called by shell scripts that can't import Python modules.

CLI:
  registry.py list [--json]              list all instances with status
  registry.py get <name>                 get instance config as JSON
  registry.py add <name> <yaml>          add instance from YAML string
  registry.py remove <name>              remove instance
  registry.py set-env <name> <key> <val> set env var for instance
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------

def get_yantra_config():
    return os.environ.get("YANTRA_CONFIG", str(Path.home() / ".config" / "yantra"))


def get_registry_path():
    return Path(get_yantra_config()) / "registry.yml"


def load_registry():
    import yaml

    path = get_registry_path()
    if not path.exists():
        return {"instances": {}}
    try:
        with open(path) as f:
            data = yaml.safe_load(f) or {}
        # Tolerate files that have top-level keys directly
        return data if "instances" in data else {"instances": data}
    except yaml.YAMLError as e:
        print(f"Error parsing registry.yml: {e}", file=sys.stderr)
        sys.exit(2)


def save_registry(registry):
    import yaml

    path = get_registry_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.dump(registry, f, default_flow_style=False, sort_keys=False)


# ---------------------------------------------------------------------------
# Tmux session helpers
# ---------------------------------------------------------------------------

def get_running_sessions():
    """Return set of running tmux session names."""
    try:
        result = subprocess.run(
            ["tmux", "list-sessions", "-F", "#{session_name}"],
            capture_output=True, text=True,
        )
        if result.returncode == 0:
            return set(result.stdout.strip().splitlines())
    except FileNotFoundError:
        pass
    return set()


# ---------------------------------------------------------------------------
# Command handlers
# ---------------------------------------------------------------------------

def cmd_list(args):
    registry = load_registry()
    instances = registry.get("instances", {})
    running = get_running_sessions()

    if args.json:
        out = {}
        for name, cfg in instances.items():
            out[name] = dict(cfg)
            out[name]["status"] = "running" if name in running else "stopped"
        print(json.dumps({"instances": out}))
        return

    # Plain one-line-per-instance format for shell consumption
    for name, cfg in instances.items():
        context = cfg.get("context", "")
        label = cfg.get("label", "")
        color = cfg.get("color", "default")
        kind = "remote" if "remote" in cfg else "local"
        status = "running" if name in running else "stopped"
        print(f"{name} {context} {label} {color} {kind} {status}")


def cmd_get(args):
    registry = load_registry()
    instance = registry.get("instances", {}).get(args.name)
    if not instance:
        print(f"Instance '{args.name}' not found", file=sys.stderr)
        sys.exit(1)
    running = get_running_sessions()
    out = dict(instance)
    out["status"] = "running" if args.name in running else "stopped"
    print(json.dumps(out))


def cmd_add(args):
    import yaml

    registry = load_registry()
    if args.name in registry.get("instances", {}):
        print(f"Instance '{args.name}' already exists", file=sys.stderr)
        sys.exit(1)
    try:
        new_cfg = yaml.safe_load(args.yaml)
    except yaml.YAMLError as e:
        print(f"Invalid YAML: {e}", file=sys.stderr)
        sys.exit(2)
    if not isinstance(new_cfg, dict):
        print("YAML must be a mapping", file=sys.stderr)
        sys.exit(2)
    registry.setdefault("instances", {})[args.name] = new_cfg
    save_registry(registry)
    print(f"Added '{args.name}'")


def cmd_remove(args):
    registry = load_registry()
    if args.name not in registry.get("instances", {}):
        print(f"Instance '{args.name}' not found", file=sys.stderr)
        sys.exit(1)
    del registry["instances"][args.name]
    save_registry(registry)
    print(f"Removed '{args.name}'")


def cmd_set_env(args):
    registry = load_registry()
    instances = registry.get("instances", {})
    if args.name not in instances:
        print(f"Instance '{args.name}' not found", file=sys.stderr)
        sys.exit(1)
    instances[args.name].setdefault("env", {})[args.key] = args.val
    save_registry(registry)
    print(f"Set {args.name}.env.{args.key}={args.val}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        prog="registry.py",
        description="yantra registry operations",
    )
    sub = parser.add_subparsers(dest="command", metavar="<command>")
    sub.required = True

    p = sub.add_parser("list", help="List all instances with status")
    p.add_argument("--json", action="store_true")

    p = sub.add_parser("get", help="Get instance config as JSON")
    p.add_argument("name")

    p = sub.add_parser("add", help="Add instance from YAML string")
    p.add_argument("name")
    p.add_argument("yaml", metavar="<yaml>")

    p = sub.add_parser("remove", help="Remove an instance")
    p.add_argument("name")

    p = sub.add_parser("set-env", help="Set env var for instance")
    p.add_argument("name")
    p.add_argument("key")
    p.add_argument("val")

    args = parser.parse_args()

    dispatch = {
        "list": cmd_list,
        "get": cmd_get,
        "add": cmd_add,
        "remove": cmd_remove,
        "set-env": cmd_set_env,
    }
    dispatch[args.command](args)


if __name__ == "__main__":
    main()
