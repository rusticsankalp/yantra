# yantra Onboarding Guide

> **Goal of this document:** Get you from zero to a fully running, color-coded terminal workspace in about two hours. Everything here is grounded in the actual repo — real file paths, real command output.

---

## 1. Introduction

yantra is a terminal-native dev OS. Its job is to eliminate the setup tax at the start of your
working day: the right tmux session, the right services started in the right order, the right
logs bubbling errors at you, all scoped to the project you're working on.

**The aha moment** looks like this: you type `yukti go wscs-dev`, your terminal grows a
dark-blue status bar labeled `wscs-dev | dev`, four windows appear (services / frontend /
queries / shell), the bubble pane waits to catch errors, and every tmux pane shows a title.
You know exactly where you are without thinking about it. Switch to a different project and the
status bar turns green. Come back tomorrow and `yt` drops you right back.

yantra manages two things:
1. **Workflow config** — how to start your services, what to watch, what your tmux layout looks like. This lives in the repo and is shared.
2. **Machine-local state** — where your code actually is on disk, your secrets, session KV. This lives in `~/.config/yantra/` and never enters git.

---

## 2. Before You Begin

yantra needs the following tools. Check each one before continuing.

| Tool | Min version | Quick check | Install hint |
|------|-------------|-------------|--------------|
| tmux | 2.6 | `tmux -V` | `brew install tmux` |
| tmuxp | any | `tmuxp --version` | `pip3 install tmuxp` |
| fzf | any | `fzf --version` | `brew install fzf` |
| zoxide | any | `zoxide --version` | `brew install zoxide` |
| mise | any | `mise --version` | `brew install mise` |
| python3 | 3.8 | `python3 --version` | `brew install python` |
| jq | any | `jq --version` | `brew install jq` |

All of these are checked automatically by `install.sh`. If something is missing it will tell you
exactly what to install. You do not need to install them by hand first — just run the installer
and fix anything it flags.

---

## 3. Module 1: Install and See It Work

**Goal:** Clone yantra, run the installer, register a demo project, and see your first live
tmux session with a color status bar.

**Time:** ~30 minutes

---

### Step 1 — Clone the repo

- [ ] Clone yantra to your home directory:

```bash
git clone <your-org>/yantra ~/yantra
```

yantra expects to live at `~/yantra`. You can put it elsewhere, but then you must set
`YANTRA_HOME` manually in your `.zshrc`. The default is simpler.

---

### Step 2 — Run the installer

- [ ] Run:

```bash
cd ~/yantra && ./install.sh
```

**You should see:**

```
  yantra installer
  home: /Users/you/yantra
  config: /Users/you/.config/yantra

Checking required tools
  ✓  tmux
  ✓  tmuxp
  ✓  fzf
  ✓  zoxide
  ✓  mise
  ✓  python3
  ✓  jq

Creating config directories
  ✓  created /Users/you/.config/yantra
  ✓  created /Users/you/.config/yantra/secrets
  ✓  created /Users/you/.config/yantra/sessions
  ✓  created /Users/you/.config/yantra/audit
  ✓  created /Users/you/.config/yantra/registry.yml

Installing Python dependencies
  ✓  pip install complete

Setting executable permissions
  ✓  chmod +x yukti
  ✓  chmod +x switch
  ...

  Setup complete.

  Add to .zshrc:
    source ~/yantra/init.sh --quiet

  Or for smart mode on new shells:
    source ~/yantra/init.sh
```

If any tool is marked `✗`, install it and re-run `./install.sh`. Do not continue until all
required tools show `✓`.

---

### Step 3 — Add yantra to your shell

- [ ] Open `~/.zshrc` and add one of these at the end:

```zsh
# Option A — smart mode: shows a context picker every time you open a new terminal
source ~/yantra/init.sh

# Option B — quiet mode: loads env and functions only, no prompt
source ~/yantra/init.sh --quiet
```

Start with Option A to see how smart mode works. You can switch to Option B later.

- [ ] Reload your shell:

```bash
source ~/.zshrc
```

With Option A you will immediately see the smart mode prompt. Press `q` to dismiss it for now.

---

### Step 4 — Initialize the config

- [ ] Run:

```bash
yukti init
```

**You should see:**

```
  ok  /Users/you/.config/yantra
  ok  /Users/you/.config/yantra/sessions
  ok  /Users/you/.config/yantra/audit

  exists   /Users/you/.config/yantra/registry.yml

Tool check:
  ✓  tmux
  ✓  fzf
  ✓  tmuxp
  ✓  python3

yantra init complete.
```

This creates the config directory structure if `install.sh` has not already done it, and
double-checks that core tools are reachable. Safe to run multiple times.

---

### Step 5 — Register a demo instance

You need an actual directory for `local_path`. Use a temp dir if you do not have a real project
handy right now — you will replace this in Module 3.

- [ ] Create a temp project directory:

```bash
mkdir -p /tmp/demo-project
```

- [ ] Register it as a yantra instance:

```bash
yukti add demo --context wscloudservices --path /tmp/demo-project --label "demo" --color cyan
```

**You should see:**

```
Added instance 'demo'  context=wscloudservices
```

What just happened: `yukti add` wrote one entry to `~/.config/yantra/registry.yml`. Nothing
else changed. The repo is untouched.

---

### Step 6 — Activate it

- [ ] Run:

```bash
yukti go demo
```

**What happens:**
1. yantra reads your instance from `~/.config/yantra/registry.yml`
2. It sets `YANTRA_INSTANCE=demo`, `YANTRA_CONTEXT_TYPE=wscloudservices`, and exports color
   variables for the cyan status bar
3. It loads `contexts/wscloudservices/tmuxp.yml` via `tmuxp`, which creates your tmux session
4. Your terminal switches into the new session

**You should see** a tmux session named `demo` with:
- A cyan status bar at the bottom showing `demo | demo`
- Four windows: `services`, `frontend`, `queries`, `shell`
- Pane titles (svc1, svc2, bubble, frontend, gql, health, shell) visible in each pane's border

If the status bar is plain white, see Troubleshooting section 5.

---

### Step 7 — Orient yourself

Still inside the tmux session:

- [ ] Run in any pane:

```bash
yukti where
```

**You should see:**

```
Instance:  demo
Context:   wscloudservices
Label:     demo
Status:    running
Color:     cyan
Path:      /tmp/demo-project
```

This tells you everything about the currently active instance. It reads from `YANTRA_INSTANCE`,
which was set when you ran `yukti go`.

---

### Step 8 — See all your instances

- [ ] Detach from the tmux session (`Ctrl-b d`), then run:

```bash
yukti ls
```

**You should see:**

```
Instance           Context                Label        Status       Color
────────────────────────────────────────────────────────────────────────
demo               wscloudservices        demo         ● running    cyan
```

The green dot means the tmux session is live. If you had stopped it, you would see an empty
circle instead.

---

### What just happened and why it matters

You now have the full picture of the yantra mental model:

| Layer | What it is | Where it lives |
|-------|-----------|----------------|
| context | Template — windows, services, watchers | `contexts/wscloudservices/` (in repo) |
| instance | Registered deployment — which path, which color | `~/.config/yantra/registry.yml` (local) |
| session | Live tmux session for one active instance | Managed by tmux |

When you run `yukti go`, yantra merges the context config (shared, in repo) with your instance
registration (local, machine-specific) and spins up a tmux session. The repo never needs to
know your `~/dev/myproject` path.

---

## 4. Module 2: Understand the Layout

**Goal:** Walk through every key file and understand what each one does, why it exists, and
what breaks without it.

**Time:** ~20 minutes

---

### The repo tree

```
yantra/
├── bin/
│   ├── yukti          # Python CLI — the only thing you call directly
│   ├── switch         # fzf instance picker (called by init.sh, not you)
│   ├── orchestrate    # bash shim → impl/python/orchestrate.py
│   ├── watch-logs     # bash shim → impl/python/watch_logs.py
│   └── healthcheck    # bash shim → impl/python/healthcheck.py
├── init.sh            # source this in .zshrc
├── install.sh         # one-time bootstrap
├── lib/
│   ├── context.sh     # yantra_activate_instance, color handling, registry reads
│   ├── session.sh     # session KV store (yantra_set, yantra_get)
│   ├── audit.sh       # shell hooks that record your commands to audit logs
│   ├── health.sh      # wait-for-port, wait-for-http, wait-for-log-pattern
│   ├── bubble.sh      # writes errors to the bubble pane
│   └── remote.sh      # SSH attach, remote bootstrap
├── impl/python/
│   ├── orchestrate.py # service start/stop/build with dependency ordering
│   ├── healthcheck.py # port / http / log_pattern health checks
│   ├── watch_logs.py  # tails service output, routes to bubble pane
│   ├── audit.py       # writes/queries audit JSONL files
│   ├── registry.py    # registry CRUD (used by shell scripts)
│   └── requirements.txt
├── contexts/
│   ├── _base/         # inherited by all contexts
│   ├── wscloudservices/  # multi-service dev context
│   └── vidheya/       # devops/k8s context
└── templates/         # starter scaffolds for yukti add
    ├── services-project/
    ├── devops-project/
    └── dev-app-project/
```

---

### Key files — one by one

#### `init.sh`

Sourced (never executed) by your `.zshrc`. Does exactly three things:
1. Sets `YANTRA_HOME`, `YANTRA_CONFIG`, adds `bin/` to `PATH`
2. Sources `lib/context.sh`, `lib/session.sh`, `lib/audit.sh` into your shell
3. Runs smart mode (if called without `--quiet`)

**Edit when:** You want to change the shell prompt that appears on new terminals.
**Missing breaks:** `yukti` is not on PATH; `yantra_activate_instance` is not available.

#### `bin/yukti`

The Python CLI. Every user-facing command goes through here. It reads `~/.config/yantra/registry.yml`,
delegates service lifecycle to `impl/python/orchestrate.py`, delegates audit queries to
`impl/python/audit.py`. It uses only stdlib at the top level (argparse, subprocess) so it works
before Python deps are installed.

**Edit when:** Adding a new `yukti <subcommand>` (see Module 5).
**Missing breaks:** Nothing works.

#### `lib/context.sh`

The core of instance activation. Key functions:
- `yantra_get_instance_info` — reads registry.yml and exports all `YANTRA_*` variables for an instance
- `yantra_color_to_hex` — converts a color name like `cyan` to `#005f5f` for the status bar
- `yantra_load_context_env` — sources `contexts/<type>/context.env` (service URLs, ports)
- `yantra_load_secrets` — sources `~/.config/yantra/secrets/<instance>.env` (tokens, passwords)
- `yantra_activate_instance` — orchestrates all of the above, then attaches or creates the tmux session

**Edit when:** Changing how instances are activated, adding new color names, changing the
session naming scheme.
**Missing breaks:** `yukti go` still works (via bin/yukti) but `source ~/yantra/init.sh <name>`
and smart mode will fail.

#### `contexts/_base/tmux.status.conf`

The tmux configuration that makes every yantra session look consistent. It reads env vars that
were set during activation:

```
# Instance identity on left (color comes from YANTRA_INSTANCE_BG env var)
set-option -g status-left " #[bold]#{E:YANTRA_INSTANCE}#[nobold] | #{E:YANTRA_LABEL} "
set-option -g status-style "bg=#{E:YANTRA_INSTANCE_BG},fg=#{E:YANTRA_INSTANCE_FG}"

# Service health + time on right
set-option -g status-right " #{E:YANTRA_STATUS_LINE}  %H:%M "
```

The `#{E:...}` syntax tells tmux to expand environment variables at render time — that is why
changing an instance's color takes effect without restarting tmux.

**Edit when:** Changing the status bar layout, adding new info to the right side, adjusting
pane border style.
**Missing breaks:** Sessions still start, but with tmux's default plain status bar.

#### `contexts/wscloudservices/services.yml`

Defines the services for the `wscloudservices` context type. This is what `yukti up` reads:

```yaml
services:
  - id: svc2
    cmd: ./run.sh svc2
    depends_on: [svc1]          # svc1 must be healthy before svc2 starts
    auto_start: true
    ready:
      type: port
      host: localhost
      port: "${SVC2_PORT}"      # resolved from context.env at runtime
      timeout: 30s
```

Three health check types exist: `port` (TCP connect), `http` (GET + optional response pattern),
`log_pattern` (regex in pane output). `depends_on` drives topological start order.

**Edit when:** Adding a service, changing its start command or health check.
**Missing breaks:** `yukti up` cannot start services; `yukti ps` returns nothing.

#### `contexts/wscloudservices/tmuxp.yml`

Defines the tmux window/pane layout for the `wscloudservices` context. The first line is
load-bearing:

```yaml
before_script: tmux source-file "${YANTRA_HOME}/contexts/_base/tmux.status.conf"
session_name: "${YANTRA_INSTANCE}"
```

This loads the status bar config and names the session after the instance so multiple instances
can coexist. All `${...}` variables are expanded from the environment at session creation time —
they come from `yantra_activate_instance` which ran before `tmuxp load`.

**Edit when:** Adding a window, changing pane layout, changing pane titles.
**Missing breaks:** Session layout is wrong or `tmuxp` refuses to load.

#### `~/.config/yantra/registry.yml`

Machine-local. Never in the repo. Written by `yukti add`, read by everything else:

```yaml
instances:
  demo:
    context: wscloudservices
    label: demo
    color: cyan
    local_path: /tmp/demo-project
```

Each entry is one registered project on this machine. The `context` field maps to a directory
under `contexts/`. The `color` field drives the status bar. `local_path` becomes `PROJECT_ROOT`
in your session environment.

**Edit when:** You move a project to a different path, change its color, or add/remove an
instance.
**Missing breaks:** `yukti go` cannot find the instance; `yukti ls` returns nothing.

---

### The two-layer model

```
REPO (shared, version controlled)          LOCAL (machine-only, never committed)
────────────────────────────────────────   ────────────────────────────────────
contexts/                                  ~/.config/yantra/registry.yml
  wscloudservices/services.yml               ↑ your paths, colors, labels
  wscloudservices/tmuxp.yml
  wscloudservices/watchers.yml             ~/.config/yantra/secrets/<name>.env
  _base/tmux.status.conf                     ↑ tokens, passwords

templates/                                 ~/.config/yantra/sessions/<name>.env
  services-project/                          ↑ live session KV (yukti set/get)

impl/python/*.py                           ~/.config/yantra/audit/<name>/<date>.jsonl
  ↑ the engine                               ↑ command history and annotations
```

The key rule: if a file contains a machine path or a secret, it belongs in `~/.config/yantra/`.
If it is safe to share with the team, it belongs in the repo.

---

## 5. Module 3: Register Your Real Project

**Goal:** Take a project you actually work on and register it as a yantra instance.

**Time:** ~30 minutes

---

### Step 1 — Register the instance

- [ ] Run, substituting your real path and project name:

```bash
yukti add myproject \
  --context services-project \
  --path ~/dev/myproject \
  --label "myproject dev" \
  --color blue
```

The `--context services-project` means yantra will use `templates/services-project/` as a
starting template. Available contexts are directories under `contexts/` — `wscloudservices`,
`vidheya`, and `services-project` (from templates).

**You should see:**

```
Added instance 'myproject'  context=services-project
```

---

### Step 2 — Inspect what was written

- [ ] Open the registry directly:

```bash
$EDITOR ~/.config/yantra/registry.yml
```

You will see your new entry:

```yaml
instances:
  demo:
    context: wscloudservices
    label: demo
    color: cyan
    local_path: /tmp/demo-project
  myproject:
    context: services-project
    label: myproject dev
    color: blue
    local_path: /Users/you/dev/myproject
```

You can add an `env:` block here to inject instance-specific variables at activation time:

```yaml
  myproject:
    context: services-project
    label: myproject dev
    color: blue
    local_path: /Users/you/dev/myproject
    env:
      SVC1_URL: http://localhost:8081
      SVC2_URL: http://localhost:8082
```

Variables in `env:` are exported before your context's `context.env` and before your secrets
file, so they are the right place for per-instance overrides of defaults.

---

### Step 3 — Add secrets

Secrets (tokens, passwords, private URLs) go in a file that is never committed:

- [ ] Create the secrets file:

```bash
$EDITOR ~/.config/yantra/secrets/myproject.env
```

Format is `KEY=value`, one per line:

```bash
AUTH_TOKEN=Bearer eyJ...
DATABASE_URL=postgres://user:pass@localhost/mydb
SOME_API_KEY=sk-...
```

These are sourced into the session environment when you run `yukti go myproject`. They become
available in every tmux pane, and you can read them at any time with `yukti get AUTH_TOKEN`.

---

### Step 4 — Activate your project

- [ ] Run:

```bash
yukti go myproject
```

**You should see** your terminal enter a new tmux session with a dark-blue status bar (blue
color maps to `#00005f`) labeled `myproject | myproject dev`.

If you have not created `contexts/services-project/tmuxp.yml` yet, `yukti go` falls back to a
bare tmux session. You will create the layout in Module 4.

---

### Step 5 — Look at the layout

The `services-project` template gives you two windows:

- `services` — panes: `svc1` and `bubble`
- `shell` — one general-purpose shell pane

Each pane starts with a hint showing how to start the service (e.g., `svc1 — run: yukti up svc1`).
The bubble pane is where log watchers will write errors. You will customize this in Module 4.

Navigate windows with `Ctrl-b <number>` or `Ctrl-b n` / `Ctrl-b p`. Navigate panes within a
window with `Ctrl-b <arrow>`.

---

### Step 6 — Check process status

- [ ] In any pane:

```bash
yukti ps
```

**You should see** the status of all services defined in `contexts/services-project/services.yml`
for this context. Since services have not been started yet, they will all show as stopped.

---

### Step 7 — Understand the status bar colors

| Color name | Hex | When to use |
|-----------|-----|-------------|
| green | `#005f00` | Primary / main dev instance |
| blue | `#00005f` | Secondary service or staging |
| cyan | `#005f5f` | Demo / sandbox |
| red | `#5f0000` | Production or high-blast-radius ops |
| yellow | `#875f00` | Infrastructure / devops |
| magenta | `#5f005f` | Experimental |
| default | `#262626` | Unassigned |

You are the one who picks colors. The rule is: glance at the status bar and know your blast
radius at a glance. Put red on things you should think twice about.

---

## 6. Module 4: Customize Your Context

**Goal:** Tailor the tmux layout, services, log watchers, and tasks to match your actual
project workflow.

**Time:** ~1 hour

---

### 4a. Customize the tmux layout (tmuxp.yml)

The tmuxp.yml in a context defines what windows and panes appear when you `yukti go`. Here is
the actual `wscloudservices` layout for reference:

```yaml
before_script: tmux source-file "${YANTRA_HOME}/contexts/_base/tmux.status.conf"
session_name: "${YANTRA_INSTANCE}"

windows:
  - window_name: services
    layout: tiled
    panes:
      - shell_command: "echo 'svc1 — run: yukti up svc1'; exec zsh"
        pane_title: svc1
      - shell_command: "echo 'svc2 — run: yukti up svc2'; exec zsh"
        pane_title: svc2
      - shell_command: "echo 'bubble pane — logs appear here'; cat"
        pane_title: bubble

  - window_name: frontend
    panes:
      - shell_command: "echo 'frontend — run: yukti up frontend'; exec zsh"
        pane_title: frontend

  - window_name: queries
    layout: even-horizontal
    panes:
      - shell_command: "exec zsh"
        pane_title: gql
      - shell_command: "exec zsh"
        pane_title: health

  - window_name: shell
    panes:
      - shell_command: "exec zsh"
        pane_title: shell
```

**Key rules:**
- `before_script` must be the first line and must point to `tmux.status.conf` — this is what
  applies the color status bar
- `session_name: "${YANTRA_INSTANCE}"` — always use this; it is what gives the session its
  instance-specific name
- `exec zsh` (or `exec bash`) at the end of `shell_command` leaves a live interactive shell in
  the pane after the hint message runs
- `cat` with no arguments leaves a pane inert and waiting — use this for the bubble pane, which
  is written to by the watcher process, not by you
- `layout` options: `tiled`, `even-horizontal`, `even-vertical`, `main-vertical`, `main-horizontal`

**To add a window for a specific tool** (e.g., a DB shell):

```yaml
  - window_name: db
    panes:
      - shell_command: "echo 'psql — run: psql ${DATABASE_URL}'; exec zsh"
        pane_title: psql
```

- [ ] Edit `contexts/services-project/tmuxp.yml` (or create it from the template) to match your
  project's actual workflow.
- [ ] Kill your session and relaunch to see the changes: `tmux kill-session -t myproject` then
  `yukti go myproject`.

---

### 4b. Add a service to services.yml

The template at `templates/services-project/services.yml` is the starting point:

```yaml
version: 1

groups:
  all: [svc1]

services:
  - id: svc1
    desc: "My service"
    cmd: ./start.sh
    auto_start: true
    build:
      cmd: ./build.sh
    ready:
      type: http
      url: "${SVC1_URL}/health"
      timeout: 60s
    groups: [all]
```

To add a second service that depends on the first:

```yaml
  - id: svc2
    desc: "Second service"
    cmd: ./run.sh svc2
    depends_on: [svc1]        # svc1 must pass its health check first
    auto_start: true
    build:
      cmd: ./build.sh svc2
    ready:
      type: port              # just TCP connect — simpler than http
      host: localhost
      port: "${SVC2_PORT}"
      timeout: 30s
    groups: [all]
```

**Health check types:**
- `type: http` — GET request; optional `expect: "pattern"` substring match in response body
- `type: port` — TCP connect to `host:port`
- `type: log_pattern` — regex match in the service's tmux pane output; useful for services
  that do not expose HTTP

- [ ] Add your services to `contexts/<your-context>/services.yml`.
- [ ] Test a single service: `yukti up svc1`
- [ ] Stop it: `yukti down svc1`
- [ ] Start everything marked `auto_start`: `yukti up`

---

### 4c. Add log watchers (watchers.yml)

The watcher system tails your service panes and routes matching lines to the bubble pane. Here
is the `wscloudservices` example:

```yaml
version: 1

watchers:
  - id: svc1-errors
    desc: Watch svc1 for errors
    source:
      type: service
      id: svc1
    keywords:
      - pattern: "ERROR|FATAL|Exception|NullPointer"
        level: error
        action: [highlight, bubble]   # highlight in the source pane, copy to bubble
      - pattern: "WARN"
        level: warn
        action: [highlight]           # highlight only, do not bubble

bubble:
  pane: "bubble"
  max_lines: 200
  format: "[{ts}] [{source}] {level}: {line}"
```

To add a domain-specific pattern for your project (e.g., an insurance service that emits
`rewardNight` errors):

```yaml
      - pattern: "rewardNight|INSURANCE_ERROR|policy_expired"
        level: error
        action: [highlight, bubble]
```

- [ ] Edit `contexts/<your-context>/watchers.yml` to add patterns for your known error strings.
- [ ] Start log watching in a new session: `yukti up` then wait for a service to emit your pattern.
- [ ] The bubble pane will show `[15:42:01] [svc1] error: INSURANCE_ERROR: policy expired`.

The bubble pane is the pane named `bubble` in your `tmuxp.yml`. The watcher process (`bin/watch-logs`)
runs in the background and writes to it automatically once `yukti up` starts services.

---

### 4d. Add project tasks (Taskfile.yml)

yantra uses [Task](https://taskfile.dev) for project-specific commands. Each context has a
`Taskfile.yml` that includes the base tasks and adds its own. Here is the base include pattern:

```yaml
version: '3'

includes:
  base:
    taskfile: "${YANTRA_HOME}/contexts/_base/Taskfile.base.yml"
    optional: false

vars:
  SVC1_URL:
    sh: echo "${SVC1_URL:-http://localhost:8081}"

tasks:
  start:
    desc: Start all auto_start services
    cmds: [yukti up]
```

To add a custom task that uses session KV and environment variables:

```yaml
  refresh-token:
    desc: Prompt for a new auth token and save it
    cmds:
      - echo "1. Open ${SVC1_URL}/login in your browser"
      - echo "2. Copy your Bearer token"
      - 'printf "Paste token: "; read -r TOKEN; yukti set AUTH_TOKEN "Bearer $TOKEN"'
      - echo "Saved. Use: yukti get AUTH_TOKEN"

  curl-health:
    desc: Hit the health endpoint
    cmds:
      - curl -sf "${SVC1_URL}/health" | python3 -m json.tool
```

`${PROJECT_ROOT}` is exported by `yantra_activate_instance` and resolves to the `local_path`
you set in the registry. Use it in tasks that need to reference project files:

```yaml
  lint:
    desc: Lint the project
    cmds:
      - cd "${PROJECT_ROOT}" && ./gradlew checkstyle
```

- [ ] Add at least one task that you actually use daily.
- [ ] Run it: `task <your-task-name>`

---

### 4e. Add context-specific audit patterns

The audit system records every command you run in a yantra session. The base patterns (in
`contexts/_base/audit-patterns.yml`) classify commands like `terraform apply` and `yukti down`
as high blast-radius automatically. You can add project-specific patterns in your context:

- [ ] Create `contexts/<your-context>/audit-patterns.yml`:

```yaml
version: 1
patterns:
  - match: "curl -X DELETE*"
    summary: "HTTP DELETE request"
    blast_radius: high

  - match: "psql -c 'DROP*"
    summary: "Database DROP statement"
    blast_radius: high

  - match: "kubectl rollout restart*"
    summary: "Deployment restart"
    blast_radius: medium

  - match: "mvn clean install*"
    summary: "Full Maven build"
    blast_radius: low
```

Patterns use shell glob syntax. `blast_radius` accepts `high`, `medium`, or `low`.
These patterns are merged with the base patterns at query time — you never override the base.

- [ ] Query your audit log to see patterns in action:

```bash
yukti log --since 2h
yukti log --blast high     # only dangerous operations
yukti log --type manual    # only commands you typed (not auto-start)
```

---

## 7. Module 5: Add a New yukti Command

**Goal:** Walk through adding a real `yukti token` subcommand that prompts for a token and
saves it to the session KV store.

**Time:** ~1 hour

---

The complete pattern for adding a yukti subcommand is:

1. Add a subparser in `build_parser()`
2. Write a `cmd_<name>()` handler function
3. Add it to the `DISPATCH` dict

Here is the full implementation for `yukti token`:

---

### Step 1 — Open bin/yukti

- [ ] Open `/Users/you/yantra/bin/yukti` in your editor.

---

### Step 2 — Add the subparser in build_parser()

Find the `build_parser()` function. Near the end, before the `return parser` line, add:

```python
    # token
    p = sub.add_parser("token", help="Prompt for an auth token and save it to session KV")
    p.add_argument(
        "--key",
        default="AUTH_TOKEN",
        help="Session key to write (default: AUTH_TOKEN)",
    )
    p.add_argument(
        "--url",
        help="Login URL to print as a hint (optional)",
    )
```

---

### Step 3 — Write the handler

Add this function in the `# Command handlers` section, anywhere before `build_parser()`:

```python
def cmd_token(args):
    """Prompt the user to paste an auth token and save it to session KV."""
    instance_name, _ = _active_instance()

    login_url = args.url or os.environ.get("FRONTEND_URL", "")
    if login_url:
        print(f"\n  1. Open in your browser:  {login_url}/login")
    else:
        print("\n  1. Log in to your service in a browser")
    print("  2. Copy your Bearer token (or raw token)")
    print()

    try:
        token = input("  Paste token: ").strip()
    except (KeyboardInterrupt, EOFError):
        print("\nAborted.")
        sys.exit(0)

    if not token:
        print("No token entered — nothing saved.", file=sys.stderr)
        sys.exit(1)

    # Prepend "Bearer " if not already present
    if not token.lower().startswith("bearer "):
        token = f"Bearer {token}"

    # Reuse cmd_set logic: write to session env file and propagate to tmux
    config = get_yantra_config()
    sessions_dir = Path(config) / "sessions"
    sessions_dir.mkdir(parents=True, exist_ok=True)
    env_file = sessions_dir / f"{instance_name}.env"

    existing = {}
    if env_file.exists():
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, _, v = line.partition("=")
                    existing[k.strip()] = v.strip()

    existing[args.key] = token
    with open(env_file, "w") as f:
        for k, v in existing.items():
            f.write(f"{k}={v}\n")

    running = get_running_sessions()
    if instance_name in running:
        subprocess.run(
            ["tmux", "setenv", "-t", instance_name, args.key, token],
            capture_output=True,
        )

    print(f"\n  Saved {args.key} to session '{instance_name}'")
    print(f"  Retrieve with: yukti get {args.key}")
    print(f"  Use in curl:   curl -H \"Authorization: $({args.key})\" ...")
```

---

### Step 4 — Add to the DISPATCH dict

Find the `DISPATCH` dictionary at the bottom of `bin/yukti`. Add one line:

```python
DISPATCH = {
    "go": cmd_go,
    "ls": cmd_ls,
    ...
    "version": cmd_version,
    "token": cmd_token,   # <-- add this line
}
```

---

### Step 5 — Test it

- [ ] Test the help output without needing a live session:

```bash
YANTRA_HOME=. YANTRA_CONFIG=/tmp/test python3 bin/yukti token --help
```

**You should see:**

```
usage: yukti token [-h] [--key KEY] [--url URL]

options:
  -h, --help   show this help message and exit
  --key KEY    Session key to write (default: AUTH_TOKEN)
  --url URL    Login URL to print as a hint (optional)
```

- [ ] Test the full flow inside an active instance (requires `YANTRA_INSTANCE` to be set):

```bash
yukti go myproject
# inside the session:
yukti token --url http://localhost:8081
```

**You should see** the prompt, and after pasting a token, `Saved AUTH_TOKEN to session 'myproject'`.

- [ ] Verify it was saved:

```bash
yukti get AUTH_TOKEN
```

---

### Step 6 — Update the README CLI reference

The README has a `## yukti CLI Reference` section. Add one row to the commands table and an
example snippet. This is the contract that teammates rely on, so keep it current.

---

## 8. Module 6: Set Up a Remote Project

**Goal:** Connect yantra to a project that runs on a remote host — either a homelab node, a
staging server, or a cloud VM.

**Time:** ~30 minutes (optional)

---

### Two modes

**Thin mode** — the remote host needs only `tmux`, `bash`, and `jq`. yantra drives everything
from your local machine by SSH-ing in and attaching to a tmux session there. The repo only
lives locally.

**Full mode** — yantra is installed on the remote host too. The remote has its own `yukti`,
its own registry, its own contexts. You SSH in and attach to the remote session as if you were
sitting at that machine. Good for devops/homelab setups where the remote is the natural place
to run the workflows.

---

### Thin mode setup

- [ ] Register the remote instance locally:

```bash
yukti add myremote \
  --context services-project \
  --remote-host user@192.168.1.50 \
  --remote-path ~/app \
  --remote-mode thin \
  --color red
```

- [ ] Verify the remote has the minimum tools:

```bash
./install.sh --remote user@192.168.1.50 --thin
```

**You should see** `ok tmux`, `ok bash`, `ok jq` (or error messages for anything missing).

- [ ] Activate:

```bash
yukti go myremote
```

yantra will SSH to `user@192.168.1.50` and attach to (or create) a tmux session there. The
status bar color (red) reminds you that you are on a production/remote host.

---

### Full mode setup

Full mode is appropriate when the remote host is a dedicated machine (like a k8s management
node) that benefits from having the full yantra workflow engine installed there.

- [ ] Install yantra on the remote:

```bash
./install.sh --remote user@192.168.1.151 --full
```

This SSHes to the remote, clones the yantra repo to `~/yantra`, and runs `install.sh` there.

- [ ] Register the instance:

```bash
yukti add vidheya \
  --context vidheya \
  --remote-host ubuntu@192.168.1.151 \
  --remote-path ~/repo/vidheya \
  --remote-mode full \
  --color yellow
```

- [ ] Activate:

```bash
yukti go vidheya
```

yantra SSHes in and attaches to the remote's yantra-managed tmux session. The `vidheya` context
on the remote runs `kubectl`, `stern`, `k9s`, and `terraform` there — you get the full devops
layout in your local terminal.

---

### SSH tips for remote instances

- Use `~/.ssh/config` to set `ControlMaster auto` and `ControlPersist 600` for your remote hosts.
  This makes repeated `yukti go` calls instant instead of re-authenticating every time.
- If SSH times out during long `yukti up` runs, set `ServerAliveInterval 60` in your SSH config.
- Test the connection manually before registering: `ssh user@host tmux list-sessions` should
  return cleanly.

---

## 9. Day-to-Day Workflows

Once everything is set up, your daily interaction with yantra is short.

---

### Morning startup

When you open a new terminal, smart mode fires (if you sourced `init.sh` without `--quiet`):

```
  yantra v0.1.0

  Detected  wscs-dev               (matched current directory)
  Last used wscs-dev

  [1] resume  wscs-dev
  [2] fresh   wscs-dev
  [3] pick    ... (fzf)
  [q] env only

  →
```

Press `1` to reattach to the existing session (preserves pane history), `2` to kill and restart
fresh (useful after a reboot), or `3` to pick a different project with fzf.

If you are in quiet mode or want to navigate manually:

```bash
yukti go              # fzf picker — shows all instances with running status
yukti go wscs-dev     # jump directly by name
yukti go --last       # resume whichever instance you were last in
```

---

### Jumping between contexts

Each `yukti go` call sets `YANTRA_INSTANCE` and all derived env vars in the new shell session
the tmux pane runs. You can jump between open sessions freely:

```bash
# From any terminal:
yukti go               # fzf picker
Ctrl-b s               # tmux's own session list (useful for quick switching)
```

---

### Dev loop (services context)

```bash
yukti up               # start all auto_start services (ordered, health-checked)
# ... make code changes ...
yukti build svc1       # rebuild svc1: stops it, runs build.cmd, restarts, waits for health
yukti restart svc2     # restart without rebuild
yukti down             # stop everything cleanly
yukti log --since 30m  # what ran in the last 30 minutes
```

---

### Setting and reading session variables

Session variables persist for the life of the tmux session and are automatically available
in every pane:

```bash
yukti set AUTH_TOKEN "Bearer eyJ..."      # write
yukti get AUTH_TOKEN                      # read
echo $AUTH_TOKEN                          # also works — it's in the environment
```

---

### Audit log and annotations

yantra records every command you run inside a session, including the exit code, duration, and
inferred blast radius. This is your session's flight recorder.

```bash
yukti log                       # today's log, current instance
yukti log --since 2h            # last 2 hours
yukti log --type manual         # only commands you typed (not auto-start)
yukti log --blast high          # only risky operations
yukti log --exit 1              # only failed commands
yukti log --search "build"      # commands matching "build"
```

To annotate as you work:

```bash
## fixing auth bug               # prefix a command with ## to tag it in the audit log
yukti note "confirmed fixed"     # post-hoc annotation on the last log entry
```

---

### Ops context workflows (devops / k8s)

For a devops context using `ops.yml` (like the `vidheya` context):

```bash
yukti run pod-watch              # starts kubectl events stream in the ops pane
yukti run tf-plan                # dry-run terraform plan
yukti run tf-apply               # terraform apply — prompts for confirm (blast_radius: high)
yukti check                      # run all checks defined in ops.yml
yukti check cluster-check        # run one specific check
```

---

## 10. Troubleshooting Reference

---

**Session already exists error when running `yukti go`**

```
# tmux refuses to create a session with an existing name
tmux kill-session -t myproject
yukti go myproject
```

Or, if you want to keep the session history, just attach directly:

```bash
tmux attach-session -t myproject
```

---

**"No instances registered" when running `yukti go`**

```
No instances registered. Run: yukti add <name> --context <type>
```

The registry is empty or `YANTRA_CONFIG` is pointing somewhere unexpected.

```bash
cat ~/.config/yantra/registry.yml     # should show instances, not just '{}'
echo $YANTRA_CONFIG                   # should be ~/.config/yantra
yukti init                            # re-run init; safe, idempotent
```

---

**Python dependencies missing**

```
pyyaml not installed — run: yukti install
```

```bash
yukti install
# or directly:
pip3 install -r ~/yantra/impl/python/requirements.txt
```

---

**Status bar not showing / plain white bar**

The `before_script` in `tmuxp.yml` loads the status config. If the bar is plain, either:
1. `tmuxp.yml` is missing the `before_script` line
2. `YANTRA_HOME` was not set when `tmuxp load` ran

```bash
echo $YANTRA_HOME                       # should be ~/yantra
# manually reload config inside a running session:
tmux source-file ~/yantra/contexts/_base/tmux.status.conf
```

---

**Pane titles not showing**

Pane titles require `pane-border-status` to be set. The base tmux config sets this:

```
set-option -g pane-border-status top
```

If it is not showing, check your tmux version — `pane-border-status` requires tmux >= 2.6.

```bash
tmux -V    # should be 2.6 or higher
```

---

**SSH connection issues for remote instances**

```bash
# Test the connection manually first:
ssh user@host tmux list-sessions

# Check SSH config:
cat ~/.ssh/config | grep -A 5 "Host myremote"

# Add ControlMaster for faster reconnects:
cat >> ~/.ssh/config << 'EOF'
Host myremote
  HostName 192.168.1.50
  User user
  ControlMaster auto
  ControlPath ~/.ssh/cm_%r@%h:%p
  ControlPersist 600
  ServerAliveInterval 60
EOF
```

---

**`yukti go` ignores my `context.env` changes**

`context.env` is sourced at activation time, not when the session is running. Changes only
take effect when you re-run `yukti go`:

```bash
tmux kill-session -t myproject   # kill the running session
yukti go myproject               # re-activate with new env
```

---

**`yukti add` says instance already exists**

```bash
# View current registry:
cat ~/.config/yantra/registry.yml

# Either edit it directly to remove the old entry, or use a different name
yukti add myproject-v2 --context services-project --path ~/dev/myproject --color blue
```

---

## 11. What to Read Next

**[CLAUDE.md](CLAUDE.md)** — How the codebase is structured: file map, data flows, naming
conventions, YAML schemas, how to add new context types, health check types, and audit rules.
Also the authoritative anti-pattern list (things that will silently break). Read this before
making any code changes. It is also the context file AI pair programming tools like Claude Code
will load automatically.

**README.md** — The complete CLI reference. Every `yukti` subcommand, all options, examples.
The place to check when you cannot remember a flag.

**yantra.md** (if present in the repo root) — The full design specification: architectural
decisions, rationale for the two-layer model, open design questions, and future work. Read this
if you want to understand why something was built the way it was, not just how to use it.

---

*Questions or issues? Open a ticket or ping the yantra channel. This guide lives at `ONBOARDING.md` in the repo root — PRs welcome.*
