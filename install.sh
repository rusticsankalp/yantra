#!/usr/bin/env bash
# yantra/install.sh — dependency check and first-time setup
# Usage:
#   ./install.sh                          # local install
#   ./install.sh --remote user@host --thin  # check remote deps
#   ./install.sh --remote user@host --full  # clone + install on remote

set -euo pipefail

YANTRA_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YANTRA_CONFIG="${HOME}/.config/yantra"

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { printf "  \033[32m✓\033[0m  %s\n" "$*"; }
warn()    { printf "  \033[33m!\033[0m  %s\n" "$*"; }
err()     { printf "  \033[31m✗\033[0m  %s\n" "$*" >&2; }
missing() { printf "  \033[31m✗\033[0m  %-12s not found  →  %s\n" "$1" "$2"; }
header()  { printf "\n\033[1m%s\033[0m\n" "$*"; }

check_version() {
  local tool="$1" min_ver="$2"
  local actual
  actual="$(${tool} --version 2>&1 | grep -Eo '[0-9]+\.[0-9]+' | head -1 || true)"
  if [[ -z "${actual}" ]]; then return 1; fi
  local major_min="${min_ver%%.*}"
  local major_act="${actual%%.*}"
  (( major_act >= major_min )) || return 1
}

# ── Remote mode ───────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--remote" ]]; then
  REMOTE_HOST="${2:?Usage: install.sh --remote user@host [--thin|--full]}"
  REMOTE_MODE="${3:---thin}"

  case "${REMOTE_MODE}" in
    --thin)
      header "yantra: checking remote deps on ${REMOTE_HOST}"
      ssh "${REMOTE_HOST}" bash <<'REMOTE'
        for tool in tmux bash jq; do
          if command -v "${tool}" &>/dev/null; then
            printf "  ok   %s\n" "${tool}"
          else
            printf "  miss %s\n" "${tool}"
          fi
        done
REMOTE
      ;;
    --full)
      header "yantra: full install on ${REMOTE_HOST}"
      ssh "${REMOTE_HOST}" bash <<REMOTE
        set -euo pipefail
        if [[ ! -d ~/yantra ]]; then
          git clone "$(git -C "${YANTRA_HOME}" remote get-url origin 2>/dev/null || echo 'https://github.com/your-org/yantra')" ~/yantra
        fi
        bash ~/yantra/install.sh
REMOTE
      ;;
    *)
      err "Unknown remote mode: ${REMOTE_MODE}. Use --thin or --full."
      exit 1
      ;;
  esac
  exit 0
fi

# ── Local install ─────────────────────────────────────────────────────────────
printf "\n\033[1;36m  yantra installer\033[0m\n"
printf "  home: %s\n" "${YANTRA_HOME}"
printf "  config: %s\n\n" "${YANTRA_CONFIG}"

header "Checking required tools"

MISSING=0

_check_tool() {
  local tool="$1" min_ver="${2:-}" hint="$3"
  if ! command -v "${tool}" &>/dev/null; then
    missing "${tool}" "${hint}"
    (( MISSING++ )) || true
  elif [[ -n "${min_ver}" ]] && ! check_version "${tool}" "${min_ver}"; then
    warn "${tool} found but may be below minimum version ${min_ver}. ${hint}"
  else
    info "${tool}"
  fi
}

_check_tool tmux    "2.6" "brew install tmux  OR  apt-get install tmux"
_check_tool tmuxp   ""    "pip3 install tmuxp"
_check_tool fzf     ""    "brew install fzf   OR  apt-get install fzf"
_check_tool zoxide  ""    "brew install zoxide  OR  curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash"
_check_tool mise    ""    "curl https://mise.run | sh  OR  brew install mise"
_check_tool python3 "3.8" "brew install python  OR  apt-get install python3"
_check_tool jq      ""    "brew install jq  OR  apt-get install jq"

if (( MISSING > 0 )); then
  printf "\n"
  warn "${MISSING} required tool(s) missing. Install them and re-run install.sh."
  printf "\n"
fi

header "Creating config directories"

for dir in \
  "${YANTRA_CONFIG}" \
  "${YANTRA_CONFIG}/secrets" \
  "${YANTRA_CONFIG}/sessions" \
  "${YANTRA_CONFIG}/audit"
do
  if [[ ! -d "${dir}" ]]; then
    mkdir -p "${dir}"
    info "created ${dir}"
  else
    info "exists  ${dir}"
  fi
done

# Create empty registry if missing
if [[ ! -f "${YANTRA_CONFIG}/registry.yml" ]]; then
  cat > "${YANTRA_CONFIG}/registry.yml" <<'YAML'
# yantra instance registry
# Managed by: yukti add / yukti rm
instances: {}
YAML
  info "created ${YANTRA_CONFIG}/registry.yml"
else
  info "exists  ${YANTRA_CONFIG}/registry.yml"
fi

header "Installing Python dependencies"

REQUIREMENTS="${YANTRA_HOME}/impl/python/requirements.txt"
if [[ -f "${REQUIREMENTS}" ]]; then
  pip3 install -r "${REQUIREMENTS}" --quiet && info "pip install complete"
else
  warn "No requirements.txt found at ${REQUIREMENTS} — skipping pip install"
fi

header "Setting executable permissions"

if [[ -d "${YANTRA_HOME}/bin" ]]; then
  while IFS= read -r -d '' f; do
    chmod +x "${f}"
    info "chmod +x ${f##*/}"
  done < <(find "${YANTRA_HOME}/bin" -type f -print0)
else
  warn "bin/ directory not found — no files to chmod"
fi

# chmod install.sh itself
chmod +x "${BASH_SOURCE[0]}"

printf "\n\033[1;32m  Setup complete.\033[0m\n"
printf "\n  Add to .zshrc:\n"
printf "    source ~/yantra/init.sh --quiet\n\n"
printf "  Or for smart mode on new shells:\n"
printf "    source ~/yantra/init.sh\n\n"
