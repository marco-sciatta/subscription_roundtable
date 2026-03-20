#!/usr/bin/env bash
# subscription_roundtable — installer
# Usage: bash install.sh

set -euo pipefail

COMMANDS_DIR="${HOME}/.claude/commands"
CONFIG_FILE="${HOME}/.roundtable.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== subscription_roundtable installer ==="
echo ""

# 1. Claude Code commands dir
mkdir -p "$COMMANDS_DIR"
cp "${SCRIPT_DIR}/roundtable.md" "${COMMANDS_DIR}/roundtable.md"
cp "${SCRIPT_DIR}/roundtable.sh" "${COMMANDS_DIR}/roundtable.sh"
chmod +x "${COMMANDS_DIR}/roundtable.sh"
echo "✅ Skill installed → ${COMMANDS_DIR}/"

# 2. Config (don't overwrite if exists)
if [[ ! -f "$CONFIG_FILE" ]]; then
  cp "${SCRIPT_DIR}/roundtable.json" "$CONFIG_FILE"
  echo "✅ Config created → ${CONFIG_FILE}"
else
  echo "ℹ️  Config already exists → ${CONFIG_FILE} (not overwritten)"
fi

# 3. Check dependencies
echo ""
echo "=== Checking dependencies ==="

check() {
  if command -v "$1" &>/dev/null; then
    echo "  ✅ $1"
    return 0
  else
    echo "  ❌ $1 — $2"
    return 1
  fi
}

MISSING=0

check "opencode" "install: curl -fsSL https://opencode.ai/install | bash" || MISSING=$((MISSING+1))
check "gemini"   "install: npm install -g @google/gemini-cli  then run: gemini (first login)" || MISSING=$((MISSING+1))
check "jq"       "install: brew install jq  (optional but recommended)" || true

echo ""

if [[ $MISSING -gt 0 ]]; then
  echo "⚠️  $MISSING reviewer(s) not found. Install them, then run:"
  echo "   roundtable.sh list-reviewers"
  echo ""
fi

echo "=== Done ==="
echo ""
echo "Restart Claude Code, then use:"
echo "  /roundtable <topic>"
echo "  /roundtable how should we split the auth module --max 3"
echo "  /roundtable is this implementation correct"
echo "  /roundtable what's the best pattern for retry in async queues"
