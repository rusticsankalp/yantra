# yantra/init.sh — source this file, do not execute it
#
# .zshrc usage (choose one):
#   source ~/yantra/init.sh             # smart mode: detect + prompt on new shells
#   source ~/yantra/init.sh --quiet     # load env/functions only, no session prompt
#   source ~/yantra/init.sh wscs-dev    # directly activate named instance
#   source ~/yantra/init.sh --last      # resume last used instance
#   source ~/yantra/init.sh --list      # fzf picker
#   source ~/yantra/init.sh --new <ctx> # wizard: add new instance

# ── Guard: must be sourced, not executed ─────────────────────────────────────
if [[ -n "${BASH_VERSION:-}" && "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
  printf 'ERROR: init.sh must be sourced, not executed.\n  source %s\n' "$0" >&2
  exit 1
fi

# ── Resolve YANTRA_HOME from script location ──────────────────────────────────
if [[ -n "${ZSH_VERSION:-}" ]]; then
  # ${(%):-%N} gives the sourced file path in zsh
  YANTRA_HOME="$(cd "$(dirname "${(%):-%N}")" && pwd)"
else
  YANTRA_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
export YANTRA_HOME
export YANTRA_CONFIG="${HOME}/.config/yantra"
export YANTRA_IMPL="${YANTRA_IMPL:-python}"

# Prepend bin/ to PATH exactly once
if [[ ":${PATH}:" != *":${YANTRA_HOME}/bin:"* ]]; then
  export PATH="${YANTRA_HOME}/bin:${PATH}"
fi

# ── Source libraries ──────────────────────────────────────────────────────────
# Sourced libs must NOT use set -euo pipefail (would kill the parent shell)
source "${YANTRA_HOME}/lib/context.sh"
source "${YANTRA_HOME}/lib/session.sh"
source "${YANTRA_HOME}/lib/audit.sh"

# TODO: load shell completions once implemented
# [[ -n "${ZSH_VERSION:-}" ]] && source "${YANTRA_HOME}/completions/_yukti" 2>/dev/null || true

# ── Smart mode ────────────────────────────────────────────────────────────────
_yantra_smart_mode() {
  local detected="" running="" last_used=""

  # 1. Detect cwd match via yukti or fallback registry parse
  if command -v yukti &>/dev/null; then
    detected="$(yukti ls --json 2>/dev/null | python3 -c "
import json, sys, os
try:
    data = json.load(sys.stdin)
    cwd = os.environ.get('PWD', os.getcwd())
    for inst in data.get('instances', []):
        root = inst.get('local_path', '')
        if root and (cwd == root or cwd.startswith(root + '/')):
            print(inst['id'])
            break
except Exception:
    pass
" 2>/dev/null || true)"
  fi

  # 2. Detect running yantra tmux sessions (sessions named "yantra-<id>")
  if command -v tmux &>/dev/null; then
    running="$(tmux list-sessions -F '#{session_name}' 2>/dev/null \
      | grep -E '^yantra-' | head -1 | sed 's/^yantra-//' || true)"
  fi

  # 3. Last used instance
  [[ -f "${YANTRA_CONFIG}/last" ]] && last_used="$(< "${YANTRA_CONFIG}/last")"

  printf "\n  yantra v0.1.0\n\n"
  [[ -n "${detected}" ]]  && printf "  Detected  %-22s (matched current directory)\n" "${detected}"
  [[ -n "${running}" ]]   && printf "  Running   %-22s ●\n" "${running}"
  [[ -n "${last_used}" ]] && printf "  Last used %s\n" "${last_used}"
  printf "\n"

  # Build menu entries; use explicit parallel arrays (portable bash+zsh)
  local _types=() _insts=()

  if [[ -n "${detected}" ]]; then
    printf "  [1] resume  %s\n" "${detected}"
    _types+=("resume"); _insts+=("${detected}")
    printf "  [2] fresh   %s\n" "${detected}"
    _types+=("fresh"); _insts+=("${detected}")
  fi

  # Attach to a different running session if any
  if [[ -n "${running}" && "${running}" != "${detected}" ]]; then
    local ridx=$(( ${#_types[@]} + 1 ))
    printf "  [%s] attach  %s  ●\n" "${ridx}" "${running}"
    _types+=("resume"); _insts+=("${running}")
  fi

  local pidx=$(( ${#_types[@]} + 1 ))
  printf "  [%s] pick    ... (fzf)\n" "${pidx}"
  _types+=("pick"); _insts+=("")
  printf "  [q] env only\n\n  → "

  local choice
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    read -rsk 1 choice
  else
    read -rn1 choice
  fi
  printf "%s\n\n" "${choice}"

  case "${choice}" in
    q|Q|"") return 0 ;;
    [1-9])
      # Resolve array index (bash: 0-indexed; zsh: 1-indexed)
      local idx
      if [[ -n "${ZSH_VERSION:-}" ]]; then
        idx=$(( choice ))
      else
        idx=$(( choice - 1 ))
      fi

      local act="${_types[$idx]:-}"
      local inst="${_insts[$idx]:-}"

      [[ -z "${act}" ]] && { printf "  yantra: choice %s out of range.\n" "${choice}" >&2; return 1; }

      case "${act}" in
        resume) yantra_activate_instance "${inst}" ;;
        fresh)  yantra_start_fresh "${inst}" ;;
        pick)
          local picked
          picked="$(yantra_fzf_pick_instance)" && yantra_activate_instance "${picked}"
          ;;
      esac
      ;;
    *)
      # Any other key falls through to fzf
      local picked
      picked="$(yantra_fzf_pick_instance)" && yantra_activate_instance "${picked}"
      ;;
  esac
}

# ── Mode dispatch ─────────────────────────────────────────────────────────────
_yantra_dispatch() {
  local mode="${1:-}"

  case "${mode}" in
    --quiet)
      # PATH + env + functions only; skip session prompt
      _yantra_setup_hooks
      return 0
      ;;
    --last)
      if [[ -f "${YANTRA_CONFIG}/last" ]]; then
        yantra_activate_instance "$(< "${YANTRA_CONFIG}/last")"
      else
        printf "yantra: no last instance recorded.\n" >&2
      fi
      ;;
    --list)
      local picked
      picked="$(yantra_fzf_pick_instance)" && yantra_activate_instance "${picked}"
      ;;
    --new)
      local ctx="${2:-}"
      if [[ -z "${ctx}" ]]; then
        printf "Usage: source init.sh --new <context_type>\n" >&2
        return 1
      fi
      yukti add --context "${ctx}"
      ;;
    "")
      _yantra_smart_mode
      ;;
    *)
      # Direct activation of named instance
      yantra_activate_instance "${mode}"
      ;;
  esac

  _yantra_setup_hooks
}

_yantra_dispatch "$@"
