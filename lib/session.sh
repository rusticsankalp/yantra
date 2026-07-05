# yantra/lib/session.sh — per-instance KV store backed by a flat .env file
# Sourced by init.sh. Do NOT use set -euo pipefail here.
#
# Session files live at: ~/.config/yantra/sessions/<instance>.env
# Each line is: KEY=value
# Tmux setenv mirrors values into the running session when available.

# ── Path helpers ──────────────────────────────────────────────────────────────
yantra_session_dir() {
  printf "%s/sessions" "${YANTRA_CONFIG}"
}

yantra_session_file() {
  local instance="${1:-${YANTRA_INSTANCE:-}}"
  if [[ -z "${instance}" ]]; then
    printf "yantra_session_file: YANTRA_INSTANCE not set.\n" >&2
    return 1
  fi
  printf "%s/sessions/%s.env" "${YANTRA_CONFIG}" "${instance}"
}

# ── Write ─────────────────────────────────────────────────────────────────────
# yantra_set KEY VALUE [instance]
yantra_set() {
  local key="${1:?yantra_set requires KEY}"
  local val="${2?yantra_set requires VALUE}"
  local instance="${3:-${YANTRA_INSTANCE:-}}"

  if [[ -z "${instance}" ]]; then
    printf "yantra_set: YANTRA_INSTANCE not set.\n" >&2
    return 1
  fi

  local session_file="${YANTRA_CONFIG}/sessions/${instance}.env"
  mkdir -p "${YANTRA_CONFIG}/sessions"

  # Update or append KEY=VALUE (remove old line first, then append)
  if [[ -f "${session_file}" ]]; then
    local tmp
    tmp="$(mktemp)"
    grep -v "^${key}=" "${session_file}" > "${tmp}" 2>/dev/null || true
    printf "%s=%s\n" "${key}" "${val}" >> "${tmp}"
    mv "${tmp}" "${session_file}"
  else
    printf "%s=%s\n" "${key}" "${val}" > "${session_file}"
  fi

  # Mirror into tmux environment if session is running
  local session_name="yantra-${instance}"
  if command -v tmux &>/dev/null && tmux has-session -t "${session_name}" 2>/dev/null; then
    tmux setenv -t "${session_name}" "${key}" "${val}" 2>/dev/null || true
  fi
}

# ── Read ──────────────────────────────────────────────────────────────────────
# yantra_get KEY [instance]
# Echoes the value. Returns 1 if key not found.
yantra_get() {
  local key="${1:?yantra_get requires KEY}"
  local instance="${2:-${YANTRA_INSTANCE:-}}"

  if [[ -z "${instance}" ]]; then
    printf "yantra_get: YANTRA_INSTANCE not set.\n" >&2
    return 1
  fi

  local session_file="${YANTRA_CONFIG}/sessions/${instance}.env"
  if [[ ! -f "${session_file}" ]]; then
    return 1
  fi

  local line
  line="$(grep "^${key}=" "${session_file}" | tail -1)" || return 1
  printf "%s" "${line#*=}"
}

# ── List ──────────────────────────────────────────────────────────────────────
# Prints all KEY=VALUE pairs for the current (or given) instance.
yantra_session_list() {
  local instance="${1:-${YANTRA_INSTANCE:-}}"

  if [[ -z "${instance}" ]]; then
    printf "yantra_session_list: YANTRA_INSTANCE not set.\n" >&2
    return 1
  fi

  local session_file="${YANTRA_CONFIG}/sessions/${instance}.env"
  if [[ ! -f "${session_file}" ]]; then
    printf "  (no session data for %s)\n" "${instance}"
    return 0
  fi

  grep -v "^#" "${session_file}" | grep -v "^[[:space:]]*$" || true
}

# ── Delete ────────────────────────────────────────────────────────────────────
# yantra_unset KEY [instance]
yantra_unset() {
  local key="${1:?yantra_unset requires KEY}"
  local instance="${2:-${YANTRA_INSTANCE:-}}"

  local session_file="${YANTRA_CONFIG}/sessions/${instance}.env"
  [[ ! -f "${session_file}" ]] && return 0

  local tmp
  tmp="$(mktemp)"
  grep -v "^${key}=" "${session_file}" > "${tmp}" 2>/dev/null || true
  mv "${tmp}" "${session_file}"

  # Remove from tmux env
  local session_name="yantra-${instance}"
  if command -v tmux &>/dev/null && tmux has-session -t "${session_name}" 2>/dev/null; then
    tmux setenv -t "${session_name}" -u "${key}" 2>/dev/null || true
  fi
}
