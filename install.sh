#!/usr/bin/env bash
# Installs cc-sandbox: clones the repo to ~/.cc-sandbox/src (or updates it if
# already cloned) and symlinks bin/cc-sandbox into ~/.local/bin so `cc-sandbox`
# is available on PATH. See docs/adr/0005-install-script-fixed-clone-and-symlink.md.
set -euo pipefail

REPO_URL="https://github.com/backpaper0/cc-sandbox.git"
SRC_DIR="${HOME}/.cc-sandbox/src"
BIN_DIR="${HOME}/.local/bin"

if ! command -v git >/dev/null 2>&1; then
  echo "error: git is required to install cc-sandbox but was not found on PATH." >&2
  exit 1
fi

if [[ -e "${SRC_DIR}" ]]; then
  if ! git -C "${SRC_DIR}" rev-parse --git-dir >/dev/null 2>&1; then
    echo "error: ${SRC_DIR} already exists but is not a git repository." >&2
    echo "Remove or move it aside, then re-run this installer." >&2
    exit 1
  fi
  echo "Updating existing clone at ${SRC_DIR}..."
  git -C "${SRC_DIR}" pull
else
  echo "Cloning cc-sandbox to ${SRC_DIR}..."
  mkdir -p "$(dirname "${SRC_DIR}")"
  git clone "${REPO_URL}" "${SRC_DIR}"
fi

mkdir -p "${BIN_DIR}"
ln -sf "${SRC_DIR}/bin/cc-sandbox" "${BIN_DIR}/cc-sandbox"
echo "Linked ${BIN_DIR}/cc-sandbox -> ${SRC_DIR}/bin/cc-sandbox"

case ":${PATH}:" in
  *":${BIN_DIR}:"*) ;;
  *)
    echo
    echo "warning: ${BIN_DIR} is not on your PATH."
    echo "Add this to your shell's rc file (e.g. ~/.bashrc, ~/.zshrc), then restart your shell:"
    echo
    echo "  export PATH=\"${BIN_DIR}:\$PATH\""
    ;;
esac

echo
echo "cc-sandbox is installed. Run 'cc-sandbox up <project-dir>' to get started."
