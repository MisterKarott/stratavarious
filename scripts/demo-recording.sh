#!/bin/bash
# demo-recording.sh — Record an Asciinema demo of StrataVarious workflow
# Prerequisites: asciinema (brew install asciinema)
# Output: demo.cast (Asciinema v2 format) and demo.gif (if agg is installed)

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PLUGIN_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
CAST_FILE="$PLUGIN_ROOT/demo.cast"

echo "StrataVarious Demo Recording"
echo "Output: $CAST_FILE"
echo ""

# Check for asciinema
if ! command -v asciinema >/dev/null 2>&1; then
  echo "Error: asciinema not found. Install with: brew install asciinema"
  exit 1
fi

echo "Recording will start. Follow the prompts to demonstrate:"
echo "  1. A Claude Code session with context"
echo "  2. Running /stratavarious consolidation"
echo "  3. Starting a new session with restored context"
echo ""
echo "Press Ctrl+D when done recording."
echo ""

asciinema rec "$CAST_FILE" --overwrite

echo ""
echo "Recording saved to: $CAST_FILE"

# Convert to GIF if agg is available
if command -v agg >/dev/null 2>&1; then
  GIF_FILE="$PLUGIN_ROOT/demo.gif"
  agg "$CAST_FILE" "$GIF_FILE"
  echo "GIF saved to: $GIF_FILE"
else
  echo "Tip: Install agg (cargo install asciiinema-aggregate) to generate a GIF"
fi
