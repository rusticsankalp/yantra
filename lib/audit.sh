# yantra/lib/audit.sh — shell command audit trail
# Sourced by init.sh. Do NOT use set -euo pipefail here.
#
# Writes JSONL records to:
#   ~/.config/yantra/audit/<instance>/YYYY-MM-DD.jsonl
#
# Each record:
#   {"ts":"...Z","instance":"...","cmd":"...","exit":0,"duration_ms":0,
#    "type":"shell","window":"...","pane":"...","summary":""}

# Commands to never audit (prefix match or exact)
_YANTRA_AUDIT_IGNORE=(
  "ls" "ls " "cd" "cd " "pwd" "cat " "echo " "man "
  "yukti log" "yukti get" "yantra_get" "yantra_session_list"
  "history" "fc " "fg" "bg" "jobs"
)

# ── Write one JSONL record ────────────────────────────────────────────────────
yantra_audit_write() {
  [[ -z "${YANTRA_INSTANCE:-}" ]] && return 0

  local audit_dir="${YANTRA_CONFIG}/audit/${YANTRA_INSTANCE}"
  local audit_file="${audit_dir}/$(date +%Y-%m-%d).jsonl"
  mkdir -p "${audit_dir}"

  # All fields passed via env vars to avoid shell-quoting issues in python
  YANTRA_AUDIT_CMD="${YANTRA_AUDIT_CMD:-}" \
  YANTRA_AUDIT_EXIT="${YANTRA_AUDIT_EXIT:-0}" \
  YANTRA_AUDIT_DURATION="${YANTRA_AUDIT_DURATION:-0}" \
  YANTRA_AUDIT_TYPE="${YANTRA_AUDIT_TYPE:-shell}" \
  YANTRA_AUDIT_WINDOW="${YANTRA_AUDIT_WINDOW:-}" \
  YANTRA_AUDIT_PANE="${YANTRA_AUDIT_PANE:-}" \
  YANTRA_AUDIT_SUMMARY="${YANTRA_AUDIT_SUMMARY:-}" \
  python3 - >> "${audit_file}" 2>/dev/null <<'PYEOF'
import json, datetime, os

r = {
    "ts":          datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.') +
                   f"{datetime.datetime.utcnow().microsecond // 1000:03d}Z",
    "instance":    os.environ.get("YANTRA_INSTANCE", ""),
    "cmd":         os.environ.get("YANTRA_AUDIT_CMD", ""),
    "exit":        int(os.environ.get("YANTRA_AUDIT_EXIT", "0") or 0),
    "duration_ms": int(os.environ.get("YANTRA_AUDIT_DURATION", "0") or 0),
    "type":        os.environ.get("YANTRA_AUDIT_TYPE", "shell"),
    "window":      os.environ.get("YANTRA_AUDIT_WINDOW", ""),
    "pane":        os.environ.get("YANTRA_AUDIT_PANE", ""),
    "summary":     os.environ.get("YANTRA_AUDIT_SUMMARY", ""),
}
print(json.dumps(r, ensure_ascii=False))
PYEOF
}

# Append a note to the summary field of the most recent record today.
yantra_audit_note() {
  local note="${1:?yantra_audit_note requires text}"
  [[ -z "${YANTRA_INSTANCE:-}" ]] && return 0

  local audit_file="${YANTRA_CONFIG}/audit/${YANTRA_INSTANCE}/$(date +%Y-%m-%d).jsonl"
  [[ ! -f "${audit_file}" ]] && return 0

  python3 - "${audit_file}" "${note}" <<'PYEOF'
import json, sys

path, note = sys.argv[1], sys.argv[2]
lines = open(path).readlines()
if not lines:
    sys.exit(0)

last = json.loads(lines[-1])
last['summary'] = note
lines[-1] = json.dumps(last, ensure_ascii=False) + '\n'
open(path, 'w').writelines(lines)
PYEOF
}

# ── zsh preexec hook ──────────────────────────────────────────────────────────
# Called by zsh before each command; records start timestamp.
_yantra_cmd_preexec() {
  _YANTRA_CMD_START="$(date +%s%3N 2>/dev/null || printf '0')"
}

# ── precmd / PROMPT_COMMAND hook ──────────────────────────────────────────────
# Called after each command completes; writes audit record.
_yantra_cmd_precmd() {
  local exit_code=$?
  [[ -z "${YANTRA_INSTANCE:-}" ]] && return 0

  # Retrieve last command
  local last_cmd=""
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    last_cmd="$(fc -ln -1 2>/dev/null | sed 's/^[[:space:]]*//' || true)"
  else
    last_cmd="$(history 1 2>/dev/null | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//' || true)"
  fi

  # Strip leading/trailing whitespace
  last_cmd="${last_cmd#"${last_cmd%%[![:space:]]*}"}"
  last_cmd="${last_cmd%"${last_cmd##*[![:space:]]}"}"

  # Skip empty
  [[ -z "${last_cmd}" ]] && return 0

  # Skip ignored prefixes
  local ignore
  for ignore in "${_YANTRA_AUDIT_IGNORE[@]}"; do
    case "${last_cmd}" in
      "${ignore}"*) return 0 ;;
    esac
  done

  # Skip consecutive duplicates
  [[ "${last_cmd}" == "${_YANTRA_LAST_CMD:-__never__}" ]] && return 0
  _YANTRA_LAST_CMD="${last_cmd}"

  # Calculate duration
  local duration=0
  if [[ -n "${_YANTRA_CMD_START:-}" && "${_YANTRA_CMD_START}" != "0" ]]; then
    local now
    now="$(date +%s%3N 2>/dev/null || printf '0')"
    duration=$(( now - _YANTRA_CMD_START ))
    (( duration < 0 )) && duration=0
  fi
  unset _YANTRA_CMD_START

  # Get tmux window/pane context
  local window="" pane=""
  if [[ -n "${TMUX:-}" ]]; then
    window="$(tmux display-message -p '#{window_name}' 2>/dev/null || true)"
    pane="$(tmux display-message -p '#{pane_title}' 2>/dev/null || true)"
  fi

  YANTRA_AUDIT_CMD="${last_cmd}" \
  YANTRA_AUDIT_EXIT="${exit_code}" \
  YANTRA_AUDIT_DURATION="${duration}" \
  YANTRA_AUDIT_TYPE="shell" \
  YANTRA_AUDIT_WINDOW="${window}" \
  YANTRA_AUDIT_PANE="${pane}" \
  YANTRA_AUDIT_SUMMARY="" \
  yantra_audit_write
}

# ── Hook registration ─────────────────────────────────────────────────────────
# Called by init.sh after all libs are loaded.
_yantra_setup_hooks() {
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    # zsh: use precmd_functions and preexec_functions arrays
    if ! (( ${precmd_functions[(Ie)_yantra_cmd_precmd]} )); then
      precmd_functions+=(_yantra_cmd_precmd)
    fi
    if ! (( ${preexec_functions[(Ie)_yantra_cmd_preexec]} )); then
      preexec_functions+=(_yantra_cmd_preexec)
    fi
  else
    # bash: prepend to PROMPT_COMMAND; capture exit code before it's overwritten
    local _pc_entry='_yantra_cmd_precmd'
    case "${PROMPT_COMMAND:-}" in
      *"${_pc_entry}"*) ;;  # already registered
      *) PROMPT_COMMAND="${_pc_entry}${PROMPT_COMMAND:+; ${PROMPT_COMMAND}}" ;;
    esac
    # bash has no preexec; approximate start time via DEBUG trap
    trap '_yantra_cmd_preexec "$BASH_COMMAND"' DEBUG
  fi
}
