# yantra

> Terminal-native development operating system. One repository, all your workflows.

---

## Table of Contents

1. [Overview](#overview)
2. [Naming](#naming)
3. [Core Concepts](#core-concepts)
4. [Chosen Tool Stack](#chosen-tool-stack)
5. [Architecture](#architecture)
6. [Repo Structure](#repo-structure)
7. [Storage Layout](#storage-layout)
8. [Configuration Schemas](#configuration-schemas)
9. [yukti CLI](#yukti-cli)
10. [Base Layer](#base-layer)
11. [Remote Execution](#remote-execution)
12. [Multi-Instance Support](#multi-instance-support)
13. [Orientation & Self-Awareness](#orientation--self-awareness)
14. [Init & Bootstrap](#init--bootstrap)
15. [Audit Trail](#audit-trail)
16. [Session KV Store](#session-kv-store)
17. [Service Orchestration — Project 1 Pattern](#service-orchestration--project-1-pattern)
18. [Infra Operations — Project 2 Pattern](#infra-operations--project-2-pattern)
19. [Implementation Language](#implementation-language)
20. [Example Contexts](#example-contexts)
21. [Open Decisions & Future Work](#open-decisions--future-work)

---

## Overview

**yantra** is a terminal-native development operating system — a single repository that manages the complete workflow environment across multiple projects and infrastructure contexts. It provides opinionated, config-driven tooling for activating development environments, orchestrating services, monitoring logs, and tracking operations — from the terminal.

**yukti** is yantra's command runner: the single CLI entry point through which all yantra functionality is accessed.

### Goals

1. One command to enter any project context, local or remote
2. Ordered service startup with health-check conditions, interruptible at any point
3. Always know where you are — orientation at near-zero cognitive cost
4. Multiple instances of the same context type running simultaneously
5. Complete audit trail of manual and automatic operations
6. Portable — clone + register = working environment on any machine

### Design Principles

- **Config over code** — environment behaviour is declared in YAML and env files, not scripts
- **Contracts over implementations** — CLI interfaces are stable; underlying implementations (Python → Go) are swappable without changing anything else
- **Engine vs consumer** — yantra is the engine; project repos are consumers and contain no yantra-specific config
- **Machine-local secrets** — credentials and filesystem paths never enter the repo
- **Base layer inheritance** — common behaviour defined once in `_base/`, inherited automatically by all contexts
- **Minimal remote footprint** — remote nodes need only what the project requires; full yantra install is optional

---

## Naming

| Name | Meaning | Role |
|------|---------|------|
| **yantra** | Sanskrit: instrument, machine | The repository and system |
| **yukti** | Sanskrit: method, technique | The CLI command runner |

Subsystem names, config keys, and file names use plain English. The Sanskrit theme is established at the top level; extending it to other concepts is an open decision.

---

## Core Concepts

| Term | Definition |
|------|-----------|
| **context** | A template defining how a class of project runs. Lives in `yantra/contexts/<type>/`. Shared across machines. Version controlled. |
| **instance** | A specific deployment of a context type. Registered in `~/.config/yantra/registry.yml`. Machine-local. |
| **session** | A live tmux session corresponding to one active instance. Named by instance id. |
| **workspace** | The tmux window and pane layout for a session, defined in `tmuxp.yml`. |
| **bubble pane** | A dedicated tmux pane in each session that receives aggregated errors and alerts from all log watchers. |
| **KV store** | Per-session ephemeral key-value storage (`yukti set` / `yukti get`). Used for auth tokens and transient runtime config. |

---

## Chosen Tool Stack

| Tool | Role | Why chosen |
|------|------|-----------|
| **mise** | Runtime version management | Replaces nvm/rbenv/pyenv; per-context `.mise.toml`; works on both local and remote |
| **task** (Taskfile) | Task runner | YAML-native, `includes:` for base task inheritance, variable substitution |
| **tmux** | Terminal multiplexer | Session isolation, scriptable via control mode, always-on status bar |
| **tmuxp** | tmux session declarator | YAML-defined layouts; `before_script` hook for base config injection |
| **fzf** | Fuzzy picker | Instance switcher, interactive command palette |
| **zoxide** | Smart directory navigation | Learns project paths; `z <name>` jumps to registered locations |
| **process-compose** | Service orchestration engine | YAML deps, health checks (port / http / cmd), graceful reverse shutdown, REST API |
| **libtmux** (Python) | tmux object model | Panes and windows as Python objects; drives status bar updates |
| **Shell** | Glue layer only | `init.sh`, `switch`, `install.sh` — no orchestration logic |

**Evaluated and not chosen:**

| Tool | Reason not chosen |
|------|------------------|
| overmind | tmux integration but no health checks or dependency ordering |
| mprocs | Own TUI, not tmux-integrated, no health checks |
| Go (now) | Strong candidate to replace Python later; deferred for development speed |
| Nushell | No async primitives, no tmux library |
| Deno/TS | Thin process orchestration ecosystem |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Shell layer                                                  │
│  init.sh  ·  switch  ·  install.sh                           │
│  Stable forever. Calls yukti. Contains no logic.             │
├──────────────────────────────────────────────────────────────┤
│  yukti  (bin/yukti)                                          │
│  Single entry point. Routes subcommands. Owns audit writes.  │
├─────────────────────────┬────────────────────────────────────┤
│  Orchestration          │  Observation                       │
│  orchestrate            │  watch-logs                        │
│  healthcheck            │  bubble writer                     │
│  (Python now / Go later)│  (Python now / Go later)           │
├─────────────────────────┴────────────────────────────────────┤
│  process-compose                                             │
│  Dependency ordering · health checks · graceful shutdown     │
├──────────────────────────────────────────────────────────────┤
│  tmux / tmuxp                                                │
│  Session isolation · pane layout · status bar                │
└──────────────────────────────────────────────────────────────┘
```

### Layer responsibilities

**Shell layer** — `init.sh`, `switch`, `install.sh`
- Sources environment, sets PATH, registers shell functions
- Launches tmux sessions via tmuxp
- Never contains orchestration logic; delegates everything to yukti

**yukti** — unified CLI entry point
- Routes all subcommands to the appropriate implementation
- Reads context config and registry
- Owns audit record writes for non-shell events
- Updates tmux session env (status bar, KV store)

**Orchestration layer** — `orchestrate`, `healthcheck`
- Reads `services.yml` or `ops.yml`
- Manages process lifecycle via process-compose
- Executes startup chains with health-check conditions
- Handles graceful reverse-order shutdown on interrupt

**Observation layer** — `watch-logs`, bubble writer
- Reads `watchers.yml`
- Tails log streams (local stdout or SSH pipe)
- Matches keyword patterns, writes matching lines to bubble pane

**process-compose**
- Handles the hard parts: dependency graph, health polling, reverse shutdown
- Exposes REST API queried by yukti for service state
- Used as a library / subprocess; not exposed directly to users

---

## Repo Structure

```
yantra/
├── bin/
│   ├── yukti              # main CLI entry point
│   ├── switch             # fzf instance picker (also callable as yukti go)
│   ├── orchestrate        # shim → impl/python or impl/go
│   ├── watch-logs         # shim → impl/python or impl/go
│   └── healthcheck        # shim → impl/python or impl/go
│
├── impl/
│   ├── python/
│   │   ├── orchestrate.py
│   │   ├── watch_logs.py
│   │   ├── healthcheck.py
│   │   └── audit.py
│   └── go/                # empty now; filled in during Go migration
│
├── lib/
│   ├── context.sh         # load_context(), resolve_path(), merge_env()
│   ├── remote.sh          # bootstrap_remote(), ssh_session_exists()
│   ├── health.sh          # wait_for_port(), wait_for_http(), wait_for_log_pattern()
│   ├── bubble.sh          # keyword matcher → bubble pane writer
│   ├── session.sh         # KV store: yukti set / yukti get
│   └── audit.sh           # shell hook: precmd/preexec capture
│
├── contexts/
│   ├── _base/
│   │   ├── context.env        # shared defaults: YANTRA_HOME, YANTRA_VERSION
│   │   ├── tmux.status.conf   # status bar format — loaded by every session
│   │   ├── Taskfile.base.yml  # where, ps, log, note, set, get — always available
│   │   ├── watchers.base.yml  # universal patterns: OOM, panic, segfault
│   │   ├── audit-patterns.yml # auto-summary rules: terraform, kubectl, build, etc.
│   │   └── audit-ignore.yml   # noise filter: ls, cat, cd, pwd, echo, etc.
│   │
│   ├── wscloudservices/       # example: multi-service development context
│   │   ├── context.env
│   │   ├── services.yml
│   │   ├── watchers.yml
│   │   ├── tmuxp.yml
│   │   ├── Taskfile.yml
│   │   └── gql/               # predefined GraphQL query files
│   │
│   └── vidheya/               # example: homelab DevOps context
│       ├── context.env
│       ├── ops.yml
│       ├── watchers.yml
│       ├── tmuxp.yml
│       └── Taskfile.yml
│
├── templates/
│   ├── services-project/      # scaffold for service-dev contexts (Project 1 pattern)
│   ├── devops-project/        # scaffold for infra/ops contexts (Project 2 pattern)
│   └── dev-app-project/       # scaffold for app+deps contexts (Project 3 pattern)
│
├── init.sh                    # sourced by user shell / .zshrc
├── install.sh                 # bootstrap: local and/or remote
├── .mise.toml                 # yantra's own runtime versions (python, go)
└── .gitignore
```

---

## Storage Layout

| Location | In repo? | Contains |
|----------|---------|---------|
| `~/yantra/` | Yes — version controlled | Engine, contexts, templates, implementations |
| `~/.config/yantra/registry.yml` | No — machine-local | Instance definitions: paths, hosts, colors, modes |
| `~/.config/yantra/secrets/<instance>.env` | No — machine-local | Credentials and tokens per instance |
| `~/.config/yantra/sessions/<instance>.env` | No — ephemeral | Session KV store |
| `~/.config/yantra/audit/<instance>/YYYY-MM-DD.jsonl` | No — machine-local | Audit log files |
| `~/.config/yantra/last` | No — machine-local | Last active instance id |
| Remote `~/yantra/` | Optional | Full yantra install on remote node (full mode only) |
| Remote `~/.config/yantra/` | Optional | Remote-local registry and secrets (full mode only) |

**Rule:** anything that varies by machine or contains credentials lives exclusively outside the repo.

---

## Configuration Schemas

### `registry.yml` — machine-local, never committed

```yaml
instances:
  wscs-dev:
    context: wscloudservices       # → yantra/contexts/wscloudservices/
    label: dev
    color: green                   # tmux status bar color for this instance
    local_path: /Users/rusahu/dev/ECP/.../experience-api-insurtech-shopping
    env:
      INSTANCE_NAME: dev
      SVC1_PORT: "8081"

  wscs-staging:
    context: wscloudservices
    label: staging
    color: yellow
    remote:
      host: staging.company.com
      mode: thin                   # thin | full
      path: ~/app
    env:
      INSTANCE_NAME: staging
      SVC1_PORT: "8081"

  vidheya:
    context: vidheya
    label: homelab
    color: blue
    remote:
      host: ubuntu@192.168.1.151
      mode: full
      path: ~/repo/vidheya
```

### `context.env` — committed, no paths, no credentials

```bash
# Logical config only. Paths and credentials injected at runtime from registry + secrets.
CONTEXT_TYPE=wscloudservices
SPLUNK_INDEX=eg-runtime-rcp
SPLUNK_SERVICE=experience-api-insurtech-shopping
SVC1_URL=http://localhost:${SVC1_PORT:-8081}
SVC2_URL=http://localhost:${SVC2_PORT:-8082}
FRONTEND_URL=http://localhost:${FRONTEND_PORT:-3000}
```

### `services.yml` — Project 1 pattern (long-running services)

```yaml
version: 1
groups:
  backend: [svc1, svc2]
  all: [svc1, svc2, frontend]

services:
  - id: svc1
    cmd: ./run.sh svc1
    auto_start: true               # include in yukti up / smart-mode suggestions
    build:
      cmd: ./run.sh build svc1
    ready:
      type: http
      url: ${SVC1_URL}/health
      expect: '"status":"UP"'
      timeout: 60s
    groups: [backend, all]

  - id: svc2
    cmd: ./run.sh svc2
    depends_on: [svc1]
    auto_start: true
    build:
      cmd: ./run.sh build svc2
    ready:
      type: port
      port: 8082
      timeout: 30s
    groups: [backend, all]

  - id: frontend
    cmd: npm run dev
    depends_on: [svc1, svc2]
    auto_start: false              # start manually when needed
    ready:
      type: log_pattern
      pattern: "ready on"
      timeout: 30s
    groups: [all]
```

### `ops.yml` — Project 2 pattern (infra/devops operations)

```yaml
version: 1
ops:
  - id: pod-watch
    kind: watcher                  # long-running, restart on exit
    cmd: kubectl get events -A -w --sort-by=.metadata.creationTimestamp
    remote: ${REMOTE_HOST}
    restart_on_exit: true

  - id: stern-apps
    kind: watcher
    cmd: stern -n ${K8S_NAMESPACE} .
    remote: ${REMOTE_HOST}
    restart_on_exit: true

  - id: k9s
    kind: shell                    # interactive, allocate PTY
    cmd: k9s
    remote: ${REMOTE_HOST}

  - id: cluster-check
    kind: check                    # one-shot, exit code matters, run on demand
    cmd: kubectl get nodes && kubectl get pods -A | grep -v Running
    remote: ${REMOTE_HOST}

  - id: tf-apply
    kind: task                     # one-shot, may require confirm + vars
    cmd: cd ${REMOTE_REPO}/infra/terraform && terraform apply .tfplan
    remote: ${REMOTE_HOST}
    blast_radius: high             # engine enforces confirmation for high blast-radius
    confirm: "Apply terraform changes to live infrastructure?"

  - id: ansible-run
    kind: task
    cmd: ansible-playbook playbooks/${PLAYBOOK}.yml -v
    remote: ${REMOTE_HOST}
    blast_radius: high
    confirm: "Run Ansible playbook '${PLAYBOOK}' against live hosts?"
    vars_required: [PLAYBOOK]      # yukti prompts interactively if not set
```

**`ops.yml` kind discriminator:**

| Kind | Lifecycle | PTY | Restart | Confirm |
|------|-----------|-----|---------|---------|
| `watcher` | Long-running | No | Optional | No |
| `shell` | Long-running | Yes | No | No |
| `check` | One-shot | No | No | No |
| `task` | One-shot | No | No | Optional |

### `watchers.yml` — keyword monitoring

```yaml
version: 1
watchers:
  - id: svc1-errors
    source:
      type: service              # local: attaches to named service stdout
      id: svc1
    keywords:
      - pattern: "ERROR|FATAL|Exception"
        level: error
        action: [highlight, bubble]
      - pattern: "NullPointerException"
        level: critical
        action: [highlight, bubble]

  - id: svc2-errors
    source:
      type: service
      id: svc2
    keywords:
      - pattern: "ERROR|FATAL|timeout"
        level: error
        action: [highlight, bubble]

  - id: remote-k8s
    source:
      type: op                   # remote: attaches to named ops.yml entry stream
      id: pod-watch
    keywords:
      - pattern: "OOMKilled|CrashLoopBackOff|Failed"
        level: critical
        action: [highlight, bubble]

bubble:
  pane: bubble
  max_lines: 300
  format: "[{ts}] [{source}] {level}: {line}"
```

### `tmuxp.yml` — session layout

```yaml
# Base config (status bar, keybindings) injected via before_script.
# This file defines only the window/pane layout.
before_script: tmux source-file "${YANTRA_HOME}/contexts/_base/tmux.status.conf"
session_name: "${YANTRA_INSTANCE}"
windows:
  - window_name: services
    layout: tiled
    panes:
      - {name: svc1,     shell_command: "yukti up svc1"}
      - {name: svc2,     shell_command: "yukti up svc2"}
      - {name: bubble,   shell_command: "echo '[bubble ready]'"}
  - window_name: shell
    panes:
      - shell_command: "exec zsh"
```

### `Taskfile.yml` — project tasks (extends base)

```yaml
version: '3'
includes:
  base:
    taskfile: "${YANTRA_HOME}/contexts/_base/Taskfile.base.yml"
    optional: false
tasks:
  start:
    cmds: [yukti up all]
  build:
    cmds: [yukti build {{.CLI_ARGS}}]
  gql:run:
    requires: {vars: [QUERY]}
    cmds:
      - |
        source "${YANTRA_SESSIONS}/$(yukti where --short).env" 2>/dev/null
        curl -sf -X POST ${SVC1_URL}/graphql \
          -H "Authorization: ${AUTH_TOKEN}" \
          -H "Content-Type: application/json" \
          -d @contexts/wscloudservices/gql/{{.QUERY}}.json | jq .
```

---

## yukti CLI

yukti is the single entry point for all yantra operations. Options and flags are high-level here; precise specs are defined when implementation begins.

### Context & session

| Command | Description |
|---------|-------------|
| `yukti go [instance]` | Activate an instance; fzf picker if no argument given |
| `yukti go --last` | Resume last active instance |
| `yukti ls` | List all registered instances with live status |
| `yukti where` | Show current instance, context type, remote mode |
| `yukti add` | Register a new instance (interactive wizard) |

### Service control (services.yml contexts)

| Command | Description |
|---------|-------------|
| `yukti up [svc\|group\|all]` | Start service(s) in dependency order, health-checked |
| `yukti down [svc\|group\|all]` | Stop service(s) in reverse dependency order |
| `yukti restart [svc\|group]` | Stop then start |
| `yukti build [svc\|group\|all]` | Rebuild + cascade: stops dependents, rebuilds, restarts in order |
| `yukti ps` | Show all services with current health status |

### Ops (ops.yml contexts)

| Command | Description |
|---------|-------------|
| `yukti run <op>` | Execute a named op from `ops.yml` |
| `yukti check [op]` | Run one-shot check ops |

### Observation

| Command | Description |
|---------|-------------|
| `yukti log` | View today's audit log, formatted |
| `yukti log --since 2h` | Time-filtered view |
| `yukti log --type manual` | Manual commands only |
| `yukti log --search <term>` | Full-text search |
| `yukti log --blast high` | High blast-radius operations only |
| `yukti log --json` | Raw JSONL output for piping to `jq` |
| `yukti note "text"` | Annotate the last audit record with a summary |

### Session KV

| Command | Description |
|---------|-------------|
| `yukti set KEY value` | Write a value to session KV store |
| `yukti get KEY` | Read a value from session KV store |

### Bootstrap

| Command | Description |
|---------|-------------|
| `yukti init` | First-time setup: dependencies, config directory |
| `yukti install` | Install or update yantra dependencies |
| `yukti install --remote host [--thin\|--full]` | Bootstrap a remote node |

---

## Base Layer

Everything in `contexts/_base/` is automatically available to all contexts. A context folder only contains what differs from the base.

| File | What it provides |
|------|----------------|
| `tmux.status.conf` | Status bar: instance name, label, service health indicators, time. Loaded by every session via `tmuxp.yml` `before_script`. |
| `Taskfile.base.yml` | Core tasks always available: `where`, `ps`, `log`, `note`, `set`, `get` |
| `context.env` | `YANTRA_HOME`, `YANTRA_VERSION`, default color values |
| `watchers.base.yml` | Universal error patterns: OOMKilled, panic, segfault, connection refused |
| `audit-patterns.yml` | Auto-summary rules for common commands |
| `audit-ignore.yml` | Noise filter: `ls`, `cat`, `cd`, `pwd`, `echo`, `yukti log`, bare comments |

Context Taskfiles include base:
```yaml
includes:
  base:
    taskfile: "${YANTRA_HOME}/contexts/_base/Taskfile.base.yml"
```

Context `watchers.yml` files can extend base patterns with an `extends: _base` key.

---

## Remote Execution

### Thin mode — minimal remote footprint

Host drives all orchestration. Remote executes commands passively.

**Remote requires:** `tmux >= 2.6`, `bash`, `jq`, project-specific tools.

```
Host (Mac)                              Remote
──────────────────────────────          ──────────────────────
yukti go wscs-staging
  → ssh remote "tmux new-session -s ..."  tmux session created
orchestrate reads services.yml
  → ssh remote "./run.sh svc1"             process runs remotely
watch-logs
  → ssh remote "tail -f log" (piped)       stdout piped to host watcher
yukti updates status bar
  → ssh remote "tmux setenv YANTRA_STATUS_LINE ..."
```

### Full mode — yantra installed on remote

**Remote requires:** thin requirements + `git`, `python3` (or go binary), `mise`.

```
Host (Mac)                              Remote (ubuntu@192.168.1.151)
──────────────────────────────          ──────────────────────────────
yukti go vidheya                        yantra installed at ~/yantra
  → ssh -t remote "yukti go vidheya"     → tmuxp loads locally
                                           orchestrate runs locally
                                           sessions survive host disconnect
```

**Recommended for:** devops contexts, persistent environments, complex multi-service orchestration on the remote node.

### Remote flag in registry

```yaml
remote:
  host: ubuntu@192.168.1.151
  mode: thin   # or: full
  path: ~/repo/vidheya
```

---

## Multi-Instance Support

Multiple instances of the same context type run as isolated tmux sessions simultaneously:

```
Session: wscs-dev     [wscloudservices]  running  ████ green status bar
Session: wscs-staging [wscloudservices]  running  ████ yellow status bar
Session: vidheya      [vidheya]          running  ████ blue status bar
```

Each instance has:
- Its own tmux session (session name = instance id)
- Its own session KV store
- Its own daily audit log file
- A unique color in the tmux status bar

`yukti go` with no argument opens an fzf picker showing all instances with live state, including which are running and their service health.

---

## Orientation & Self-Awareness

Three layers at different cognitive costs. All three are provided by the base layer — no per-context configuration needed.

### 1. tmux status bar — always visible, zero cognitive cost

Present in every pane at all times, even when commands are running. Color-coded by instance.

```
 [wscs-dev | dev]  svc1● svc2● frontend◌        services | svc1   14:32
 ─────────────────────────────────────────────────────────────────────────
  ^^green^^        ^^^live service health^^^      window | pane     time
```

- Background color = instance color from registry (`color: green`)
- Service health dots: `●` running healthy, `◌` stopped, `✗` failed
- Window and pane name always visible on right
- Multiple simultaneous sessions are distinguishable by color alone, without reading

Defined once in `_base/tmux.status.conf`. Loaded by all sessions via `tmuxp.yml` `before_script`. yukti updates `YANTRA_STATUS_LINE` via `tmux setenv` on every service state change.

### 2. Shell prompt — visible when idle

```
wscs-dev  ~/dev/ECP/experience-api-insurtech-shopping  main  ❯
^^^^^^^
instance prefix, colored to match status bar
```

Set via `YANTRA_INSTANCE`, `YANTRA_LABEL`, `YANTRA_INSTANCE_COLOR` exported into every shell pane by `init.sh`. Compatible with starship and p10k prompt frameworks.

### 3. `yukti where` — on demand

```bash
$ yukti where
wscs-dev  (wscloudservices | dev | local)

$ yukti where --short
wscs-dev
```

For scripts, pre-command confirmation, and any tool that needs the current context identity.

---

## Init & Bootstrap

### `init.sh` modes

`init.sh` must be **sourced**, not executed. Sourcing allows it to modify the current shell environment: export variables, set PATH, register shell functions, and drop into a tmux session.

```bash
source ~/yantra/init.sh              # smart mode: detect → suggest → pick
source ~/yantra/init.sh wscs-dev     # direct: activate named instance immediately
source ~/yantra/init.sh --last       # resume last active instance
source ~/yantra/init.sh --list       # fzf picker only, no detection
source ~/yantra/init.sh --quiet      # PATH + env + functions only, no session launch
source ~/yantra/init.sh --new <ctx>  # register new instance wizard, then activate
```

`--quiet` is the safe default for `.zshrc` — sets up the shell without launching anything on every new tab.

### Smart mode — detection and suggestions

Smart mode builds context from observable state and surfaces ranked suggestions:

```
yantra v1.0

  Detected  wscs-dev  ~/dev/ECP/.../experience-api-insurtech-shopping
  Running   vidheya   ● pods✓ events✓
  Last used wscs-dev  2h ago  svc1✓ svc2✗ frontend✗

  [1] resume  wscs-dev   attach + restart failed services
  [2] fresh   wscs-dev   new session + start svc1, svc2
  [3] attach  vidheya    join running session
  [4] pick    ...        fzf all instances
  [q]         env only   set up shell, no session

  → [1]
```

Detection priority:
1. Current directory → match against registry `local_path` values
2. Running tmux sessions → offer to attach
3. `~/.config/yantra/last` → most recently used instance
4. Full registry → fzf picker fallback

**resume vs fresh:** resume attaches to an existing session and offers to restart stopped or failed services. Fresh creates a new session and starts from scratch.

`auto_start: true` in `services.yml` controls which services are offered in suggestions.

### `.zshrc` integration

```bash
# Option 1 — quiet setup always, alias for smart mode on demand
source ~/yantra/init.sh --quiet
alias yt='source ~/yantra/init.sh'

# Option 2 — smart mode once per day, quiet on subsequent tabs
if [[ ! -f /tmp/.yantra-greeted-$(date +%Y%m%d) ]]; then
  source ~/yantra/init.sh
  touch /tmp/.yantra-greeted-$(date +%Y%m%d)
else
  source ~/yantra/init.sh --quiet
fi
```

Option 2 recommended: morning greeting with full context, quiet for the rest of the day.

### `install.sh`

```bash
./install.sh                              # local full setup
./install.sh --remote host --thin         # minimal remote: check tmux + bash + jq
./install.sh --remote host --full         # clone yantra on remote + full setup
```

Thin remote bootstrap is idempotent — checks what is already present before installing.

---

## Audit Trail

### What gets captured

| Type | Source | How |
|------|--------|-----|
| `manual` | Commands typed by user in any yantra shell pane | `precmd`/`preexec` shell hook |
| `auto` | Commands run by orchestrate, watch-logs | Written directly by Python impl |
| `system` | Session start/stop, service state transitions | Written directly by yukti |

### Capture mechanism (manual)

`lib/audit.sh` is sourced into every shell pane by `init.sh`. After each command:

```bash
_yantra_audit_hook() {
  # captures: command text, exit code, duration, tmux window+pane, instance, context
  # appends one JSONL record to ~/.config/yantra/audit/<instance>/YYYY-MM-DD.jsonl
}
precmd_functions+=(_yantra_audit_hook)    # zsh
preexec_functions+=(_yantra_cmd_timer)    # zsh — for duration tracking
```

### Storage format

One JSONL record per line, append-only:

```json
{"ts":"2026-07-04T10:23:45Z","instance":"wscs-dev","context":"wscloudservices",
 "window":"shell","pane":"shell","cmd":"yukti build svc1","exit":0,
 "duration_ms":4521,"type":"manual","summary":"Service rebuild triggered",
 "blast_radius":"medium"}
```

### Summary mechanisms

Three ways to attach a human-readable summary to an audit record:

**1. Automatic pattern matching** — `_base/audit-patterns.yml`, evaluated at write time:
```yaml
patterns:
  - match: "terraform apply*"
    summary: "Infrastructure change applied"
    blast_radius: high
  - match: "yukti build*"
    summary: "Service rebuild triggered"
    blast_radius: medium
  - match: "ansible-playbook*"
    summary: "Ansible playbook executed"
    blast_radius: high
  - match: "kubectl delete*"
    summary: "Kubernetes resource deleted"
    blast_radius: high
```

**2. Inline prefix** — a `## text` comment on the line immediately before a command is attached as that command's summary:
```bash
## rebuilding svc1 after fixing auth token expiry
yukti build svc1
```

**3. Post-hoc annotation** — `yukti note "text"` patches the summary field on the last audit record in the current session.

### Querying

```bash
yukti log                          # today, all instances, formatted
yukti log --instance wscs-dev      # filter by instance
yukti log --since 2h               # last 2 hours
yukti log --since 2026-07-04       # specific date
yukti log --type manual            # manual commands only
yukti log --blast high             # high blast-radius only
yukti log --exit 1                 # failed commands only
yukti log --search "rebuild"       # text search on cmd field
yukti log --annotated              # only records with summaries
yukti log --json                   # raw JSONL for piping to jq
```

Default formatted output:
```
2026-07-04  wscs-dev  (wscloudservices)
───────────────────────────────────────────────────────────────────
10:23:45  manual   shell/shell     yukti build svc1         ✓  4.5s
                   Service rebuild triggered
10:25:12  auto     services/svc1   orchestrate start svc1   ✓  8.2s
                   svc1 started, health check passed
10:31:07  manual   shell/shell     task gql:run QUERY=users  ✓  0.3s
11:02:14  manual   ops/iac         terraform apply          ✓  43.2s  [high]
                   Infrastructure change applied
          note     "applied DB migration for ticket ILSSSP-5212"
```

### Noise filter

`_base/audit-ignore.yml` suppresses records for: `ls`, `cat`, `cd`, `pwd`, `echo`, `yukti log*`, and bare comments. Context folders can extend this list.

---

## Session KV Store

Per-session ephemeral key-value store for runtime state that should not be in env vars globally.

```bash
yukti set AUTH_TOKEN "Bearer xxxx"   # write to session KV
yukti get AUTH_TOKEN                  # read from session KV
```

Backed by `~/.config/yantra/sessions/<instance>.env`. Values are injected into the tmux session env via `tmux setenv` so they are available in any pane without re-sourcing.

Tasks that depend on a KV key declare `reads_session: [AUTH_TOKEN]` — yukti checks for the key at task start and fails fast with a helpful message if it is not set, rather than silently failing mid-execution.

---

## Service Orchestration — Project 1 Pattern

For contexts with long-running services that must start in a specific order with health validation.

### Startup chain

1. yukti reads `services.yml`, resolves dependency graph
2. process-compose starts services in topological order
3. For each service: start → poll ready condition → proceed only on pass
4. On `SIGINT`: graceful reverse-order shutdown (last started, first stopped)
5. Rebuild cascade: `yukti build svc1` → stops dependents (reverse order) → rebuilds → restarts (forward order)

### Ready condition types

| Type | Config example | Passes when |
|------|---------------|-------------|
| `http` | `url: .../health` + optional `expect: '"status":"UP"'` | HTTP 200 (+ body match if expect set) |
| `port` | `port: 8082` | TCP connection accepted |
| `log_pattern` | `pattern: "Started Application"` | Pattern appears in service stdout |
| `exit_code` | `code: 0` | Process exits with given code (one-shot services) |

### Groups

Services declare group membership in `services.yml`. Groups are named collections used for bulk operations:

```bash
yukti up backend      # start svc1 + svc2 in order
yukti build all       # rebuild all services with cascade
yukti down all        # stop all in reverse order
```

---

## Infra Operations — Project 2 Pattern

For contexts where the primary work is infrastructure management rather than long-running services.

`ops.yml` uses a `kind` discriminator because infra contexts have four distinct operation types with different lifecycle semantics, and cramming them into `services.yml` would require too many nullable fields.

### High blast-radius protection

ops entries with `blast_radius: high` require explicit confirmation before execution, enforced by yukti regardless of whether a Taskfile `prompt:` is set. This is not optional and cannot be skipped by callers.

### `vars_required`

If an op declares `vars_required: [PLAYBOOK]` and the variable is not in the environment, yukti prompts the user interactively rather than failing with an error.

---

## Implementation Language

### Current: Python + Shell

| Component | Language | Rationale |
|-----------|----------|-----------|
| `init.sh`, `switch`, `install.sh` | Shell | Glue only; stable forever; no logic |
| `orchestrate`, `watch-logs`, `healthcheck`, `audit` | Python | libtmux, asyncio, PyYAML; fast to build |

### Future: Go (drop-in replacement)

All logic components are behind shims. Replacing Python with Go requires changing only the implementation files and flipping `YANTRA_IMPL`. Everything else — shell scripts, config schemas, CLI contracts — stays identical.

```bash
# bin/orchestrate — shim, never changes
case "${YANTRA_IMPL:-python}" in
  python) exec python3 "${YANTRA_HOME}/impl/python/orchestrate.py" "$@" ;;
  go)     exec "${YANTRA_HOME}/impl/go/orchestrate" "$@" ;;
esac
```

**Migration path:**
1. Implement Go binary with identical CLI contract (same flags, exit codes, stdout format)
2. Test in parallel: `YANTRA_IMPL=go yukti up svc1`
3. Flip default in shim once proven
4. Remove Python impl when no longer needed

**Why Go later:**
- Single binary distribution to remote nodes (no `python3 + pip install`)
- Goroutines for parallel health checks
- Strong argument for thin-remote mode: `scp` one binary, done

**CLI contracts are the interface.** Config schemas (YAML) and CLI signatures never change across language migrations.

---

## Example Contexts

### WSCloudServices — service development

**Registry instances:** `wscs-dev` (local), `wscs-staging` (thin remote)

**Services:** `svc1` → `svc2` (depends on svc1) → `frontend` (depends on both)

**Workflow:**
1. `yukti up` starts svc1, waits for health, starts svc2, waits, offers frontend
2. Visit frontend in browser, copy auth token
3. `yukti set AUTH_TOKEN "Bearer xxxx"` — available in all panes immediately
4. `yukti run gql:users` — runs predefined GQL query using session token
5. Bubble pane surfaces errors from all services
6. `yukti build svc1` — cascade: down svc2 → down svc1 → build → up svc1 → wait → up svc2

**tmux layout:**
```
Window: services   [svc1 | svc2 | bubble]
Window: frontend   [npm run dev]
Window: queries    [gql/curl shell — AUTH_TOKEN auto-available]
Window: shell      [free shell]
```

**Auth token workflow note:** the step of visiting the browser and pasting a token is a human-in-the-loop pause in an otherwise automated workflow. `yukti set` is the current solution. A future `workflow.yml` with `kind: interactive-step` will formalise this pattern.

---

### Vidheya — homelab DevOps

**Registry instance:** `vidheya` (full remote, `ubuntu@192.168.1.151`)

**Stack:** Proxmox → k3s → deployed apps, managed via Terraform and Ansible

**Ops:** `pod-watch` and `stern-apps` (watchers), `k9s` (interactive shell), `cluster-check` (one-shot check), `tf-apply` and `ansible-run` (high blast-radius tasks with confirm)

**tmux layout:**
```
Window: watchers   [pod-watch | stern | k9s | bubble]
Window: ops        [remote shell | IaC shell]
Window: checks     [cluster-check | proxmox shell]
```

---

## Open Decisions & Future Work

| Item | Status | Notes |
|------|--------|-------|
| `workflow.yml` schema | Planned | Human-in-the-loop steps; `kind: interactive-step`; models the auth-token pause pattern |
| Go implementation | Deferred | Python first; shim pattern enables clean swap; prioritise for remote nodes |
| SQLite audit index | Planned | Richer query support; JSONL remains append-only source of truth |
| Sanskrit naming for subsystems | Open | yantra + yukti established; other concepts use English for now |
| `yukti add` instance wizard | Planned | Interactive registration + context scaffold from template |
| macOS notifications | Planned | `terminal-notifier` for critical bubble events (level: critical) |
| Test suite for yantra itself | Planned | Contract tests for yukti CLI; schema validators for YAML configs |
| Context-specific audit patterns | Planned | `contexts/<name>/audit-patterns.yml` extends `_base/audit-patterns.yml` |
| `blast_radius` on manual commands | Considered | Pattern-match manual commands against blast_radius registry for audit tagging |
