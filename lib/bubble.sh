# yantra/lib/bubble.sh — bubble pane message relay
# Sourced on demand. Do NOT use set -euo pipefail here.
#
# Architecture: messages are written to a named FIFO / log file that the bubble
# pane tails. This avoids the fragility of tmux send-keys for structured output.
#
# Bubble input file: ~/.config/yantra/sessions/<instance>.bubble
# Start bubble pane with: tail -f <bubble_file> | <formatter>

# ── Path helper ───────────────────────────────────────────────────────────────
yantra_bubble_file() {
  local instance="${1:-${YANTRA_INSTANCE:-}}"
  [[ -z "${instance}" ]] && { printf "yantra_bubble_file: YANTRA_INSTANCE not set.\n" >&2; return 1; }
  printf "%s/sessions/%s.bubble" "${YANTRA_CONFIG}" "${instance}"
}

# ── Write a message ───────────────────────────────────────────────────────────
# yantra_bubble_write LEVEL SOURCE MESSAGE
# LEVEL: info | warn | error | ok | debug
# SOURCE: short tag, e.g. "healthcheck", "deploy", "git"
yantra_bubble_write() {
  local level="${1:-info}"
  local source="${2:-yantra}"
  local message="${3:-}"
  local instance="${YANTRA_INSTANCE:-}"

  [[ -z "${instance}" ]] && return 0

  local bfile
  bfile="$(yantra_bubble_file "${instance}")" || return 0

  # Ensure the bubble file exists
  [[ ! -f "${bfile}" ]] && touch "${bfile}"

  local ts
  ts="$(date +%H:%M:%S)"

  # Color codes for level (ANSI; works in most terminals / tmux)
  local color_reset="\033[0m"
  local level_color
  case "${level}" in
    ok|info)  level_color="\033[32m" ;;  # green
    warn)     level_color="\033[33m" ;;  # yellow
    error)    level_color="\033[31m" ;;  # red
    debug)    level_color="\033[36m" ;;  # cyan
    *)        level_color="\033[0m"  ;;
  esac

  printf "[%s] [%-12s] ${level_color}%-5s${color_reset}: %s\n" \
    "${ts}" "${source}" "${level^^}" "${message}" >> "${bfile}"
}

# ── Start bubble watcher in a tmux pane ──────────────────────────────────────
# yantra_bubble_start [SESSION] [WINDOW] [PANE]
# Defaults: current YANTRA_INSTANCE session, window "bubble", pane "bubble"
yantra_bubble_start() {
  local session="${1:-yantra-${YANTRA_INSTANCE:-}}"
  local window="${2:-bubble}"
  local pane="${3:-bubble}"

  if ! command -v tmux &>/dev/null; then
    printf "yantra_bubble_start: tmux not found.\n" >&2
    return 1
  fi

  local bfile
  bfile="$(yantra_bubble_file)" || return 1

  # Create bubble file if needed
  [[ ! -f "${bfile}" ]] && touch "${bfile}"

  local target="${session}:${window}"

  # Create the window/pane if it doesn't exist
  if ! tmux has-session -t "${session}" 2>/dev/null; then
    printf "yantra_bubble_start: session %s not running.\n" "${session}" >&2
    return 1
  fi

  if ! tmux list-windows -t "${session}" -F '#{window_name}' 2>/dev/null | grep -q "^${window}$"; then
    tmux new-window -t "${session}" -n "${window}" "tail -f '${bfile}'" 2>/dev/null || true
  else
    # Window exists; send tail command to the pane
    tmux send-keys -t "${target}.${pane}" "tail -f '${bfile}'" Enter 2>/dev/null || true
  fi

  printf "  yantra: bubble pane started — writing to %s\n" "${bfile}"
}

# ── Clear bubble log ──────────────────────────────────────────────────────────
yantra_bubble_clear() {
  local bfile
  bfile="$(yantra_bubble_file)" || return 1
  truncate -s 0 "${bfile}" 2>/dev/null || true
}
