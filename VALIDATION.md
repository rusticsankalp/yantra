# VALIDATION.md — yantra acceptance test plan

yantra manages dev project contexts as isolated tmux sessions. `yukti` is its CLI. This document
is a step-by-step test plan to verify that a fresh installation works correctly, get familiar with
the system through hands-on use, and sign off the codebase before customising it.

## How to use this document

Work through the phases in order. Check each item as you go. Record failures with the exact
command, actual output, and expected output. A phase is complete when all checkboxes are ticked.

Symbols:
- `✓` — pass (output matched expected)
- `✗` — fail (note the error below the item)
- `⚠` — partial or warning (output differed in a minor or known way)

**Estimated time: ~45 minutes** for all phases on a machine with dependencies already installed.

---

## Phase 0: Prerequisites (~5 minutes)

Verify each required tool is present before running install.sh. Install any that are missing.

**tmux** (need >= 2.6):
```bash
tmux -V
# Expected: tmux 3.x  (or any 2.6+)
```
- [ ] tmux is present and version >= 2.6

**python3** (need >= 3.8):
```bash
python3 --version
# Expected: Python 3.8.x or higher
```
- [ ] python3 is present and version >= 3.8

**tmuxp**:
```bash
tmuxp --version
# Expected: any version string
```
- [ ] tmuxp is present (install: `pip3 install tmuxp` if missing)

**fzf**:
```bash
fzf --version
# Expected: 0.x.x or higher
```
- [ ] fzf is present (install: `brew install fzf` or `apt-get install fzf`)

**jq**:
```bash
jq --version
# Expected: jq-1.x
```
- [ ] jq is present (install: `brew install jq` or `apt-get install jq`)

**mise** (optional but recommended):
```bash
mise --version
# Expected: mise x.x.x — if not installed, yantra still works; YANTRA_IMPL will need manual export
```
- [ ] mise is present, or note that it is absent (non-blocking)

---

## Phase 1: Repository and Installation (~10 minutes)

### 1.1 Verify repo structure

```bash
ls ~/yantra/bin/
# Expected: healthcheck  orchestrate  switch  watch-logs  yukti
```
- [ ] All five bin files are present

```bash
ls ~/yantra/lib/
# Expected: audit.sh  bubble.sh  context.sh  health.sh  remote.sh  session.sh
```
- [ ] All six lib files are present

```bash
ls ~/yantra/contexts/
# Expected: _base  vidheya  wscloudservices
```
- [ ] All three context directories are present

```bash
cat ~/yantra/.mise.toml
# Expected: contains  YANTRA_IMPL = "python"
```
- [ ] `.mise.toml` has `YANTRA_IMPL = "python"` in the `[env]` block

### 1.2 Run install.sh

```bash
cd ~/yantra && ./install.sh
```

Expected output (abbreviated):
```
  yantra installer
  home: /Users/<you>/yantra
  config: /Users/<you>/.config/yantra

Checking required tools
  ✓  tmux
  ✓  tmuxp
  ✓  fzf
  ...

Creating config directories
  ✓  created /Users/<you>/.config/yantra          (or: exists ...)
  ✓  created /Users/<you>/.config/yantra/secrets
  ✓  created /Users/<you>/.config/yantra/sessions
  ✓  created /Users/<you>/.config/yantra/audit

Installing Python dependencies
  ✓  pip install complete

Setting executable permissions
  ✓  chmod +x yukti
  ...

  Setup complete.
```

- [ ] `./install.sh` exits 0 with no error lines
- [ ] Any missing-tool warnings appear but do not abort the run

```bash
ls ~/.config/yantra/
# Expected: audit  registry.yml  secrets  sessions
```
- [ ] All four entries exist under `~/.config/yantra/`

```bash
cat ~/.config/yantra/registry.yml
# Expected first meaningful line: instances: {}
```
- [ ] registry.yml is present and contains `instances: {}`

```bash
ls -l ~/yantra/bin/
# Expected: each file shows -rwxr-xr-x (x bit set)
```
- [ ] All files in `bin/` are executable

### 1.3 Python dependencies

```bash
python3 -c "import yaml, requests, libtmux, rich, dateutil; print('OK')"
# Expected: OK
```
- [ ] All five packages import cleanly

### 1.4 Source init.sh

In a **new terminal tab** (or a fresh shell without yantra already in PATH):

```bash
source ~/yantra/init.sh --quiet
# Expected: no output (--quiet suppresses the session-selection prompt)
```
- [ ] Sourcing produces no error output

```bash
echo $YANTRA_HOME
# Expected: /Users/<you>/yantra
```
- [ ] `YANTRA_HOME` is set to the yantra repo path

```bash
echo $YANTRA_CONFIG
# Expected: /Users/<you>/.config/yantra
```
- [ ] `YANTRA_CONFIG` is set to `~/.config/yantra`

```bash
which yukti
# Expected: /Users/<you>/yantra/bin/yukti
```
- [ ] `yukti` is on PATH and resolves to `bin/yukti`

---

## Phase 2: Core CLI (~10 minutes)

All commands in this phase require that `source ~/yantra/init.sh --quiet` has been run in the
current shell. If you opened a new terminal, re-source it first.

### 2.1 Help and version

```bash
yukti --help
# Expected: usage line + list of subcommands including: go, ls, where, up, down,
#           restart, build, ps, run, check, log, note, set, get, add, init, install, version
```
- [ ] `yukti --help` shows a subcommand list without errors

```bash
yukti version
# Expected: yantra 0.1.0-dev
# (If a VERSION file exists in ~/yantra/, it prints that instead.)
```
- [ ] `yukti version` prints a version string and exits 0

```bash
yukti go --help
# Expected: shows "instance" positional arg and "--last" option
```
- [ ] `yukti go --help` shows the instance argument and --last flag

```bash
yukti log --help
# Expected: shows -i/--instance, --since, --type, --search, --blast, --exit, --annotated, --json
```
- [ ] `yukti log --help` shows all filter options

```bash
yukti add --help
# Expected: shows --context (required), --path, --label, --color, --remote-host options
```
- [ ] `yukti add --help` shows registration options

### 2.2 Init

```bash
yukti init
# Expected (roughly):
#   ok  /Users/<you>/.config/yantra
#   ok  /Users/<you>/.config/yantra/sessions
#   ok  /Users/<you>/.config/yantra/audit
#   exists   /Users/<you>/.config/yantra/registry.yml
#
#   Tool check:
#     ✓  tmux
#     ✓  fzf
#     ✓  tmuxp
#     ✓  python3
#
#   yantra init complete.
```
- [ ] Output ends with `yantra init complete.`
- [ ] No directory is missing or errored

### 2.3 Register an instance

```bash
yukti add test-instance --context wscloudservices --path /tmp --label test --color green
# Expected: Added instance 'test-instance'  context=wscloudservices
```
- [ ] Output shows `Added instance 'test-instance'  context=wscloudservices`

```bash
cat ~/.config/yantra/registry.yml
# Expected: test-instance entry with context, label, color, local_path fields, e.g.:
#   instances:
#     test-instance:
#       context: wscloudservices
#       label: test
#       color: green
#       local_path: /tmp
```
- [ ] registry.yml contains the test-instance entry with all four fields

### 2.4 List instances

```bash
yukti ls
# Expected: table or plain listing showing:
#   test-instance   wscloudservices   test   ○ stopped   green
```
- [ ] test-instance appears with context wscloudservices, label test, status stopped, color green

```bash
yukti ls --json | python3 -c "import json,sys; d=json.load(sys.stdin); print(list(d['instances'].keys()))"
# Expected: ['test-instance']
```
- [ ] `yukti ls --json` produces valid JSON with an `instances` key

### 2.5 Where (outside an active instance)

```bash
unset YANTRA_INSTANCE
yukti where
# Expected: exits non-zero; stderr shows "No active instance (YANTRA_INSTANCE not set)"
# There should be NO Python traceback — a clean error message only.
echo "exit code: $?"
# Expected: exit code: 1
```
- [ ] `yukti where` exits 1 with a graceful error message (no crash)

---

## Phase 3: Registry operations (~5 minutes)

```bash
python3 ~/yantra/impl/python/registry.py list
# Expected: one space-separated line per instance:
#   test-instance wscloudservices test green local stopped
```
- [ ] test-instance line appears with all six fields (name context label color kind status)

```bash
python3 ~/yantra/impl/python/registry.py list --json | python3 -c "import json,sys; d=json.load(sys.stdin); print('instances key present:', 'instances' in d)"
# Expected: instances key present: True
```
- [ ] `registry.py list --json` produces valid JSON with an `instances` key

```bash
python3 ~/yantra/impl/python/registry.py get test-instance
# Expected: JSON object with context, label, color, local_path, status fields, e.g.:
#   {"context": "wscloudservices", "label": "test", "color": "green", "local_path": "/tmp", "status": "stopped"}
```
- [ ] `registry.py get test-instance` returns valid JSON with expected fields

---

## Phase 4: Health checks (~5 minutes)

These tests use public endpoints and an unused local port. They do not require tmux or any
running services.

### 4.1 HTTP check — should pass

```bash
python3 ~/yantra/impl/python/healthcheck.py http \
  --url https://httpbin.org/status/200 \
  --timeout 10
# Expected: progress dots on stderr as it polls, then "READY" on stdout, exit code 0
echo "exit: $?"
```
- [ ] stdout is `READY`
- [ ] exit code is 0

### 4.2 Port check — should timeout

```bash
python3 ~/yantra/impl/python/healthcheck.py port \
  --host localhost --port 59999 --timeout 5
# Expected: progress dots on stderr for ~5 seconds, then "TIMEOUT" on stdout, exit code 1
echo "exit: $?"
```
- [ ] stdout is `TIMEOUT`
- [ ] exit code is 1

### 4.3 HTTP with body pattern — should pass

```bash
python3 ~/yantra/impl/python/healthcheck.py http \
  --url https://httpbin.org/json \
  --expect "slideshow" \
  --timeout 10
# Expected: "READY", exit 0
echo "exit: $?"
```
- [ ] stdout is `READY`
- [ ] exit code is 0

### 4.4 HTTP with wrong pattern — should timeout

```bash
python3 ~/yantra/impl/python/healthcheck.py http \
  --url https://httpbin.org/json \
  --expect "NOTHERE_XXXXXX" \
  --timeout 5
# Expected: "TIMEOUT", exit 1
echo "exit: $?"
```
- [ ] stdout is `TIMEOUT`
- [ ] exit code is 1

---

## Phase 5: Audit trail (~5 minutes)

Set up an isolated config for this phase so test records do not pollute `~/.config/yantra/`:

```bash
export YANTRA_HOME=~/yantra
export YANTRA_CONFIG=/tmp/yantra-validation
mkdir -p /tmp/yantra-validation
echo "instances: {}" > /tmp/yantra-validation/registry.yml
```

### 5.1 Write a record

```bash
python3 ~/yantra/impl/python/audit.py write \
  --instance test-instance \
  --cmd "yukti build svc1" \
  --exit 0 \
  --duration 4500 \
  --type manual
# Expected: no output, no error, exit 0
echo "exit: $?"
```
- [ ] Command is silent and exits 0

### 5.2 Query records

```bash
python3 ~/yantra/impl/python/audit.py query --instance test-instance
# Expected: formatted output showing a record with:
#   - today's date header
#   - "manual" type
#   - "yukti build svc1" command
#   - ✓ status (exit 0)
#   - ~4.5s duration
```
- [ ] Record appears in the output with correct type, command, and status

### 5.3 Annotate with a note

```bash
python3 ~/yantra/impl/python/audit.py note \
  --instance test-instance \
  --text "validated during onboarding"
# Expected: no output, exit 0
```
- [ ] Command is silent and exits 0

### 5.4 Query again — verify note

```bash
python3 ~/yantra/impl/python/audit.py query --instance test-instance
# Expected: same record now shows "validated during onboarding" below the command line
```
- [ ] The note text appears under the record

### 5.5 JSON output

```bash
python3 ~/yantra/impl/python/audit.py query --instance test-instance --json | \
  python3 -c "
import json, sys
records = json.load(sys.stdin)
print('record count:', len(records))
print('fields present:', sorted(records[0].keys()))
"
# Expected:
#   record count: 1
#   fields present: ['blast_radius', 'cmd', 'context', 'duration_ms', 'exit',
#                    'instance', 'pane', 'summary', 'ts', 'type', 'window']
```
- [ ] Output is valid JSON
- [ ] Record contains ts, instance, cmd, exit, summary, type, duration_ms fields

### 5.6 Write a high blast-radius command

```bash
python3 ~/yantra/impl/python/audit.py write \
  --instance test-instance \
  --cmd "terraform apply -auto-approve" \
  --exit 0 \
  --duration 30000 \
  --type manual

python3 ~/yantra/impl/python/audit.py query --instance test-instance
```

Expected: two records appear. The `terraform apply` record will NOT have an auto-filled
summary because `audit.py` currently looks for the patterns file at
`$YANTRA_HOME/_base/audit-patterns.yml`, but the file lives at
`$YANTRA_HOME/contexts/_base/audit-patterns.yml` (wrong path). Additionally, the YAML key
is `match:` but the parser reads `pattern:`. Both issues mean auto-pattern matching is
currently inoperative. The record will be written successfully with an empty summary.

- [ ] `terraform apply` record appears in the query output (write succeeded)
- [ ] ⚠ Auto-summary is absent (known bug: wrong path + key mismatch in `audit.py:match_audit_patterns`)

### 5.7 Restore YANTRA_CONFIG

```bash
export YANTRA_CONFIG=~/.config/yantra
```
- [ ] Restored (confirm: `echo $YANTRA_CONFIG` shows `~/.config/yantra`)

---

## Phase 6: Shell library functions (~5 minutes)

Re-source init.sh if you are in a fresh shell:

```bash
source ~/yantra/init.sh --quiet
```

### 6.1 Session KV store

```bash
export YANTRA_INSTANCE=test-instance
yantra_set TEST_KEY "hello-yantra"
# Expected: no output (yantra_set is silent on success)
```
- [ ] `yantra_set` exits 0 with no output

```bash
yantra_get TEST_KEY
# Expected: hello-yantra
```
- [ ] echoes `hello-yantra`

```bash
cat ~/.config/yantra/sessions/test-instance.env
# Expected: contains the line:  TEST_KEY=hello-yantra
```
- [ ] Session env file contains `TEST_KEY=hello-yantra`

### 6.2 Color mapping

```bash
source ~/yantra/lib/context.sh
yantra_color_to_hex green
echo "BG=$YANTRA_INSTANCE_BG FG=$YANTRA_INSTANCE_FG"
# Expected: BG=#005f00 FG=#ffffff
```
- [ ] BG is `#005f00`
- [ ] FG is `#ffffff`

```bash
yantra_color_to_hex cyan
echo "BG=$YANTRA_INSTANCE_BG FG=$YANTRA_INSTANCE_FG"
# Expected: BG=#005f5f FG=#ffffff
```
- [ ] BG is `#005f5f` for cyan

---

## Phase 7: Config file validation (~5 minutes)

All YAML files must parse without error:

```bash
python3 -c "
import yaml, os
os.chdir(os.path.expanduser('~/yantra'))
files = [
    'contexts/_base/audit-patterns.yml',
    'contexts/_base/watchers.base.yml',
    'contexts/_base/audit-ignore.yml',
    'contexts/wscloudservices/services.yml',
    'contexts/wscloudservices/watchers.yml',
    'contexts/vidheya/ops.yml',
    'contexts/vidheya/watchers.yml',
]
for f in files:
    with open(f) as fh:
        yaml.safe_load(fh)
    print(f'OK: {f}')
"
# Expected: seven OK lines, one per file, no exceptions
```
- [ ] All seven files print `OK: <path>` without errors

Validate Taskfile syntax (skip if `task` is not installed):

```bash
# Run from a context directory that has a Taskfile.yml
cd ~/yantra/contexts/wscloudservices && task --list-all
# Expected: list of available tasks (build, where, ps, status, log, etc.)
```
- [ ] task --list-all shows available tasks, or ⚠ task is not installed (non-blocking)

---

## Phase 8: Full flow simulation (~10 minutes)

This phase runs an end-to-end workflow without requiring real services or a live tmux session.
Ensure these are set in your shell before starting:

```bash
source ~/yantra/init.sh --quiet
export YANTRA_HOME=~/yantra
export YANTRA_CONFIG=~/.config/yantra
```

### Flow 1: Register → list → inspect

```bash
yukti add flow-test \
  --context wscloudservices \
  --path /tmp \
  --label flowtest \
  --color cyan
# Expected: Added instance 'flow-test'  context=wscloudservices

yukti ls
# Expected: table shows both test-instance and flow-test;
#           flow-test row has context=wscloudservices, label=flowtest, color=cyan

python3 ~/yantra/impl/python/registry.py get flow-test
# Expected: JSON object with: context, label, color, local_path, status fields
```
- [ ] `yukti add` prints the confirmation line
- [ ] `yukti ls` shows flow-test with color cyan
- [ ] `registry.py get flow-test` returns valid JSON with correct fields

### Flow 2: Audit a simulated session

```bash
python3 ~/yantra/impl/python/audit.py write \
  --instance flow-test \
  --cmd "yukti up svc1" \
  --exit 0 --duration 8000 --type auto --summary "svc1 started"

python3 ~/yantra/impl/python/audit.py write \
  --instance flow-test \
  --cmd "task gql:run QUERY=list-users" \
  --exit 0 --duration 300 --type manual

python3 ~/yantra/impl/python/audit.py write \
  --instance flow-test \
  --cmd "yukti build svc1" \
  --exit 0 --duration 5200 --type manual

yukti log --instance flow-test
# Expected: three records under today's date for flow-test:
#   - yukti up svc1       type=auto    ✓  8.0s   summary: svc1 started
#   - task gql:run ...    type=manual  ✓  0.3s
#   - yukti build svc1    type=manual  ✓  5.2s   (no auto-summary — known audit-patterns bug)
```
- [ ] Log shows 3 records
- [ ] `yukti up svc1` record shows `auto` type and `svc1 started` summary
- [ ] `task gql:run` record shows `manual` type and ~0.3s duration
- [ ] `yukti build svc1` record shows `manual` type; ⚠ no auto-summary (known bug)

### Flow 3: Session KV round-trip

```bash
export YANTRA_INSTANCE=flow-test
yantra_set AUTH_TOKEN "Bearer test-token-abc"
yantra_get AUTH_TOKEN
# Expected: Bearer test-token-abc
```
- [ ] `yantra_get` returns `Bearer test-token-abc`

```bash
cat ~/.config/yantra/sessions/flow-test.env
# Expected: line containing  AUTH_TOKEN=Bearer test-token-abc
```
- [ ] Session env file contains the AUTH_TOKEN line

You can also test via the CLI commands (equivalent path, different interface):

```bash
yukti set MY_KEY "cli-value"
# Expected: Set MY_KEY=cli-value

yukti get MY_KEY
# Expected: cli-value
```
- [ ] `yukti set` prints `Set MY_KEY=cli-value`
- [ ] `yukti get` echoes `cli-value`

### Flow 4: Audit filter tests

```bash
yukti log --instance flow-test --type manual
# Expected: 2 records (task gql:run and yukti build svc1)
```
- [ ] Shows exactly 2 records

```bash
yukti log --instance flow-test --type auto
# Expected: 1 record (yukti up svc1)
```
- [ ] Shows exactly 1 record

```bash
yukti log --instance flow-test --search "gql"
# Expected: 1 record matching "task gql:run QUERY=list-users"
```
- [ ] Only the gql record appears

```bash
yukti log --instance flow-test --json | python3 -c "
import json, sys
records = json.load(sys.stdin)
print('record count:', len(records))
print('first cmd:', records[0]['cmd'])
"
# Expected:
#   record count: 3
#   first cmd: yukti up svc1
```
- [ ] `--json` produces a valid JSON array with 3 records

### Flow 5: Orchestrate help (without tmux)

```bash
python3 ~/yantra/impl/python/orchestrate.py --help
# Expected: usage and subcommand list (start, stop, status, restart, build, wait)
```
- [ ] `orchestrate.py --help` prints help without errors

```bash
python3 ~/yantra/impl/python/orchestrate.py start --help
# Expected: shows --context, --service, --group options
```
- [ ] `orchestrate.py start --help` shows expected options

```bash
python3 ~/yantra/impl/python/orchestrate.py status --help
# Expected: shows --context, --json options
```
- [ ] `orchestrate.py status --help` shows expected options

Minor failures here (e.g. missing subcommands in help output) are acceptable — orchestrate.py
requires an active tmux session for non-help commands.

---

## Phase 9: Context file structure (~3 minutes)

### 9.1 Verify example context directories

```bash
for ctx in wscloudservices vidheya; do
  echo "=== $ctx ==="; ls ~/yantra/contexts/$ctx/
done
```

Expected output:
```
=== wscloudservices ===
Taskfile.yml  context.env  services.yml  tmuxp.yml  watchers.yml

=== vidheya ===
Taskfile.yml  context.env  ops.yml  tmuxp.yml  watchers.yml
```

- [ ] wscloudservices has: `context.env`, `services.yml`, `watchers.yml`, `tmuxp.yml`, `Taskfile.yml`
- [ ] vidheya has: `context.env`, `ops.yml`, `watchers.yml`, `tmuxp.yml`, `Taskfile.yml`

Also verify the base layer:

```bash
ls ~/yantra/contexts/_base/
# Expected: audit-ignore.yml  audit-patterns.yml  context.env  Taskfile.base.yml  tmux.status.conf  watchers.base.yml
```
- [ ] `_base/` has audit-patterns.yml, audit-ignore.yml, watchers.base.yml, Taskfile.base.yml

### 9.2 Spot-check services.yml schema

```bash
python3 - <<'EOF'
import os, yaml

with open(os.path.expanduser('~/yantra/contexts/wscloudservices/services.yml')) as f:
    s = yaml.safe_load(f)

svcs = {svc['id']: svc for svc in s['services']}
print('services:', list(svcs.keys()))
print('svc2 depends_on:', svcs['svc2'].get('depends_on'))
print('groups:', s.get('groups'))
EOF
# Expected:
#   services: ['svc1', 'svc2', 'frontend']
#   svc2 depends_on: ['svc1']
#   groups: {'backend': ['svc1', 'svc2'], 'all': ['svc1', 'svc2', 'frontend']}
```
- [ ] services list is `['svc1', 'svc2', 'frontend']`
- [ ] svc2 depends_on is `['svc1']`
- [ ] groups map contains backend and all

---

## Sign-off

After completing all phases, fill in the results:

| Phase | Result | Notes |
|-------|--------|-------|
| 0 Prerequisites | ✓/✗ | |
| 1 Installation | ✓/✗ | |
| 2 Core CLI | ✓/✗ | |
| 3 Registry | ✓/✗ | |
| 4 Health checks | ✓/✗ | |
| 5 Audit trail | ✓/✗ | |
| 6 Shell libs | ✓/✗ | |
| 7 Config files | ✓/✗ | |
| 8 Full flow | ✓/✗ | |
| 9 Context structure | ✓/✗ | |

**Tester:** _________________________ &nbsp; **Date:** _____________

**Acceptance criteria:** All Phase 1–7 checks pass. Phase 8 Flows 1–4 pass. Phase 8 Flow 5
(orchestrate help) is informational only — minor output differences are acceptable. Known ⚠
items in Phase 5.6 and Phase 8 Flow 2 (audit auto-patterns inoperative) do not block acceptance.

---

## Known issues at time of writing (2026-07-04)

**Audit auto-pattern matching is inoperative** (Phase 5.6, Phase 8 Flow 2):

`impl/python/audit.py` in `match_audit_patterns()` constructs the path as:
```
Path(yantra_home) / "_base" / "audit-patterns.yml"
```
The actual file lives at `contexts/_base/audit-patterns.yml`. Additionally, the parser looks
for a `pattern:` key per entry, but `audit-patterns.yml` uses `match:` as the key. Both bugs
must be fixed before auto-summarisation and blast-radius tagging works.

Workaround: pass `--summary` and `--blast` explicitly when calling `audit.py write`.

---

## If something fails

Run with verbose debug output:
```bash
YANTRA_DEBUG=1 yukti <command>
```

Common issues:
- **`pyyaml not installed`** — run `pip3 install pyyaml` or `yukti install`
- **`registry not found`** — run `./install.sh` or `yukti init`
- **`YANTRA_INSTANCE not set`** — run `export YANTRA_INSTANCE=<name>` or `yukti go <name>`
- **`which yukti` returns nothing** — run `source ~/yantra/init.sh --quiet` in the current shell
- **`tmux: command not found`** in health check tests — only `port` and `http` checks can run
  without tmux; `log_pattern` requires an active session

---

After sign-off you are ready to customise yantra for your workflow. Start with `ONBOARDING.md`
Module 3, or run `yukti add <name> --context <template> --path <your-project-root>` to register
your first real project instance.
