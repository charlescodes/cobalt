#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$SCRIPT_DIR/godot-env.local.sh" ]]; then
  source "$SCRIPT_DIR/godot-env.local.sh"
fi

if [[ -z "${GODOT_BIN:-}" ]]; then
  candidates=(
    "/mnt/c/Users/chjiv/Desktop/Godot_v4.4.1-stable_win64.exe"
    "/mnt/c/Program Files/Godot/Godot.exe"
    "godot4"
    "godot"
  )

  for candidate in "${candidates[@]}"; do
    if [[ "$candidate" == */* ]]; then
      if [[ -x "$candidate" ]]; then
        GODOT_BIN="$candidate"
        break
      fi
    elif command -v "$candidate" >/dev/null 2>&1; then
      GODOT_BIN="$(command -v "$candidate")"
      break
    fi
  done
fi

if [[ -z "${GODOT_BIN:-}" ]]; then
  cat >&2 <<EOF_HELP
Could not find Godot 4.4.

Set GODOT_BIN for this shell:
  GODOT_BIN="/mnt/c/Users/chjiv/Desktop/Godot_v4.4.1-stable_win64.exe" ./scripts/run-tests.sh

Or create ignored local overrides in scripts/godot-env.local.sh:
  export GODOT_BIN="/mnt/c/Users/chjiv/Desktop/Godot_v4.4.1-stable_win64.exe"
EOF_HELP
  exit 1
fi

if [[ "$GODOT_BIN" != */* ]]; then
  if ! GODOT_BIN_RESOLVED="$(command -v "$GODOT_BIN" 2>/dev/null)"; then
    echo "Godot command not found: $GODOT_BIN" >&2
    exit 1
  fi
  GODOT_BIN="$GODOT_BIN_RESOLVED"
fi

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "Godot executable is not runnable: $GODOT_BIN" >&2
  exit 1
fi

PROJECT_PATH="$PROJECT_DIR"
PROJECT_DIR_WIN=""

if command -v wslpath >/dev/null 2>&1 && [[ "$GODOT_BIN" == /mnt/* || "${GODOT_BIN,,}" == *.exe ]]; then
  PROJECT_DIR_WIN="$(wslpath -w "$PROJECT_DIR")"
  PROJECT_PATH="$PROJECT_DIR_WIN"
fi

export GODOT_BIN
export PROJECT_DIR
export PROJECT_DIR_WIN
export PROJECT_PATH
