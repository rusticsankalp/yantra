# yantra

A terminal-native dev OS — persistent, color-coded tmux workspaces with structured service lifecycle, audit trail, and smart context switching.

---

## What is yantra

yantra turns your terminal into a structured operating environment for development work. Instead of scattered tmux sessions and ad-hoc scripts, you get **named contexts** (project templates defining how a project type runs), **registered instances** (specific deployments of those contexts), and **sessions** (live tmux workspaces that appear and disappear cleanly). Every command you run is logged. Every service has a defined start order, health check, and build cascade. When you switch between projects, you switch between fully configured environments — ports, secrets, layouts, watchers — not just directories.

Core tools it orchestrates: **mise** (runtime versions), **task** (project tasks), **tmux + tmuxp** (session layout), **fzf** (interactive selection), **zoxide** (smart directory jumping).

---

## Quick Start

Five steps from zero to running your first instance:

```bash
# 1. Install yantra
git clone https://github.com/you/yantra ~/yantra
cd ~/yantra && ./install.sh

# 2. Wire it into your shell
echo 'source ~/yantra/init.sh --quiet' >> ~/.zshrc
echo "alias yt='source ~/yantra/init.sh'" >> ~/.zshrc
source ~/.zshrc

# 3. Register a project instance
yukti add myproject-dev \
  --context services-project \
  --path ~/dev/myproject \
  --color green

# 4. Activate it
yukti go myproject-dev

# 5. Start services
yukti up
```

You are now in a color-coded tmux session with your services starting, log watchers running, and every action recorded in the audit trail.

---

## Concepts

### context

A **context** is a template that defines how a category of project runs. It lives in `~/yantra/contexts/<type>/` and contains:

| File | Purpose |
|------|---------|
| `context.env` | Environment variables for this context type |
| `services.yml` | Service definitions, start order, health checks |
| `watchers.yml` | Log keyword rules, bubble pane routing |
| `tmuxp.yml` | tmux window and pane layout |
| `Taskfile.yml` | Project tasks (includes base tasks) |

Contexts are reusable blueprints. Multiple instances can share the same context type. You create a new context when you have a new *category* of project (e.g., a Go microservice cluster, a k8s ops box, a frontend app).

### instance

An **instance** is a specific registered deployment of a context. It lives in `~/.config/yantra/registry.yml` and binds a context type to:

- a local (or remote) path
- a color for its tmux status bar
- optional env overrides (port numbers, tokens, remote host)
- secrets file path

Example: `wscs-dev` and `wscs-staging` are two instances of the same `wscloudservices` context — different environments, same blueprint.

### session

A **session** is the live tmux workspace for an active instance. Sessions are created by `yukti go` using tmuxp and the instance's `tmuxp.yml`. Each session:

- Has a color-coded status bar (set at instance registration)
- Runs log watchers in the background
- Sources the instance's env and secrets on attach
- Is torn down cleanly by `yukti down` (services stopped first)

Session names match instance names: `wscs-dev`, `vidheya`, `myproject-staging`.

---

## Installation

### Prerequisites

| Tool | Minimum version | Install |
|------|----------------|---------|
| tmux | >= 2.6 | `brew install tmux` |
| tmuxp | any | `pip3 install tmuxp` |
| fzf | any | `brew install fzf` |
| zoxide | any | `brew install zoxide` |
| mise | any | `curl https://mise.run \| sh` |
| python3 | >= 3.8 | via mise or system |
| jq | any | `brew install jq` |

Verify: `tmux -V && python3 --version && mise --version`

### Install yantra

```bash
git clone https://github.com/you/yantra ~/yantra
cd ~/yantra
./install.sh
```

`install.sh` does the following:
- Creates `~/.config/yantra/` (registry, secrets, logs)
- Installs Python dependencies: `pip3 install -r impl/python/requirements.txt`
- Verifies tool prerequisites
- Writes a default `~/.config/yantra/registry.yml` if none exists

### Shell integration

Add to `~/.zshrc`:

```zsh
# yantra — always-on quiet init (sets YANTRA_HOME, PATH entries, completions)
source ~/yantra/init.sh --quiet

# yt — smart jump: fzf picker if not in a session, attach if you are
alias yt='source ~/yantra/init.sh'
```

Reload: `source ~/.zshrc`

### Verify installation

```bash
yukti ls          # should show empty registry or example instance
yukti --version   # prints yantra version
```

---

## yukti CLI Reference

`yukti` is the Python CLI that drives yantra. All subcommands follow `yukti <command> [args] [options]`.

---

### yukti go

Activate an instance — create its tmux session (if needed) and attach.

**Usage:** `yukti go [instance] [--last]`

| Option | Description |
|--------|-------------|
| `instance` | Instance name to activate (optional; fzf picker if omitted) |
| `--last` | Resume the last active instance (stored in `~/.config/yantra/last`) |
| `--no-attach` | Create the session without attaching (useful for scripting) |

**What it does:** Looks up the instance in the registry, sources its env and secrets, runs `tmuxp load` with the context's `tmuxp.yml`, and attaches. If a session already exists, it attaches without recreating it.

**Examples:**
```bash
yukti go                   # fzf picker over all registered instances
yukti go wscs-dev          # direct activate — create or attach
yukti go --last            # resume whatever you were last working on
yukti go wscs-staging --no-attach  # start session in background
```

---

### yukti ls

List all registered instances with their status.

**Usage:** `yukti ls [--json]`

| Option | Description |
|--------|-------------|
| `--json` | Output as JSON (for scripting) |
| `--active` | Show only instances with live tmux sessions |

**What it does:** Reads the registry, checks which instances have active tmux sessions, and prints a status table.

**Examples:**
```bash
yukti ls                   # table: name, context, path, session status, color
yukti ls --active          # only instances with live sessions
yukti ls --json            # machine-readable for scripts
```

---

### yukti where

Print the current instance and context.

**Usage:** `yukti where`

**What it does:** Reads `$YANTRA_INSTANCE` from the environment and prints the instance name, context type, project path, and active session name. Useful for orientation when jumping between terminals.

**Examples:**
```bash
yukti where
# Instance:  wscs-dev
# Context:   wscloudservices
# Path:      ~/dev/WSCloudServices
# Session:   wscs-dev (active)
```

---

### yukti up

Start services for the current instance.

**Usage:** `yukti up [service...] [--all] [--dry-run]`

| Option | Description |
|--------|-------------|
| `service` | One or more service IDs to start (default: all `auto_start: true`) |
| `--all` | Force-start all services, including those with `auto_start: false` |
| `--dry-run` | Print what would happen without starting anything |
| `--no-wait` | Don't wait for health checks before returning |

**What it does:** Reads `services.yml` for the current context, starts services in dependency order, and waits for health checks to pass. Logs start events to the audit trail.

**Examples:**
```bash
yukti up                   # start all auto_start services in order
yukti up svc1              # start just svc1
yukti up svc1 svc2         # start svc1, then svc2
yukti up --dry-run         # preview startup order and health checks
```

---

### yukti down

Stop services for the current instance.

**Usage:** `yukti down [service...] [--all] [--kill]`

| Option | Description |
|--------|-------------|
| `service` | One or more service IDs to stop (default: all running) |
| `--all` | Stop all services and detach session |
| `--kill` | SIGKILL instead of graceful shutdown |
| `--session` | Also kill the tmux session after stopping services |

**What it does:** Stops services in reverse dependency order, sends SIGTERM, waits for clean exit. With `--session`, tears down the tmux session afterward.

**Examples:**
```bash
yukti down                 # stop all running services (graceful)
yukti down svc2            # stop just svc2
yukti down --kill          # force-kill all
yukti down --all --session # full teardown: services + session
```

---

### yukti restart

Restart one or more services.

**Usage:** `yukti restart [service...] [--all]`

| Option | Description |
|--------|-------------|
| `service` | Service(s) to restart (default: all running) |
| `--all` | Restart every service including those not currently running |

**What it does:** Stops then starts the specified services, respecting dependency order (dependents are stopped before their dependency restarts).

**Examples:**
```bash
yukti restart              # restart all running services
yukti restart svc1         # restart svc1 (stops svc2 first if svc2 depends on svc1)
yukti restart svc1 svc2    # restart both
```

---

### yukti build

Build one or more services (runs build command, then restarts).

**Usage:** `yukti build [service...] [--no-restart]`

| Option | Description |
|--------|-------------|
| `service` | Service(s) to build (default: all services with `build.cmd`) |
| `--no-restart` | Build only, do not restart after |
| `--cascade` | Also rebuild and restart services that depend on the built service |

**What it does:** For each service: stops it (and dependents), runs the `build.cmd` from `services.yml`, then restarts. Cascades by default if dependents are defined.

**Examples:**
```bash
yukti build                # build all buildable services
yukti build svc1           # build svc1 (cascades to dependents)
yukti build svc1 --no-restart  # compile only, leave running as-is
yukti build all --cascade  # full rebuild in dependency order
```

---

### yukti ps

Show running service processes for the current instance.

**Usage:** `yukti ps [--json] [--watch]`

| Option | Description |
|--------|-------------|
| `--json` | Output as JSON |
| `--watch` | Refresh every 2 seconds (like watch) |
| `--verbose` | Include PIDs, ports, uptime |

**What it does:** Queries the process state from the yantra runtime and prints a table of service name, status (running/stopped/starting/failed), PID, and uptime.

**Examples:**
```bash
yukti ps                   # snapshot: all services + status
yukti ps --watch           # live refresh
yukti ps --verbose         # include PID, port, uptime
yukti ps --json | jq .     # pipe to jq
```

---

### yukti run

Run a named op or ad-hoc command in the current context's session.

**Usage:** `yukti run <op-id|command> [--pane <name>] [--detach]`

| Option | Description |
|--------|-------------|
| `op-id` | ID of an op defined in `ops.yml` (for devops contexts) |
| `--pane` | Target tmux pane name (default: current pane) |
| `--detach` | Run in background without attaching |
| `--remote` | Run on remote host (uses instance's `REMOTE_HOST`) |

**What it does:** For devops contexts, looks up the op in `ops.yml` and runs it. For arbitrary commands, wraps them in the instance's env and runs in the specified pane.

**Examples:**
```bash
yukti run pod-watch              # start named op in ops.yml
yukti run "kubectl get pods -A"  # run ad-hoc command
yukti run pod-watch --pane watchers  # target a specific pane
yukti run cluster-check --remote # run op on remote host
```

---

### yukti check

Run a health or sanity check.

**Usage:** `yukti check [check-id] [--all]`

| Option | Description |
|--------|-------------|
| `check-id` | ID of a check op in `ops.yml` (default: all checks) |
| `--all` | Run all defined checks |
| `--json` | Output results as JSON |

**What it does:** Runs check-type ops from `ops.yml` (or service health checks from `services.yml`) and reports pass/fail with output.

**Examples:**
```bash
yukti check                    # run all health checks for this instance
yukti check cluster-check      # run named check
yukti check --all --json       # all checks, JSON output
```

---

### yukti log

View the audit trail for this instance.

**Usage:** `yukti log [--type <type>] [--blast <level>] [--since <time>] [--tail]`

| Option | Description |
|--------|-------------|
| `--type` | Filter by entry type: `manual`, `auto`, `note`, `annotation` |
| `--blast` | Filter by blast radius: `low`, `medium`, `high` |
| `--since` | Show entries since time: `1h`, `today`, `2026-07-04` |
| `--tail` | Follow the log (like `tail -f`) |
| `--instance` | Log for a specific instance (default: current) |

**What it does:** Reads `~/.config/yantra/logs/<instance>.log` and prints a formatted audit trail with timestamps, command types, and blast-radius tags.

**Examples:**
```bash
yukti log                        # today's log for current instance
yukti log --type manual          # only commands you explicitly ran
yukti log --blast high           # only high blast-radius operations
yukti log --since 1h             # last hour
yukti log --tail                 # follow live
yukti log --instance wscs-staging  # log for a different instance
```

---

### yukti note

Append an annotation to the audit trail.

**Usage:** `yukti note <message>`

| Option | Description |
|--------|-------------|
| `message` | Free-text annotation string (quote it) |

**What it does:** Writes a `note` entry to the current instance's audit log with timestamp. Use for post-hoc context ("confirmed fix in staging") or before a risky operation.

**Examples:**
```bash
yukti note "deploying hotfix for auth bug"
yukti note "restarted svc1 due to OOM — watching"
yukti note "confirmed fix working in staging — will deploy to prod"
```

---

### yukti set

Set an environment variable in the current instance's live session.

**Usage:** `yukti set <KEY> <value> [--persist]`

| Option | Description |
|--------|-------------|
| `KEY` | Environment variable name |
| `value` | Value to set |
| `--persist` | Also write to the instance's secrets file |

**What it does:** Sets the variable in the current tmux session environment and optionally persists it to `~/.config/yantra/secrets/<instance>.env`. Without `--persist`, the value is session-scoped only.

**Examples:**
```bash
yukti set AUTH_TOKEN "Bearer eyJhbGc..."    # session-scoped
yukti set AUTH_TOKEN "Bearer eyJhbGc..." --persist  # persist to secrets file
yukti set DEBUG true
```

---

### yukti get

Print the value of an environment variable in the current instance.

**Usage:** `yukti get <KEY>`

**What it does:** Reads the variable from the instance's tmux environment and prints it. Useful for verifying `AUTH_TOKEN` and other dynamic secrets without exposing them in shell history.

**Examples:**
```bash
yukti get AUTH_TOKEN           # prints current token value
yukti get SVC1_URL             # prints resolved URL
yukti get DEBUG
```

---

### yukti add

Register a new instance (and optionally scaffold a new context from template).

**Usage:** `yukti add <name> --context <type> --path <dir> [options]`

| Option | Description |
|--------|-------------|
| `name` | Instance name (e.g., `wscs-dev`, `vidheya`) |
| `--context` | Context type to use (must exist in `~/yantra/contexts/`) |
| `--path` | Absolute path to the project directory |
| `--color` | Status bar color: `green`, `yellow`, `blue`, `cyan`, `red`, `magenta` |
| `--remote-host` | SSH target for remote instances (e.g., `ubuntu@192.168.1.151`) |
| `--remote-path` | Path on the remote host |
| `--remote-mode` | `thin` (host-driven) or `full` (yantra on remote) |
| `--scaffold` | Also copy `templates/<context>/` to `contexts/<name>/` for customization |

**What it does:** Adds an entry to `~/.config/yantra/registry.yml`. With `--scaffold`, it copies the matching template directory to `contexts/<name>/` so you can customize it without modifying the shared context.

**Examples:**
```bash
# Register with an existing shared context
yukti add wscs-dev --context wscloudservices --path ~/dev/WSCloudServices --color green

# Register a new instance + scaffold your own context from template
yukti add myservice-dev \
  --context services-project \
  --path ~/dev/myservice \
  --color cyan \
  --scaffold

# Register a remote instance
yukti add vidheya \
  --context vidheya \
  --path ~/repo/vidheya \
  --remote-host ubuntu@192.168.1.151 \
  --remote-path ~/repo/vidheya \
  --remote-mode full \
  --color blue
```

---

### yukti init

Initialize the yantra config directory and registry.

**Usage:** `yukti init [--force]`

| Option | Description |
|--------|-------------|
| `--force` | Reinitialize even if registry already exists (non-destructive) |

**What it does:** Creates `~/.config/yantra/` with subdirectories (`secrets/`, `logs/`, `state/`) and writes a default `registry.yml` if none exists. Safe to re-run.

**Examples:**
```bash
yukti init             # first-time setup
yukti init --force     # reset config dirs without touching registry data
```

---

### yukti install

Install yantra dependencies and optionally bootstrap a remote host.

**Usage:** `yukti install [--remote <host>] [--full] [--check]`

| Option | Description |
|--------|-------------|
| `--remote` | SSH target to bootstrap yantra on (e.g., `ubuntu@192.168.1.151`) |
| `--full` | Full install on remote: yantra + all tool deps (tmux, mise, etc.) |
| `--check` | Dry-run: check what's missing without installing |

**What it does:** Locally: installs Python deps and verifies tools. Remotely: SSHes to the target, clones yantra, and runs `install.sh` there. With `--full`, also installs tmux, mise, fzf, zoxide on the remote.

**Examples:**
```bash
yukti install                                    # local: install/verify deps
yukti install --check                            # local: check what's missing
yukti install --remote ubuntu@192.168.1.151      # bootstrap remote (thin mode)
yukti install --remote ubuntu@192.168.1.151 --full  # full remote install
```

---

## Scenarios

### Scenario A: First time setup and registering a project

**Goal:** Install yantra from scratch and get a local services project running.

```bash
# 1. Install yantra
git clone https://github.com/you/yantra ~/yantra
cd ~/yantra && ./install.sh

# 2. Wire into shell
echo 'source ~/yantra/init.sh --quiet' >> ~/.zshrc
echo "alias yt='source ~/yantra/init.sh'" >> ~/.zshrc
source ~/.zshrc

# 3. Register your project (using the shared wscloudservices context)
yukti add wscs-dev \
  --context wscloudservices \
  --path ~/dev/WSCloudServices \
  --color green

# 4. Add secrets — open the secrets file and populate it
$EDITOR ~/.config/yantra/secrets/wscs-dev.env
# Add lines like:
# export DB_PASSWORD=...
# export API_KEY=...

# 5. Activate the instance
yukti go wscs-dev
# → tmux session opens, status bar turns green, env is sourced

# 6. Start services
yukti up
# → svc1 starts, health check passes, svc2 starts

# 7. Set your auth token (from the frontend login)
yukti set AUTH_TOKEN "Bearer eyJhbGciOiJIUzI1..."

# 8. Run a GQL query using task
task gql:run QUERY=list-users
```

---

### Scenario B: Onboarding a new service (adding a new context)

**Goal:** Add a new project type (e.g., `myservice`) that doesn't have a context yet.

```bash
# 1. Scaffold a new context from the services-project template
yukti add myservice-dev \
  --context services-project \
  --path ~/dev/myservice \
  --color cyan \
  --scaffold
# → copies ~/yantra/templates/services-project/ to ~/yantra/contexts/myservice/
# → registers myservice-dev instance pointing to contexts/myservice

# 2. Edit services.yml to match your actual services
$EDITOR ~/yantra/contexts/myservice/services.yml
# Replace svc1 with your real service IDs
# Set actual cmd, build.cmd, and health check URLs

# 3. Edit watchers.yml to match your log patterns
$EDITOR ~/yantra/contexts/myservice/watchers.yml
# Add keyword patterns relevant to your service (error classes, etc.)

# 4. Edit tmuxp.yml to set up your preferred window layout
$EDITOR ~/yantra/contexts/myservice/tmuxp.yml
# Add windows for test runner, logs, etc.

# 5. Test it
yukti go myservice-dev
# → session opens with your layout
yukti up
# → services start per your services.yml
```

---

### Scenario C: Jumping between contexts

**Goal:** Quickly move between active instances from any terminal.

```bash
# Option 1: Smart jump alias — fzf picker if not in a session
yt
# → opens fzf showing all registered instances with their status

# Option 2: Direct activation
yukti go wscs-dev

# Option 3: Resume last
yukti go --last
# → re-attaches to whatever you were working on

# Once inside a session, the status bar shows:
# [wscs-dev] [green] | svc1: UP | svc2: UP | 14:32

# Confirm your context
yukti where
# Instance:  wscs-dev
# Context:   wscloudservices
# Path:      /Users/you/dev/WSCloudServices
# Session:   wscs-dev (active)
```

---

### Scenario D: Setting up a remote project (vidheya-style)

**Goal:** Register and connect to a remote k8s/IaC project via SSH.

```bash
# 1. Register the remote instance
yukti add vidheya \
  --context vidheya \
  --path ~/repo/vidheya \
  --remote-host ubuntu@192.168.1.151 \
  --remote-path ~/repo/vidheya \
  --remote-mode full \
  --color blue

# 2. Bootstrap yantra on the remote (full install)
yukti install --remote ubuntu@192.168.1.151 --full
# → SSHes in, installs tmux/mise/fzf/zoxide, clones yantra, runs install.sh

# 3. Add remote secrets
$EDITOR ~/.config/yantra/secrets/vidheya.env
# export KUBECONFIG=/home/ubuntu/.kube/config
# export PROXMOX_TOKEN=...

# 4. Activate — yantra SSHes in and attaches to the remote session
yukti go vidheya
# → SSH to ubuntu@192.168.1.151
# → tmuxp loads on the remote
# → you are now in a blue-coded session on the remote machine

# 5. Run ops
yukti run pod-watch           # start k8s event watcher
yukti check cluster-check     # run health check
```

---

### Scenario E: Working with WSCloudServices — the dev loop

**Goal:** Full development cycle: start, auth, change code, rebuild, verify.

```bash
# 1. Activate
yukti go wscs-dev

# 2. Start services in defined order
yukti up
# → svc1 starts → health check passes → svc2 starts → health check passes

# 3. Open the frontend, log in, copy the Bearer token from DevTools

# 4. Set the token in your session
yukti set AUTH_TOKEN "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

# 5. Run a GQL query
task gql:run QUERY=list-users
# → uses AUTH_TOKEN from the session env

# 6. Make a code change to svc1 in your editor

# 7. Rebuild — yantra stops svc2, rebuilds svc1, restarts both in order
yukti build svc1
# → stopping svc2...
# → running build.cmd for svc1...
# → starting svc1 → health check → starting svc2 → health check

# 8. Check the bubble pane — log watcher highlights errors/exceptions
# (bubble pane shows last 200 matched lines from all watchers)

# 9. Review the audit trail for this session
yukti log
# → timestamped list of every up/build/run/set with blast-radius tags
```

---

### Scenario F: Running parallel instances

**Goal:** Work on dev and staging side-by-side with visual distinction.

```bash
# Terminal 1
yukti go wscs-dev
# → green status bar: [wscs-dev] | svc1: UP | svc2: UP

# Open a new terminal tab (or tmux window outside yantra)
# Terminal 2
yukti go wscs-staging
# → yellow status bar: [wscs-staging] | svc1: UP | svc2: UP

# Both sessions are live simultaneously
# Switch between them with tmux (prefix + s) or:
yukti go           # fzf shows both: wscs-dev (active), wscs-staging (active)

# Check both at once
yukti ls --active
# wscs-dev      wscloudservices   ~/dev/WSCloudServices   active (green)
# wscs-staging  wscloudservices   ~/dev/WSCloudServices   active (yellow)
```

---

### Scenario G: Audit trail usage

**Goal:** Use the audit log during and after a risky operation.

```bash
# Pre-annotate before doing something significant
yukti note "deploying hotfix for auth token expiry bug"

# Run your operations — they are auto-logged
yukti build svc1
yukti restart svc2

# Post-annotate after observing the result
yukti note "confirmed fix working in wscs-staging — will promote"

# Review today's log
yukti log
# 14:31:02  [note]   deploying hotfix for auth token expiry bug
# 14:31:15  [auto]   [HIGH] build svc1
# 14:32:44  [auto]   [LOW]  restart svc2
# 14:33:10  [note]   confirmed fix working in wscs-staging — will promote

# Filter to just risky operations
yukti log --blast high

# Filter to just your manual commands (not auto-triggered)
yukti log --type manual

# Review ops from the last hour
yukti log --since 1h
```

---

## Adding a New Context

A context defines how a *type* of project runs. Create one when you have a project category not covered by existing contexts.

```
1. Create the context directory:

   mkdir -p ~/yantra/contexts/mycontext

   OR copy from the nearest template:

   cp -r ~/yantra/templates/services-project ~/yantra/contexts/mycontext

2. Edit the files in ~/yantra/contexts/mycontext/:

   context.env     — Set CONTEXT_TYPE, default ports, any type-level env vars
   services.yml    — Define your services: cmd, build.cmd, health check
   watchers.yml    — Define log patterns to highlight and bubble
   tmuxp.yml       — Define your tmux windows and pane layout
   Taskfile.yml    — Add project-specific tasks; include _base for yantra tasks

3. Register an instance:

   yukti add mycontext-dev \
     --context mycontext \
     --path ~/dev/myproject \
     --color cyan

4. Test it:

   yukti go mycontext-dev
   yukti ps          # should show services defined in services.yml
   yukti up          # should start services per services.yml
```

### File authoring notes

**services.yml:** Each service needs at minimum an `id`, `cmd`, and `ready` block. Use `groups` to define named subsets for `yukti up <group>`. Dependencies are expressed with `depends_on: [<id>]` on a service.

**tmuxp.yml:** `session_name: "${YANTRA_INSTANCE}"` is required — it must use the instance name so multiple instances don't collide. Always include `before_script: tmux source-file "${YANTRA_HOME}/contexts/_base/tmux.status.conf"` to get the status bar.

**Taskfile.yml:** Always include the base:

```yaml
includes:
  base:
    taskfile: "${YANTRA_HOME}/contexts/_base/Taskfile.base.yml"
    optional: false
```

This gives you the standard `yukti:*` tasks and lets you override or extend them.

---

## Adding a New yukti Command

`yukti` subcommands are defined in `~/yantra/bin/yukti` (Python). To add a new command:

```
1. Add the argument parser in setup_parser():

   p_mycommand = subparsers.add_parser("mycommand", help="one-line description")
   p_mycommand.add_argument("target", nargs="?", help="target service or op")
   p_mycommand.add_argument("--option", help="what this option does")

2. Add the dispatch function:

   def cmd_mycommand(args):
       instance = get_current_instance()   # from $YANTRA_INSTANCE
       ctx = load_context(instance)
       # ... implementation ...
       return 0  # exit code

3. Register in the dispatch table:

   COMMANDS = {
       ...
       "mycommand": cmd_mycommand,
   }
```

### Accessing common subsystems

```python
# Read service definitions
from impl.python.services import load_services_yml
services = load_services_yml(ctx.context_type)

# Interact with tmux via libtmux
import libtmux
server = libtmux.Server()
session = server.find_where({"session_name": instance})
pane = session.find_where({"pane_title": "bubble"})
pane.send_keys("echo hello")

# Run a subprocess with the instance env
import subprocess
env = {**os.environ, **ctx.env}
subprocess.run(["some-tool", "--flag"], env=env)

# Call orchestrate.py or healthcheck.py
subprocess.run(["python3", f"{YANTRA_HOME}/impl/python/orchestrate.py",
                "--action", "start", "--service", "svc1"], env=env)
```

### Writing audit records

```python
# Option A: subprocess call to audit.py
subprocess.run([
    "python3", f"{YANTRA_HOME}/impl/python/audit.py",
    "--instance", instance,
    "--type", "manual",
    "--blast", "low",
    "--message", f"mycommand {args.target}"
])

# Option B: direct import
from impl.python.audit import write_audit_record
write_audit_record(instance, type="manual", blast="low",
                   message=f"mycommand {args.target}")
```

### Testing your command

```bash
yukti mycommand --option value
yukti log --type manual   # confirm it was recorded
```

---

## Remote Setup

yantra supports two remote modes. Choose based on where you want execution to live.

### Thin mode (host-driven)

The control machine (your laptop) runs yantra. Commands execute locally but operate on remote resources over SSH. The remote host does not need yantra installed.

**Use when:**
- Remote is a simple VM or container with no persistent terminal need
- You want the remote to be stateless
- The project is small and SSH latency is acceptable

**Setup:**
```bash
# 1. Register with thin mode
yukti add myremote-dev \
  --context devops-project \
  --path ~/projects/myremote \
  --remote-host user@remote.host \
  --remote-path ~/repo/myproject \
  --remote-mode thin \
  --color magenta

# 2. SSH ControlMaster (speeds up repeated connections significantly)
# Add to ~/.ssh/config:
Host remote.host
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 10m

# 3. Activate — sessions run locally, ops that need remote use SSH
yukti go myremote-dev
yukti run cluster-check   # SSHes for this command, returns output locally
```

### Full mode (yantra on remote)

The remote host runs yantra. `yukti go` SSHes in and attaches to a tmux session running *on the remote*. All execution happens there. Your terminal is a thin SSH client.

**Use when:**
- Remote has persistent processes (k8s ops box, always-on dev server)
- You need persistent tmux sessions that survive disconnection
- Multiple people may share the remote environment (homelab, bastion)
- Low local resources — offload everything

**Setup:**
```bash
# 1. Bootstrap yantra on the remote
yukti install --remote ubuntu@192.168.1.151 --full
# → installs tmux, mise, fzf, zoxide, python3 on remote
# → clones yantra to ~/yantra on remote
# → runs install.sh on remote

# 2. Register the instance
yukti add vidheya \
  --context vidheya \
  --path ~/repo/vidheya \
  --remote-host ubuntu@192.168.1.151 \
  --remote-path ~/repo/vidheya \
  --remote-mode full \
  --color blue

# 3. Add secrets (stored locally, synced on attach)
$EDITOR ~/.config/yantra/secrets/vidheya.env

# 4. Activate — yukti go SSHes and runs tmuxp on the remote
yukti go vidheya
```

### SSH ControlMaster (recommended for both modes)

Add to `~/.ssh/config` for all remote hosts:

```
Host 192.168.1.*
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 15m
  ServerAliveInterval 30
  ServerAliveCountMax 3
```

This keeps an SSH multiplexer alive so successive `yukti` commands that SSH don't pay the handshake cost each time.

---

## Audit Trail

Every yantra operation is logged to `~/.config/yantra/logs/<instance>.log`. Entries have a type, blast radius, and timestamp.

### Entry types

| Type | When logged |
|------|-------------|
| `auto` | Commands run by yantra itself (build cascades, health check retries) |
| `manual` | Commands you explicitly ran via yukti |
| `note` | Annotations you added with `yukti note` |
| `annotation` | The `## comment` pattern (see below) |

### Blast radius tags

| Level | Meaning |
|-------|---------|
| `low` | Read-only or reversible (ps, log, ls, check) |
| `medium` | Service restart, config change |
| `high` | Build, deploy, teardown, remote ops |

### The `##` annotation pattern

Prefix any shell command with `## your note` and yantra captures the comment as a pre-annotation in the log, automatically linked to the next command:

```bash
## deploying hotfix for auth bug
yukti build svc1 --cascade
```

Log output:
```
14:31:01  [annotation]   deploying hotfix for auth bug
14:31:02  [manual][HIGH] build svc1 --cascade
```

### Filtering the log

```bash
yukti log                          # today's full log
yukti log --type manual            # only explicit commands
yukti log --blast high             # only high blast-radius ops
yukti log --since today            # today only (explicit)
yukti log --since 2h               # last 2 hours
yukti log --since 2026-07-04       # specific date
yukti log --tail                   # follow live
yukti log --instance wscs-staging  # another instance
```

---

## Troubleshooting

**tmux session already exists (attach fails)**

```bash
# Kill the stuck session and re-create it
tmux kill-session -t wscs-dev
yukti go wscs-dev
```

**Registry not found / yukti init error**

```bash
yukti init
# Creates ~/.config/yantra/ and default registry.yml
```

**Python deps missing (import errors)**

```bash
cd ~/yantra
pip3 install -r impl/python/requirements.txt
```

**Context not found (unknown context type)**

```bash
yukti ls           # check registered context type
ls ~/yantra/contexts/  # verify the context directory exists
# If missing, copy from template:
cp -r ~/yantra/templates/services-project ~/yantra/contexts/<your-context>
```

**Remote SSH issues (timeout / permission denied)**

```bash
# Test SSH manually first
ssh ubuntu@192.168.1.151 echo ok

# Check your SSH key is loaded
ssh-add -l

# Verify ControlMaster socket isn't stale
ls ~/.ssh/cm-*
rm ~/.ssh/cm-ubuntu@192.168.1.151:22   # if stale
```

**Status bar not showing (tmux version too old)**

```bash
tmux -V           # need >= 2.6
brew upgrade tmux  # macOS
```

**Service health check times out**

- Check that the service actually started: `yukti ps --verbose`
- Verify the URL in `services.yml` `ready.url` is reachable manually: `curl -v <url>`
- Increase timeout: edit `ready.timeout` in `services.yml`

**fzf picker is empty**

```bash
yukti ls           # verify instances are registered
yukti init         # re-initialize if registry is corrupt
```

**`yukti set` not persisting across sessions**

Without `--persist`, `yukti set` is session-scoped only. Re-run with `--persist` to write to the secrets file, or add the export directly to `~/.config/yantra/secrets/<instance>.env`.

---

## Architecture

yantra is composed of:

- `bin/yukti` — Python CLI entrypoint; all subcommands live here
- `impl/python/` — Subsystems: `orchestrate.py` (service lifecycle), `healthcheck.py`, `audit.py`, `watchers.py`
- `lib/` — Shell helpers sourced by `init.sh`
- `contexts/` — Installed context types (each a directory of config files)
- `templates/` — Starter scaffolds for `yukti add --scaffold`
- `init.sh` — Shell integration: sets `YANTRA_HOME`, `PATH`, completions
- `install.sh` — One-time bootstrap

For a deeper architectural walkthrough — design decisions, the session lifecycle state machine, how watchers interact with the bubble pane, the registry schema — see [`docs/yantra.md`](docs/yantra.md).
