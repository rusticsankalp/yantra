# yantra/lib/health.sh — health check polling helpers
# Sourced on demand. Do NOT use set -euo pipefail here.

# ── TCP port poll ─────────────────────────────────────────────────────────────
# yantra_wait_port HOST PORT TIMEOUT_SECS
# Returns 0 when port is open, 1 if timeout exceeded.
yantra_wait_port() {
  local host="${1:?yantra_wait_port requires HOST}"
  local port="${2:?yantra_wait_port requires PORT}"
  local timeout="${3:-30}"
  local elapsed=0

  printf "  yantra: waiting for %s:%s" "${host}" "${port}"
  while (( elapsed < timeout )); do
    if (echo > /dev/tcp/"${host}"/"${port}") 2>/dev/null; then
      printf " ✓\n"
      return 0
    fi
    printf "."
    sleep 2
    (( elapsed += 2 )) || true
  done
  printf " timeout after %ss\n" "${timeout}" >&2
  return 1
}

# ── HTTP endpoint poll ────────────────────────────────────────────────────────
# yantra_wait_http URL [EXPECT_PATTERN] [TIMEOUT_SECS]
# EXPECT_PATTERN: grep pattern to match in response body (optional)
# Returns 0 when URL responds (and pattern matches if given).
yantra_wait_http() {
  local url="${1:?yantra_wait_http requires URL}"
  local pattern="${2:-}"
  local timeout="${3:-60}"
  local elapsed=0

  printf "  yantra: waiting for %s" "${url}"
  while (( elapsed < timeout )); do
    local body
    body="$(curl -sf --max-time 4 "${url}" 2>/dev/null || true)"
    if [[ -n "${body}" ]]; then
      if [[ -z "${pattern}" ]] || printf "%s" "${body}" | grep -q "${pattern}"; then
        printf " ✓\n"
        return 0
      fi
    fi
    printf "."
    sleep 2
    (( elapsed += 2 )) || true
  done
  printf " timeout after %ss\n" "${timeout}" >&2
  return 1
}

# ── Tmux pane log pattern poll ────────────────────────────────────────────────
# yantra_wait_log_pattern SESSION WINDOW PANE PATTERN [TIMEOUT_SECS]
# Captures tmux pane output and greps for PATTERN.
yantra_wait_log_pattern() {
  local session="${1:?yantra_wait_log_pattern requires SESSION}"
  local window="${2:?yantra_wait_log_pattern requires WINDOW}"
  local pane="${3:?yantra_wait_log_pattern requires PANE}"
  local pattern="${4:?yantra_wait_log_pattern requires PATTERN}"
  local timeout="${5:-60}"
  local elapsed=0

  local target="${session}:${window}.${pane}"
  printf "  yantra: waiting for '%s' in %s" "${pattern}" "${target}"

  if ! command -v tmux &>/dev/null; then
    printf "\n  yantra: tmux not found\n" >&2
    return 1
  fi

  while (( elapsed < timeout )); do
    local pane_content
    pane_content="$(tmux capture-pane -pt "${target}" -S -500 2>/dev/null || true)"
    if printf "%s" "${pane_content}" | grep -q "${pattern}"; then
      printf " ✓\n"
      return 0
    fi
    printf "."
    sleep 2
    (( elapsed += 2 )) || true
  done
  printf " timeout after %ss\n" "${timeout}" >&2
  return 1
}

# ── Dispatcher ────────────────────────────────────────────────────────────────
# yantra_health_check TYPE [args...]
# TYPE: port | http | log
yantra_health_check() {
  local check_type="${1:?yantra_health_check requires TYPE}"
  shift

  case "${check_type}" in
    port) yantra_wait_port "$@" ;;
    http) yantra_wait_http "$@" ;;
    log)  yantra_wait_log_pattern "$@" ;;
    *)
      printf "yantra_health_check: unknown type '%s'. Use: port | http | log\n" \
        "${check_type}" >&2
      return 1
      ;;
  esac
}
