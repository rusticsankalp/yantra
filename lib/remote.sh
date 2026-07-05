# yantra/lib/remote.sh — remote SSH operations
# Sourced on demand by yantra_activate_instance. Do NOT use set -euo pipefail here.
#
# SSH multiplexing: uses ControlMaster for connection reuse (60s persist).
# Control socket: /tmp/yantra-ssh-<user>@<host>:<port>

# ── Shared SSH options ────────────────────────────────────────────────────────
_yantra_ssh_opts() {
  local host="$1"
  printf -- "-o ControlMaster=auto -o ControlPath=/tmp/yantra-ssh-%%r@%s:%%p -o ControlPersist=60 -o ConnectTimeout=10" \
    "${host}"
}

# ── Remote exec ───────────────────────────────────────────────────────────────
# yantra_remote_exec HOST CMD [extra ssh args...]
# Runs CMD on HOST and returns its stdout/exit code.
yantra_remote_exec() {
  local host="${1:?yantra_remote_exec requires HOST}"
  local cmd="${2:?yantra_remote_exec requires CMD}"
  shift 2

  # shellcheck disable=SC2046
  ssh $(_yantra_ssh_opts "${host}") "${@}" "${host}" "${cmd}"
}

# ── Attach / open session on remote ──────────────────────────────────────────
# yantra_remote_attach HOST SESSION_NAME MODE
# MODE:
#   thin  — ssh -t HOST "tmux new-session -As SESSION_NAME"
#   full  — ssh -t HOST "yukti go SESSION_NAME"  (requires yantra on remote)
yantra_remote_attach() {
  local host="${1:?yantra_remote_attach requires HOST}"
  local session_name="${2:?yantra_remote_attach requires SESSION_NAME}"
  local mode="${3:-thin}"

  printf "  yantra: connecting to %s (mode: %s)\n" "${host}" "${mode}"

  case "${mode}" in
    thin)
      # shellcheck disable=SC2046
      ssh -t $(_yantra_ssh_opts "${host}") "${host}" \
        "tmux new-session -As '${session_name}'"
      ;;
    full)
      # Assumes yantra is installed on remote and yukti is in PATH
      # shellcheck disable=SC2046
      ssh -t $(_yantra_ssh_opts "${host}") "${host}" \
        "YANTRA_INSTANCE='${session_name}' yukti go '${session_name}'"
      ;;
    *)
      printf "yantra_remote_attach: unknown mode '%s'. Use: thin | full\n" "${mode}" >&2
      return 1
      ;;
  esac
}

# ── Session existence check ───────────────────────────────────────────────────
# yantra_remote_session_exists HOST SESSION_NAME
# Returns 0 if the tmux session exists on the remote host.
yantra_remote_session_exists() {
  local host="${1:?yantra_remote_session_exists requires HOST}"
  local session_name="${2:?yantra_remote_session_exists requires SESSION_NAME}"

  yantra_remote_exec "${host}" "tmux has-session -t '${session_name}' 2>/dev/null" \
    2>/dev/null
}

# ── Bootstrap remote host ─────────────────────────────────────────────────────
# yantra_bootstrap_remote HOST MODE
# MODE:
#   thin  — check tmux, bash, jq on remote; print what's missing
#   full  — rsync/git-clone yantra, then run install.sh remotely
yantra_bootstrap_remote() {
  local host="${1:?yantra_bootstrap_remote requires HOST}"
  local mode="${2:-thin}"

  case "${mode}" in
    thin)
      printf "  yantra: checking remote deps on %s\n" "${host}"
      yantra_remote_exec "${host}" "
        for tool in tmux bash jq python3; do
          if command -v \"\${tool}\" >/dev/null 2>&1; then
            printf '  ok   %s\n' \"\${tool}\"
          else
            printf '  miss %s\n' \"\${tool}\"
          fi
        done
      "
      ;;
    full)
      printf "  yantra: full bootstrap on %s\n" "${host}"

      # Prefer git remote URL; fall back to rsync
      local remote_url
      remote_url="$(git -C "${YANTRA_HOME}" remote get-url origin 2>/dev/null || true)"

      if [[ -n "${remote_url}" ]]; then
        # shellcheck disable=SC2046
        ssh $(_yantra_ssh_opts "${host}") "${host}" "
          if [[ ! -d ~/yantra ]]; then
            git clone '${remote_url}' ~/yantra
          else
            git -C ~/yantra pull --ff-only
          fi
          bash ~/yantra/install.sh
        "
      else
        printf "  yantra: no git remote found — using rsync\n"
        # shellcheck disable=SC2046
        rsync -az --exclude '.git' --exclude '__pycache__' --exclude '.venv' \
          $(_yantra_ssh_opts "${host}") \
          "${YANTRA_HOME}/" "${host}:~/yantra/"
        # shellcheck disable=SC2046
        ssh -t $(_yantra_ssh_opts "${host}") "${host}" "bash ~/yantra/install.sh"
      fi
      ;;
    *)
      printf "yantra_bootstrap_remote: unknown mode '%s'. Use: thin | full\n" "${mode}" >&2
      return 1
      ;;
  esac
}
