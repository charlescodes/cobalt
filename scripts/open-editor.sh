#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/godot-env.sh"

exec "$GODOT_BIN" --path "$PROJECT_PATH"
