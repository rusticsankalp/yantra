#!/usr/bin/env python3
"""Service lifecycle management for yantra.

Reads services.yml, manages processes via tmux panes.

CLI:
  orchestrate.py start   --context <name> [--service <id>] [--group <grp>]
  orchestrate.py stop    --context <name> [--service <id>] [--group <grp>] [--all]
  orchestrate.py status  --context <name> [--json]
  orchestrate.py restart --context <name> [--service <id>]
  orchestrate.py build   --context <name> [--service <id>] [--group <grp>]
  orchestrate.py wait    --context <name> --service <id> [--timeout <secs:30>]

services.yml shape:
  services:
    svc1:
      cmd: "java -jar svc1.jar"
      group: backend
      auto_start: true
      depends_on: [db]
      health:
        type: port     # port | http | log_pattern
        port: 8081
      build:
        cmd: "mvn package -pl svc1"
"""

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------

def get_yantra_home():
    return os.environ.get(
        "YANTRA_HOME",
        str(Path(__file__).parent.parent.parent.resolve()),
    )


def get_yantra_config():
    return os.environ.get("YANTRA_CONFIG", str(Path.home() / ".config" / "yantra"))


# ---------------------------------------------------------------------------
# Service loading
# ---------------------------------------------------------------------------

def load_services(context_type):
    """Parse services.yml from contexts/<type>/services.yml."""
    import yaml

    path = Path(get_yantra_home()) / "contexts" / context_type / "services.yml"
    if not path.exists():
        print(f"services.yml not found: {path}", file=sys.stderr)
        return {}
    try:
        with open(path) as f:
            data = yaml.safe_load(f) or {}
        # Accept both {services: {...}} and {services: [{id: ...}, ...]}.
        services = data.get("services", data)
        if isinstance(services, list):
            normalized = {}
            for service in services:
                if not isinstance(service, dict):
                    continue
                service_id = service.get("id")
                if service_id:
                    normalized[service_id] = service
            return normalized
        return services
    except Exception as e:
        print(f"Error parsing services.yml: {e}", file=sys.stderr)
        sys.exit(2)


# ---------------------------------------------------------------------------
# Dependency resolution
# ---------------------------------------------------------------------------

def _collect_with_deps(services, target):
    """Return set of target + all transitive dependencies."""
    result = set()
    queue = [target]
    while queue:
        svc = queue.pop()
        if svc in result:
            continue
        result.add(svc)
        for dep in services.get(svc, {}).get("depends_on", []):
            if dep in services:
                queue.append(dep)
    return result


def _topo_sort(services, candidates):
    """Topological sort of candidates set. Returns ordered list."""
    order = []
    visited = set()

    def visit(node, stack=None):
        if node in visited:
            return
        if stack is None:
            stack = set()
        stack.add(node)
        for dep in services.get(node, {}).get("depends_on", []):
            if dep in candidates and dep not in stack:
                visit(dep, stack)
        stack.discard(node)
        visited.add(node)
        order.append(node)

    for svc in sorted(candidates):
        visit(svc)

    return order


def resolve_start_order(services, target=None, group=None):
    """Return ordered list of services to start.

    - target specified: that service + its deps, in dep order
    - group specified: all services in that group
    - neither: all auto_start services
    """
    if target and target != "all":
        candidates = _collect_with_deps(services, target)
    elif group:
        candidates = {k for k, v in services.items() if v.get("group") == group}
    else:
        candidates = {k for k, v in services.items() if v.get("auto_start", False)}

    return _topo_sort(services, candidates)


def resolve_stop_order(services, target=None, group=None):
    """Reverse of start order."""
    return list(reversed(resolve_start_order(services, target, group)))


def resolve_build_cascade(services, target):
    """Return (target, dependents_list) where dependents transitively depend on target."""
    dependents = set()
    queue = [target]
    while queue:
        current = queue.pop()
        for svc, cfg in services.items():
            if current in cfg.get("depends_on", []) and svc not in dependents:
                dependents.add(svc)
                queue.append(svc)
    # Order dependents in start order so we can reverse for stop
    ordered_deps = _topo_sort(services, dependents) if dependents else []
    return target, ordered_deps


# ---------------------------------------------------------------------------
# Tmux helpers
# ---------------------------------------------------------------------------

def _tmux_server():
    import libtmux
    return libtmux.Server()


def _get_session(server, instance):
    try:
        return server.sessions.get(session_name=instance)
    except Exception:
        return None


def _get_or_create_window(session, window_name):
    try:
        return session.windows.get(window_name=window_name)
    except Exception:
        return session.new_window(window_name=window_name)


# ---------------------------------------------------------------------------
# Service operations
# ---------------------------------------------------------------------------

def start_service(service_id, service_cfg, instance, project_root):
    """Send the service start command to its tmux window/pane. Returns pane or None."""
    cmd = service_cfg.get("cmd")
    if not cmd:
        print(f"  No cmd for service '{service_id}'", file=sys.stderr)
        return None

    try:
        server = _tmux_server()
        session = _get_session(server, instance)
        if not session:
            print(f"  tmux session '{instance}' not found — is yantra active?", file=sys.stderr)
            return None

        window = _get_or_create_window(session, service_id)
        pane = window.panes[0]

        if project_root:
            pane.send_keys(f"cd {project_root}", enter=True)
        pane.send_keys(cmd, enter=True)
        return pane

    except ImportError:
        # libtmux not installed — degrade gracefully
        print(f"  [libtmux unavailable] would run in tmux: {cmd}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"  Error starting '{service_id}': {e}", file=sys.stderr)
        return None


def stop_service(service_id, service_cfg, instance):
    """Send C-c to the service pane, then brief wait."""
    try:
        server = _tmux_server()
        session = _get_session(server, instance)
        if not session:
            return False

        try:
            window = session.windows.get(window_name=service_id)
        except Exception:
            return True  # window doesn't exist → already stopped

        pane = window.panes[0]
        pane.cmd("send-keys", "C-c")
        time.sleep(0.8)
        return True

    except ImportError:
        print(f"  [libtmux unavailable] would stop: {service_id}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"  Error stopping '{service_id}': {e}", file=sys.stderr)
        return False


def build_service(service_id, service_cfg, project_root):
    """Run the build command in a subprocess. Returns True on success."""
    build_cfg = service_cfg.get("build", {})
    cmd = build_cfg.get("cmd") if isinstance(build_cfg, dict) else str(build_cfg)
    if not cmd:
        print(f"  No build.cmd for service '{service_id}'", file=sys.stderr)
        return False

    print(f"  [build] {service_id}: {cmd}")
    result = subprocess.run(cmd, shell=True, cwd=project_root or None)
    return result.returncode == 0


def run_health_check(service_id, service_cfg, project_root):
    """Invoke healthcheck.py with appropriate args. Returns True if healthy."""
    health = service_cfg.get("health")
    if not health:
        return True  # No healthcheck configured → assume OK

    hc_script = str(Path(get_yantra_home()) / "impl" / "python" / "healthcheck.py")
    hc_type = health.get("type", "port")
    timeout = str(health.get("timeout", 30))

    if hc_type == "port":
        host = health.get("host", "localhost")
        port = str(health.get("port", 8080))
        cmd = ["python3", hc_script, "port", "--host", host, "--port", port, "--timeout", timeout]

    elif hc_type == "http":
        url = health.get("url", f"http://localhost:{health.get('port', 8080)}/health")
        cmd = ["python3", hc_script, "http", "--url", url, "--timeout", timeout]
        if health.get("expect"):
            cmd += ["--expect", str(health["expect"])]

    elif hc_type == "log_pattern":
        cmd = [
            "python3", hc_script, "log_pattern",
            "--session", os.environ.get("YANTRA_INSTANCE", ""),
            "--window", service_id,
            "--pane", "0",
            "--pattern", str(health.get("pattern", "started")),
            "--timeout", timeout,
        ]
    else:
        return True  # Unknown type → skip

    result = subprocess.run(cmd)
    return result.returncode == 0


def get_service_status(instance):
    """Return dict {svc_id: 'running'|'stopped'} by inspecting tmux pane commands."""
    try:
        server = _tmux_server()
        session = _get_session(server, instance)
        if not session:
            return {}

        status = {}
        for window in session.windows:
            name = window.window_name
            if name in ("shell", "logs", "bubble", "main"):
                continue
            result = subprocess.run(
                ["tmux", "display-message", "-p", "-t", f"{instance}:{name}", "#{pane_current_command}"],
                capture_output=True, text=True,
            )
            cmd = result.stdout.strip()
            # Idle shells signal no process running under that window
            status[name] = "stopped" if cmd in ("bash", "zsh", "sh", "fish", "") else "running"

        return status
    except ImportError:
        return {}
    except Exception as e:
        print(f"Error getting service status: {e}", file=sys.stderr)
        return {}


# ---------------------------------------------------------------------------
# State file (${YANTRA_CONFIG}/sessions/<instance>.state.json)
# ---------------------------------------------------------------------------

def _state_file(instance):
    return Path(get_yantra_config()) / "sessions" / f"{instance}.state.json"


def read_state(instance):
    f = _state_file(instance)
    if f.exists():
        try:
            with open(f) as fh:
                return json.load(fh)
        except Exception:
            return {}
    return {}


def write_state(instance, state):
    f = _state_file(instance)
    f.parent.mkdir(parents=True, exist_ok=True)
    with open(f, "w") as fh:
        json.dump(state, fh, indent=2)


# ---------------------------------------------------------------------------
# Audit helper
# ---------------------------------------------------------------------------

def _write_audit(instance, context, cmd_str, exit_code, duration_ms, rec_type="system"):
    audit_script = str(Path(get_yantra_home()) / "impl" / "python" / "audit.py")
    subprocess.run(
        [
            "python3", audit_script, "write",
            "--instance", instance,
            "--cmd", cmd_str,
            "--exit", str(exit_code),
            "--duration", str(duration_ms),
            "--type", rec_type,
        ],
        capture_output=True,
    )


# ---------------------------------------------------------------------------
# Registry helper (inline — avoids circular import with registry.py)
# ---------------------------------------------------------------------------

def _load_registry():
    import yaml

    path = Path(get_yantra_config()) / "registry.yml"
    if not path.exists():
        return {"instances": {}}
    try:
        with open(path) as f:
            return yaml.safe_load(f) or {"instances": {}}
    except Exception:
        return {"instances": {}}


# ---------------------------------------------------------------------------
# Command handlers
# ---------------------------------------------------------------------------

def cmd_start(args):
    instance = os.environ.get("YANTRA_INSTANCE", "")
    services = load_services(args.context)
    if not services:
        print("No services found in services.yml", file=sys.stderr)
        sys.exit(1)

    order = resolve_start_order(services, target=args.service, group=getattr(args, "group", None))
    if not order:
        print("No services selected to start (check auto_start or --service/--group)", file=sys.stderr)
        sys.exit(0)

    registry = _load_registry()
    project_root = registry.get("instances", {}).get(instance, {}).get("local_path", "")
    state = read_state(instance)

    for svc_id in order:
        svc_cfg = services.get(svc_id)
        if not svc_cfg:
            print(f"  '{svc_id}' not found in services.yml — skipping", file=sys.stderr)
            continue

        print(f"  starting {svc_id}...")
        t0 = time.time()
        start_service(svc_id, svc_cfg, instance, project_root)
        ok = run_health_check(svc_id, svc_cfg, project_root)
        duration_ms = int((time.time() - t0) * 1000)

        symbol = "✓" if ok else "✗"
        print(f"  {symbol} {svc_id} ({'ready' if ok else 'health check failed'}) {duration_ms}ms")

        state[svc_id] = {
            "state": "running" if ok else "failed",
            "started_at": datetime.now(timezone.utc).isoformat(),
        }

        if instance:
            _write_audit(instance, args.context, f"start {svc_id}", 0 if ok else 1, duration_ms)

        if not ok:
            ans = input("  Continue starting remaining services? [y/N] ").strip().lower()
            if ans != "y":
                write_state(instance, state)
                sys.exit(1)

    write_state(instance, state)


def cmd_stop(args):
    instance = os.environ.get("YANTRA_INSTANCE", "")
    services = load_services(args.context)

    if getattr(args, "all", False) or not args.service:
        order = resolve_stop_order(services)
    else:
        order = resolve_stop_order(services, target=args.service)

    state = read_state(instance)

    for svc_id in order:
        svc_cfg = services.get(svc_id, {})
        print(f"  stopping {svc_id}...")
        ok = stop_service(svc_id, svc_cfg, instance)
        symbol = "✓" if ok else "✗"
        print(f"  {symbol} {svc_id}")
        if ok:
            state[svc_id] = {"state": "stopped"}

    write_state(instance, state)


def cmd_status(args):
    instance = os.environ.get("YANTRA_INSTANCE", "")
    services = load_services(args.context)
    tmux_status = get_service_status(instance)
    state = read_state(instance)

    result = {}
    for svc_id in services:
        # Prefer live tmux observation; fall back to persisted state
        live = tmux_status.get(svc_id)
        saved = state.get(svc_id, {}).get("state", "stopped")
        result[svc_id] = live if live else saved

    if args.json:
        print(json.dumps(result))
        return

    for svc_id, status in result.items():
        icon = "●" if status == "running" else ("!" if status == "failed" else "○")
        print(f"  {icon}  {svc_id:<24}  {status}")


def cmd_restart(args):
    instance = os.environ.get("YANTRA_INSTANCE", "")
    services = load_services(args.context)

    if args.service:
        stop_order = resolve_stop_order(services, target=args.service)
        start_order = list(reversed(stop_order))
    else:
        stop_order = resolve_stop_order(services)
        start_order = resolve_start_order(services)

    registry = _load_registry()
    project_root = registry.get("instances", {}).get(instance, {}).get("local_path", "")
    state = read_state(instance)

    print("  stopping...")
    for svc_id in stop_order:
        svc_cfg = services.get(svc_id, {})
        stop_service(svc_id, svc_cfg, instance)
        state[svc_id] = {"state": "stopped"}
        print(f"  ○ {svc_id}")

    print("  starting...")
    for svc_id in start_order:
        svc_cfg = services.get(svc_id, {})
        start_service(svc_id, svc_cfg, instance, project_root)
        ok = run_health_check(svc_id, svc_cfg, project_root)
        state[svc_id] = {"state": "running" if ok else "failed"}
        symbol = "✓" if ok else "✗"
        print(f"  {symbol} {svc_id}")

    write_state(instance, state)


def cmd_build(args):
    instance = os.environ.get("YANTRA_INSTANCE", "")
    services = load_services(args.context)

    target = args.service
    if not target:
        print("--service is required for build", file=sys.stderr)
        sys.exit(2)
    if target not in services:
        print(f"Service '{target}' not found in services.yml", file=sys.stderr)
        sys.exit(1)

    registry = _load_registry()
    project_root = registry.get("instances", {}).get(instance, {}).get("local_path", "")

    _, dependents = resolve_build_cascade(services, target)

    # 1. Stop dependents (reverse topo order so leaves first)
    for dep in reversed(dependents):
        print(f"  stopping dependent: {dep}")
        stop_service(dep, services.get(dep, {}), instance)

    # 2. Stop the build target itself
    print(f"  stopping {target}...")
    stop_service(target, services[target], instance)

    # 3. Build
    t0 = time.time()
    ok = build_service(target, services[target], project_root)
    duration_ms = int((time.time() - t0) * 1000)

    if not ok:
        print(f"  ✗ build failed", file=sys.stderr)
        if instance:
            _write_audit(instance, args.context, f"build {target}", 1, duration_ms)
        sys.exit(1)
    print(f"  ✓ build succeeded ({duration_ms}ms)")

    # 4. Start target + health check
    print(f"  starting {target}...")
    start_service(target, services[target], instance, project_root)
    if not run_health_check(target, services[target], project_root):
        print(f"  ✗ {target} health check failed after build", file=sys.stderr)
        if instance:
            _write_audit(instance, args.context, f"build {target}", 1, duration_ms)
        sys.exit(1)
    print(f"  ✓ {target} ready")

    # 5. Restart dependents in forward order
    for dep in dependents:
        dep_cfg = services.get(dep, {})
        print(f"  starting dependent: {dep}")
        start_service(dep, dep_cfg, instance, project_root)
        dep_ok = run_health_check(dep, dep_cfg, project_root)
        print(f"  {'✓' if dep_ok else '✗'} {dep}")

    if instance:
        _write_audit(instance, args.context, f"build {target}", 0, duration_ms)


def cmd_wait(args):
    """Block until a service health check passes or timeout."""
    services = load_services(args.context)
    svc_cfg = services.get(args.service)
    if not svc_cfg:
        print(f"Service '{args.service}' not found", file=sys.stderr)
        sys.exit(1)

    ok = run_health_check(args.service, svc_cfg, "")
    sys.exit(0 if ok else 1)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        prog="orchestrate.py",
        description="yantra service orchestration",
    )
    sub = parser.add_subparsers(dest="command", metavar="<command>")
    sub.required = True

    def _common(p):
        p.add_argument("--context", required=True, help="Context type (directory name under contexts/)")

    p = sub.add_parser("start", help="Start services")
    _common(p)
    p.add_argument("--service", help="Specific service id")
    p.add_argument("--group", help="Service group name")

    p = sub.add_parser("stop", help="Stop services")
    _common(p)
    p.add_argument("--service")
    p.add_argument("--group")
    p.add_argument("--all", action="store_true")

    p = sub.add_parser("status", help="Show service status")
    _common(p)
    p.add_argument("--json", action="store_true")

    p = sub.add_parser("restart", help="Restart services")
    _common(p)
    p.add_argument("--service")

    p = sub.add_parser("build", help="Build and restart a service")
    _common(p)
    p.add_argument("--service")
    p.add_argument("--group")

    p = sub.add_parser("wait", help="Wait for a service health check to pass")
    _common(p)
    p.add_argument("--service", required=True)
    p.add_argument("--timeout", type=int, default=30)

    args = parser.parse_args()

    dispatch = {
        "start": cmd_start,
        "stop": cmd_stop,
        "status": cmd_status,
        "restart": cmd_restart,
        "build": cmd_build,
        "wait": cmd_wait,
    }
    dispatch[args.command](args)


if __name__ == "__main__":
    main()
