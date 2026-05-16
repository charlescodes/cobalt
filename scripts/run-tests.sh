#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/godot-env.sh"

exec "$GODOT_BIN" --headless --path "$PROJECT_PATH" -s res://tests/test_runner.gd
