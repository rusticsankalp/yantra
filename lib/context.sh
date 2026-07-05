# yantra/lib/context.sh — core context management
# Sourced by init.sh. Do NOT use set -euo pipefail here (would kill parent shell).

# ── Color map ─────────────────────────────────────────────────────────────────
# Sets and exports YANTRA_INSTANCE_BG / YANTRA_INSTANCE_FG from a color name.
yantra_color_to_hex() {
  local color="${1:-default}"
  case "${color}" in
    green)   YANTRA_INSTANCE_BG="#005f00"; YANTRA_INSTANCE_FG="#ffffff" ;;
    yellow)  YANTRA_INSTANCE_BG="#875f00"; YANTRA_INSTANCE_FG="#ffffff" ;;
    blue)    YANTRA_INSTANCE_BG="#00005f"; YANTRA_INSTANCE_FG="#ffffff" ;;
    red)     YANTRA_INSTANCE_BG="#5f0000"; YANTRA_INSTANCE_FG="#ffffff" ;;
    cyan)    YANTRA_INSTANCE_BG="#005f5f"; YANTRA_INSTANCE_FG="#ffffff" ;;
    magenta) YANTRA_INSTANCE_BG="#5f005f"; YANTRA_INSTANCE_FG="#ffffff" ;;
    orange)  YANTRA_INSTANCE_BG="#875f00"; YANTRA_INSTANCE_FG="#ffffff" ;;
    *)       YANTRA_INSTANCE_BG="#262626"; YANTRA_INSTANCE_FG="#aaaaaa" ;;
  esac
  export YANTRA_INSTANCE_BG YANTRA_INSTANCE_FG
}

# ── Registry ──────────────────────────────────────────────────────────────────
# Validates registry is present and parseable. Sets YANTRA_REGISTRY_LOADED=1.
yantra_load_registry() {
  local registry="${YANTRA_CONFIG}/registry.yml"
  if [[ ! -f "${registry}" ]]; then
    printf "yantra: registry not found at %s\n  Run: ./install.sh\n" "${registry}" >&2
    return 1
  fi
  python3 -c "
import yaml, sys
try:
    yaml.safe_load(open('${registry}'))
except Exception as e:
    print('yantra: registry parse error:', e, file=sys.stderr)
    sys.exit(1)
" || return 1
  export YANTRA_REGISTRY_LOADED=1
}

# Internal: dump one instance's fields as KEY=VALUE lines via python3 + PyYAML.
_yantra_registry_dump_instance() {
  local instance_name="$1" registry="$2"
  python3 - "${instance_name}" "${registry}" <<'PYEOF'
import sys
try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed. Run: pip3 install pyyaml", file=sys.stderr)
    sys.exit(1)

name, reg_path = sys.argv[1], sys.argv[2]
with open(reg_path) as f:
    reg = yaml.safe_load(f) or {}

inst = (reg.get('instances') or {}).get(name)
if not inst:
    print(f"ERROR: instance '{name}' not in registry", file=sys.stderr)
    sys.exit(1)

def emit(k, v):
    # Sanitize: no newlines in values
    print(f"{k}={str(v or '').replace(chr(10), ' ')}")

emit('YANTRA_INSTANCE',     name)
emit('YANTRA_LABEL',        inst.get('label', name))
emit('YANTRA_CONTEXT_TYPE', inst.get('context') or inst.get('context_type', ''))
emit('PROJECT_ROOT',        inst.get('local_path', ''))
emit('YANTRA_COLOR',        inst.get('color', 'default'))

remote = inst.get('remote') or {}
emit('YANTRA_REMOTE_HOST', remote.get('host', ''))
emit('YANTRA_REMOTE_MODE', remote.get('mode', 'thin'))
emit('YANTRA_REMOTE_PATH', remote.get('path', ''))
PYEOF
}

# Internal: dump env: block of one instance as KEY=VALUE lines.
_yantra_registry_dump_env() {
  local instance_name="$1" registry="$2"
  python3 - "${instance_name}" "${registry}" <<'PYEOF'
import sys
try:
    import yaml
except ImportError:
    sys.exit(0)
name, reg_path = sys.argv[1], sys.argv[2]
with open(reg_path) as f:
    reg = yaml.safe_load(f) or {}
inst = (reg.get('instances') or {}).get(name, {})
for k, v in (inst.get('env') or {}).items():
    print(f"{k}={v or ''}")
PYEOF
}

# Reads one instance from registry; exports all YANTRA_* instance vars.
yantra_get_instance_info() {
  local instance_name="${1:?yantra_get_instance_info requires instance name}"
  local registry="${YANTRA_CONFIG}/registry.yml"

  [[ ! -f "${registry}" ]] && { printf "yantra: registry not found.\n" >&2; return 1; }

  local info
  info="$(_yantra_registry_dump_instance "${instance_name}" "${registry}")" || return 1

  while IFS='=' read -r key val; do
    [[ -z "${key}" || "${key:0:1}" == '#' ]] && continue
    export "${key}=${val}"
  done <<< "${info}"

  yantra_color_to_hex "${YANTRA_COLOR:-default}"
}

# ── Context env ───────────────────────────────────────────────────────────────
# Sources contexts/<type>/context.env — defines service ports, API roots, etc.
yantra_load_context_env() {
  local context_type="${1:-${YANTRA_CONTEXT_TYPE:-}}"
  local ctx_env="${YANTRA_HOME}/contexts/${context_type}/context.env"
  [[ -f "${ctx_env}" ]] && source "${ctx_env}"
  # Non-existence is not an error; context.env is optional
}

# ── Secrets ───────────────────────────────────────────────────────────────────
# Sources ~/.config/yantra/secrets/<instance>.env (never committed to repo).
yantra_load_secrets() {
  local instance_name="${1:-${YANTRA_INSTANCE:-}}"
  local secrets_file="${YANTRA_CONFIG}/secrets/${instance_name}.env"
  [[ -f "${secrets_file}" ]] && source "${secrets_file}"
}

# ── Instance env block ────────────────────────────────────────────────────────
# Sources the env: block from the registry entry as KEY=VAL exports.
yantra_load_instance_env() {
  local instance_name="${1:-${YANTRA_INSTANCE:-}}"
  local registry="${YANTRA_CONFIG}/registry.yml"
  [[ ! -f "${registry}" ]] && return 0

  local env_pairs
  env_pairs="$(_yantra_registry_dump_env "${instance_name}" "${registry}" 2>/dev/null)" || return 0

  while IFS='=' read -r key val; do
    [[ -z "${key}" || "${key:0:1}" == '#' ]] && continue
    export "${key}=${val}"
  done <<< "${env_pairs}"
}

# ── Activation ────────────────────────────────────────────────────────────────
yantra_activate_instance() {
  local instance_name="${1:?yantra_activate_instance requires instance name}"
  local session_name="${instance_name}"

  printf "  yantra: activating %s\n" "${instance_name}"

  yantra_get_instance_info  "${instance_name}" || return 1
  yantra_load_context_env   "${YANTRA_CONTEXT_TYPE:-}"
  yantra_load_instance_env  "${instance_name}"
  yantra_load_secrets       "${instance_name}"

  # Record last used
  printf "%s" "${instance_name}" > "${YANTRA_CONFIG}/last"

  # Apply tmux status-bar colors if already inside a tmux session
  if [[ -n "${TMUX:-}" ]]; then
    tmux set-option -g status-style "bg=${YANTRA_INSTANCE_BG},fg=${YANTRA_INSTANCE_FG}" 2>/dev/null || true
    tmux set-option -g status-right " ${YANTRA_LABEL:-${instance_name}} " 2>/dev/null || true
  fi

  # Remote host: delegate to yantra_remote_attach
  if [[ -n "${YANTRA_REMOTE_HOST:-}" ]]; then
    source "${YANTRA_HOME}/lib/remote.sh"
    yantra_remote_attach "${YANTRA_REMOTE_HOST}" "${instance_name}" "${YANTRA_REMOTE_MODE:-thin}"
    return
  fi

  # Local: attach to existing session or load via tmuxp
  if command -v tmux &>/dev/null && tmux has-session -t "${session_name}" 2>/dev/null; then
    printf "  yantra: attaching to session %s\n" "${session_name}"
    tmux attach-session -t "${session_name}"
  else
    yantra_tmuxp_load "${instance_name}"
  fi
}

# Like activate but always starts a fresh session (kills existing first).
yantra_start_fresh() {
  local instance_name="${1:?yantra_start_fresh requires instance name}"
  local session_name="${instance_name}"

  yantra_get_instance_info  "${instance_name}" || return 1
  yantra_load_context_env   "${YANTRA_CONTEXT_TYPE:-}"
  yantra_load_instance_env  "${instance_name}"
  yantra_load_secrets       "${instance_name}"

  printf "%s" "${instance_name}" > "${YANTRA_CONFIG}/last"

  if command -v tmux &>/dev/null && tmux has-session -t "${session_name}" 2>/dev/null; then
    printf "  yantra: killing existing session %s\n" "${session_name}"
    tmux kill-session -t "${session_name}" 2>/dev/null || true
  fi

  yantra_tmuxp_load "${instance_name}"
}

# ── fzf picker ────────────────────────────────────────────────────────────────
yantra_fzf_pick_instance() {
  local picker="${YANTRA_HOME}/bin/switch"
  if [[ ! -x "${picker}" ]]; then
    printf "yantra: bin/switch not found or not executable.\n" >&2
    return 1
  fi
  local picked
  picked="$("${picker}")" || return 1
  printf "%s" "${picked}"
}

# ── tmuxp loader ──────────────────────────────────────────────────────────────
yantra_tmuxp_load() {
  local instance_name="${1:?yantra_tmuxp_load requires instance name}"
  local tmuxp_yml="${YANTRA_HOME}/contexts/${YANTRA_CONTEXT_TYPE:-default}/tmuxp.yml"

  if ! command -v tmuxp &>/dev/null; then
    printf "yantra: tmuxp not found. Install: pip3 install tmuxp\n" >&2
    return 1
  fi

  if [[ ! -f "${tmuxp_yml}" ]]; then
    printf "yantra: no tmuxp.yml at %s\n  TODO: create contexts/%s/tmuxp.yml\n" \
      "${tmuxp_yml}" "${YANTRA_CONTEXT_TYPE:-default}" >&2
    return 1
  fi

  # Export all YANTRA_* so tmuxp.yml env: blocks can reference them
  export YANTRA_INSTANCE YANTRA_LABEL YANTRA_CONTEXT_TYPE
  export YANTRA_INSTANCE_BG YANTRA_INSTANCE_FG
  export PROJECT_ROOT YANTRA_CONFIG YANTRA_HOME

  printf "  yantra: starting tmuxp session for %s\n" "${instance_name}"
  tmuxp load "${tmuxp_yml}" --yes
}
