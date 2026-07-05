# yantra — AI codebase context

This file is for AI assistants working on this repository. Read it before making any changes.

---

## What this is

yantra is a terminal-native development OS: a single repository that manages multiple project
contexts as isolated tmux sessions. `yukti` is its Python CLI. Projects are consumers — their
code lives in separate repos; yantra holds only their workflow config (services, layouts, watchers).
Machine-specific paths and credentials live in `~/.config/yantra/` and never enter this repo.

---

## Repository map

| Path | Purpose |
|------|---------|
| `bin/yukti` | Python CLI. All subcommands. The single entry point for everything. |
| `bin/switch` | Bash fzf picker. Prints chosen instance name to stdout only. |
| `bin/orchestrate` | Bash shim → `impl/python/orchestrate.py` or `impl/go/orchestrate` |
| `bin/watch-logs` | Bash shim → `impl/python/watch_logs.py` or `impl/go/watch-logs` |
| `bin/healthcheck` | Bash shim → `impl/python/healthcheck.py` or `impl/go/healthcheck` |
| `init.sh` | Sourced (not executed) by user shell. Sets env, PATH, audit hooks. |
| `install.sh` | Bootstrap. Checks deps, creates `~/.config/yantra/`, pip installs. |
| `lib/context.sh` | Core: `yantra_activate_instance`, `yantra_get_instance_info`, `yantra_tmuxp_load` |
| `lib/session.sh` | KV store: `yantra_set`, `yantra_get`, `yantra_session_list` |
| `lib/audit.sh` | Hooks: `_yantra_cmd_precmd`, `yantra_audit_write`, `yantra_audit_note` |
| `lib/health.sh` | Polling: `yantra_wait_port`, `yantra_wait_http`, `yantra_wait_log_pattern` |
| `lib/bubble.sh` | Alert pane: `yantra_bubble_write`, `yantra_bubble_start` |
| `lib/remote.sh` | SSH: `yantra_remote_exec`, `yantra_remote_attach`, `yantra_bootstrap_remote` |
| `impl/python/orchestrate.py` | Service lifecycle: start/stop/build with topological dep ordering |
| `impl/python/healthcheck.py` | Health checks: port / http / log_pattern |
| `impl/python/watch_logs.py` | Log stream watching → bubble pane writer |
| `impl/python/audit.py` | Audit JSONL: write, annotate (note), query with filters |
| `impl/python/registry.py` | Registry CRUD — used by shell scripts that can't import Python |
| `impl/python/requirements.txt` | pyyaml, requests, libtmux, rich, python-dateutil |
| `contexts/_base/` | Inherited by all contexts: status bar, base tasks, audit patterns |
| `contexts/<type>/` | Context templates: context.env, services.yml or ops.yml, watchers.yml, tmuxp.yml, Taskfile.yml |
| `templates/` | Starter scaffolds — `yukti add` copies these when registering a new context |
| `~/.config/yantra/` | Machine-local (NOT in repo): registry.yml, secrets/, sessions/, audit/ |

---

## Architecture

```
Shell layer  (init.sh, switch, install.sh)
  — glue only, no logic, calls yukti or lib functions

yukti  (bin/yukti, Python + argparse)
  — routing, output formatting, user interaction

impl/python/*.py  (orchestrate, healthcheck, watch_logs, audit, registry)
  — all service logic, tmux interaction, file I/O

lib/*.sh  (context, session, audit, health, bubble, remote)
  — shell functions sourced into user's shell or called by init.sh

Runtime: libtmux / tmux / tmuxp / process-compose
```

### Key data flow — `yukti go wscs-dev`

```
bin/yukti cmd_go("wscs-dev")
  → lib/context.sh yantra_get_instance_info("wscs-dev")
      reads ~/.config/yantra/registry.yml
      exports: YANTRA_INSTANCE, YANTRA_LABEL, YANTRA_CONTEXT_TYPE,
               YANTRA_INSTANCE_BG/FG, PROJECT_ROOT, YANTRA_REMOTE_HOST
  → lib/context.sh yantra_load_context_env("wscloudservices")
      sources contexts/wscloudservices/context.env
  → lib/context.sh yantra_load_secrets("wscs-dev")
      sources ~/.config/yantra/secrets/wscs-dev.env (if exists)
  → check tmux for existing session named "wscs-dev"
      if exists  → tmux attach-session -t wscs-dev
      if not     → tmuxp load contexts/wscloudservices/tmuxp.yml
```

### Key data flow — `yukti up svc1`

```
bin/yukti cmd_up("svc1")
  → subprocess: orchestrate.py start --context wscloudservices --service svc1
      reads contexts/wscloudservices/services.yml
      resolves dep order
      libtmux: creates window "svc1" in session YANTRA_INSTANCE
      runs health check via healthcheck.py
      writes audit record via audit.py write --type auto
```

---

## Environment variables

| Variable | Set by | Used by |
|----------|--------|---------|
| `YANTRA_HOME` | `init.sh` (from script location) | Everything. Always `~/yantra`. |
| `YANTRA_CONFIG` | `init.sh` | Everything. Always `~/.config/yantra`. |
| `YANTRA_IMPL` | `.mise.toml` | Shims: select `python` or `go` backend |
| `YANTRA_INSTANCE` | `yantra_activate_instance` | Audit, session KV, tmux targeting |
| `YANTRA_LABEL` | `yantra_get_instance_info` | tmux status bar label |
| `YANTRA_CONTEXT_TYPE` | `yantra_get_instance_info` | Context file path resolution |
| `YANTRA_INSTANCE_BG` | `yantra_color_to_hex` | tmux status bar background hex |
| `YANTRA_INSTANCE_FG` | `yantra_color_to_hex` | tmux status bar foreground hex |
| `YANTRA_STATUS_LINE` | `yukti` + `orchestrate.py` | tmux status-right live content |
| `PROJECT_ROOT` | `yantra_get_instance_info` | Commands in service tmux panes |

---

## Naming conventions

| Pattern | Scope |
|---------|-------|
| `YANTRA_*` | All environment variables |
| `yantra_*()` | Public shell functions in `lib/*.sh` |
| `_yantra_*()` | Private shell functions (hooks, internal helpers) |
| `cmd_*()` | yukti subcommand handlers in `bin/yukti` |
| `contexts/<type>/` | Context type name, kebab-case |
| instance id | `<context-abbrev>-<env>` — e.g. `wscs-dev`, `wscs-staging`, `vidheya` |

---

## Contracts — never break without updating all callers

### Python impl CLI (used by shims and yukti subprocess calls)

```
orchestrate.py start   --context <name> [--service <id>] [--group <grp>]
orchestrate.py stop    --context <name> [--service <id>] [--group <grp>]
orchestrate.py status  --context <name> [--json]
orchestrate.py restart --context <name> [--service <id>]
orchestrate.py build   --context <name> [--service <id>] [--group <grp>]
orchestrate.py wait    --context <name> --service <id> [--timeout <secs:30>]

healthcheck.py port        --host <h> --port <p> [--timeout <secs:30>]
healthcheck.py http        --url <u> [--expect <pattern>] [--timeout <secs:30>]
healthcheck.py log_pattern --session <s> --window <w> --pane <p> --pattern <p> [--timeout <secs:60>]

watch_logs.py  --config <path> --instance <name> --context-dir <path>

audit.py write  --instance <n> --cmd "..." --exit <code> --duration <ms>
                [--type auto|manual|system] [--summary "..."] [--window w] [--pane p] [--blast h|m|l]
audit.py note   --instance <n> --text "..."
audit.py query  --instance <n> [--since 2h|YYYY-MM-DD] [--type t] [--search s]
                [--blast h|m|l] [--exit code] [--annotated] [--json]

registry.py list  [--json]
registry.py get   <name>
registry.py add   <name> <yaml-string>
registry.py remove <name>
```

Exit codes: 0 = success, 1 = failure/timeout, 2 = config/usage error.

### YAML schema fields that Python parsers depend on

**services.yml**: `id`, `cmd`, `depends_on[]`, `ready.type`, `ready.url|port|pattern`, `ready.timeout`,
`auto_start`, `groups[]`, `build.cmd`

**ops.yml**: `id`, `kind` (watcher|shell|check|task), `cmd`, `remote`, `blast_radius`,
`confirm`, `vars_required[]`, `restart_on_exit`

**watchers.yml**: `watchers[].id`, `watchers[].source.type` (service|op|file|ssh_pipe),
`watchers[].source.id`, `watchers[].keywords[].pattern`, `watchers[].keywords[].action[]`,
`bubble.pane`, `bubble.format`

**registry.yml**: `instances.<name>.context`, `instances.<name>.color`, `instances.<name>.label`,
`instances.<name>.local_path` OR `instances.<name>.remote.{host,mode,path}`,
`instances.<name>.env`

### Storage paths (hardcoded expectations throughout the codebase)

```
~/.config/yantra/registry.yml
~/.config/yantra/secrets/<instance>.env
~/.config/yantra/sessions/<instance>.env
~/.config/yantra/audit/<instance>/YYYY-MM-DD.jsonl
~/.config/yantra/last
```

---

## How to add things

### New yukti subcommand

```python
# 1. In bin/yukti setup_parser():
p_mycommand = subparsers.add_parser("mycommand", help="does X")
p_mycommand.add_argument("--option", help="...")

# 2. Add handler:
def cmd_mycommand(args):
    yantra_home = get_yantra_home()
    # use load_registry(), get_instance(), subprocess to call impl scripts
    pass

# 3. Add to dispatch dict:
"mycommand": cmd_mycommand,
```

Update `README.md` section `## yukti CLI Reference` with usage, options table, examples.

### New context type

```bash
cp -r templates/services-project contexts/mycontext   # or devops-project template
# Edit: context.env, services.yml or ops.yml, watchers.yml, tmuxp.yml, Taskfile.yml
# Register: yukti add mycontext-dev --context mycontext --path ~/dev/myproject --color cyan
```

No changes to `bin/yukti` or `impl/python/` needed — context files are data, not code.

### New health check type

1. Add argparse subparser + handler function in `impl/python/healthcheck.py`
2. Add `yantra_wait_<type>()` in `lib/health.sh`
3. Handle `type: <new-type>` in `orchestrate.py` `run_health_check()` dispatch

### New audit-ignore or audit-pattern rule

- Global: edit `contexts/_base/audit-ignore.yml` or `contexts/_base/audit-patterns.yml`
- Context-specific: add `contexts/<type>/audit-patterns.yml` (same schema, merged at query time)

### Go migration (one binary at a time)

```bash
# 1. Build Go binary with identical CLI contract (same flags, exit codes, stdout format)
# 2. Test in parallel:
YANTRA_IMPL=go yukti up svc1
# 3. When stable, set default in .mise.toml:
#    YANTRA_IMPL = "go"
# 4. Shims in bin/ never need to change.
```

---

## Common code patterns

### Read registry in Python
```python
import yaml, os
config = os.environ.get("YANTRA_CONFIG", os.path.expanduser("~/.config/yantra"))
with open(os.path.join(config, "registry.yml")) as f:
    registry = yaml.safe_load(f) or {}
instances = registry.get("instances", {})
instance = instances.get("wscs-dev", {})
```

### Write audit record from Python impl script
```python
import subprocess, os, sys

def write_audit(cmd, exit_code, duration_ms, summary=None, blast=None):
    args = [
        sys.executable,
        os.path.join(os.environ["YANTRA_HOME"], "impl/python/audit.py"),
        "write",
        "--instance", os.environ.get("YANTRA_INSTANCE", "unknown"),
        "--cmd", cmd,
        "--exit", str(exit_code),
        "--duration", str(duration_ms),
        "--type", "auto",
    ]
    if summary:
        args += ["--summary", summary]
    if blast:
        args += ["--blast", blast]
    subprocess.run(args, check=False)
```

### Run health check from orchestrate.py
```python
import subprocess, sys, os

def run_health_check(ready_config, timeout=30):
    hc = os.path.join(os.environ["YANTRA_HOME"], "bin", "healthcheck")
    rtype = ready_config.get("type", "port")
    if rtype == "port":
        cmd = [hc, "port", "--host", ready_config.get("host", "localhost"),
               "--port", str(ready_config["port"]), "--timeout", str(timeout)]
    elif rtype == "http":
        cmd = [hc, "http", "--url", ready_config["url"], "--timeout", str(timeout)]
        if "expect" in ready_config:
            cmd += ["--expect", ready_config["expect"]]
    result = subprocess.run(cmd)
    return result.returncode == 0
```

### Use libtmux to interact with a pane
```python
import libtmux

server = libtmux.Server()
session = server.find_where({"session_name": os.environ["YANTRA_INSTANCE"]})
if session:
    window = session.find_where({"window_name": "svc1"})
    if window:
        pane = window.panes[0]
        pane.send_keys("./run.sh svc1", enter=True)
```

### Source context in bash (for shell scripts)
```bash
source "${YANTRA_HOME}/lib/context.sh"
yantra_activate_instance "wscs-dev"
# Now: YANTRA_INSTANCE, PROJECT_ROOT, YANTRA_CONTEXT_TYPE, etc. are exported
echo "Running in: $PROJECT_ROOT"
```

---

## Anti-patterns

- **Do NOT** use `set -euo pipefail` in sourced `lib/*.sh` files — errors kill the user's parent shell
- **Do NOT** put machine paths or credentials in `contexts/*/context.env` — version controlled
- **Do NOT** put absolute paths in `contexts/*/tmuxp.yml` — use `${PROJECT_ROOT}` from registry
- **Do NOT** add logic to `init.sh` — glue only; logic belongs in `lib/` or `impl/python/`
- **Do NOT** change YAML schemas without updating all Python parsers that read those fields
- **Do NOT** hardcode `~/yantra` anywhere — always `${YANTRA_HOME}`
- **Do NOT** write to `~/.config/yantra/` from context config files — only `yukti` and `install.sh` own that directory
- **Do NOT** call `impl/python/*.py` directly from contexts or external scripts — always use the shims in `bin/`
- **Do NOT** assume `YANTRA_INSTANCE` is set — check with `[[ -z "${YANTRA_INSTANCE:-}" ]]` before using it

---

## Testing without a full tmux environment

Most Python impl files degrade gracefully when tmux is not available (they print what they would do).
For unit testing individual functions:

```bash
# Test audit write/query without tmux:
YANTRA_HOME=. YANTRA_CONFIG=/tmp/test-yantra python3 impl/python/audit.py write \
  --instance test --cmd "echo hi" --exit 0 --duration 100
YANTRA_HOME=. YANTRA_CONFIG=/tmp/test-yantra python3 impl/python/audit.py query --instance test

# Test health checks:
python3 impl/python/healthcheck.py http --url https://httpbin.org/status/200 --timeout 5
python3 impl/python/healthcheck.py port --host localhost --port 9999 --timeout 3

# Test registry:
YANTRA_CONFIG=/tmp/test-yantra python3 impl/python/registry.py list
```

---

## Full spec

`yantra.md` in the repo root contains the complete design specification: all architectural
decisions, rationale, open decisions, and future work. Read it for context on any non-obvious
design choice in the codebase.
