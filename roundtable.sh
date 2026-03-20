#!/usr/bin/env bash
# roundtable.sh — Multi-AI roundtable runner
# Usage:
#   roundtable.sh init SLUG [ROOT_DIR]   → create round dir, print path
#   roundtable.sh run DIR PROMPT_FILE N  → launch reviewers in parallel
#   roundtable.sh list-reviewers         → show reviewer availability

set -uo pipefail   # no -e: parallel process failures handled explicitly

CONFIG_FILE="${HOME}/.roundtable.json"
ROUNDS_DIR="roundtable/rounds"
REVIEWER_TIMEOUT="${ROUNDTABLE_TIMEOUT:-120}"  # seconds, override via env

# ── Default config ────────────────────────────────────────────────────────────
default_config() {
  cat <<'EOF'
{
  "reviewers": [
    { "name": "opencode", "cmd": "opencode", "args": ["run"] },
    { "name": "gemini",   "cmd": "gemini",   "args": ["-p"]  }
  ]
}
EOF
}

read_config() {
  if command -v jq &>/dev/null && [[ -f "$CONFIG_FILE" ]]; then
    cat "$CONFIG_FILE"
  else
    default_config
  fi
}

# ── Count existing round dirs and return zero-padded NNN ─────────────────────
next_round_number() {
  mkdir -p "$ROUNDS_DIR"
  local count
  count=$(find "$ROUNDS_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  printf "%03d" $(( count + 1 ))
}

check_cmd() { command -v "$1" &>/dev/null; }

# ── Run a single reviewer, feed prompt via stdin ──────────────────────────────
run_reviewer() {
  local name="$1"
  local cmd="$2"
  local args_json="$3"
  local prompt_file="$4"   # path to file — read via stdin, avoids ARG_MAX
  local outfile="$5"
  local context_file="${6:-}"

  if ! check_cmd "$cmd"; then
    echo "[SKIP] $name: command '$cmd' not found" > "$outfile"
    return 0
  fi

  local full_cmd=("$cmd")

  if command -v jq &>/dev/null; then
    while IFS= read -r arg; do
      full_cmd+=("$arg")
    done < <(echo "$args_json" | jq -r '.[]')
  else
    # jq not available: use defaults
    case "$name" in
      opencode) full_cmd+=("run") ;;
      gemini)   full_cmd+=("-p")  ;;
    esac
  fi

  # OpenCode: use --file for context, pass prompt as arg (opencode reads stdin poorly)
  # Other reviewers: prompt embedded in content already, pass via process substitution
  if [[ "$name" == "opencode" ]]; then
    if [[ -n "$context_file" && -f "$context_file" ]]; then
      full_cmd+=("--file" "$context_file")
    fi
    # opencode run takes prompt as positional arg — read from file to avoid ARG_MAX
    local prompt_content
    prompt_content=$(cat "$prompt_file")
    timeout "$REVIEWER_TIMEOUT" "${full_cmd[@]}" "$prompt_content" > "$outfile" 2>&1
  else
    # gemini and others: pipe prompt via stdin using -p flag already set
    # the prompt content is embedded in the file, pass as arg (gemini -p requires arg, not stdin)
    local prompt_content
    prompt_content=$(cat "$prompt_file")
    timeout "$REVIEWER_TIMEOUT" "${full_cmd[@]}" "$prompt_content" > "$outfile" 2>&1
  fi

  local exit_code=$?
  if [[ $exit_code -eq 124 ]]; then
    echo "" >> "$outfile"
    echo "[TIMEOUT] $name did not respond within ${REVIEWER_TIMEOUT}s" >> "$outfile"
  elif [[ $exit_code -ne 0 ]]; then
    echo "" >> "$outfile"
    echo "[ERROR] $name: exit code $exit_code" >> "$outfile"
  fi
  return 0  # always return 0 — failures are noted in the output file
}

# ── COMMAND: init ─────────────────────────────────────────────────────────────
cmd_init() {
  local slug="${1:-auto}"
  local root="${2:-}"

  if [[ -n "$root" ]]; then
    ROUNDS_DIR="${root}/roundtable/rounds"
  fi

  local nnn
  nnn=$(next_round_number)
  local dir="${ROUNDS_DIR}/${nnn}-${slug}"
  mkdir -p "$dir"
  echo "$dir"
}

# ── COMMAND: run ──────────────────────────────────────────────────────────────
cmd_run() {
  local round_dir="$1"
  local prompt_file="$2"
  local iter="${3:-1}"

  if [[ ! -f "$prompt_file" ]]; then
    echo "ERROR: prompt file not found: $prompt_file" >&2
    exit 1
  fi

  # context.md in the round dir — written by Claude before calling this script
  # NOT passed to gemini (already embedded in prompt) — only to opencode via --file
  local context_file="${round_dir}/context.md"
  local config
  config=$(read_config)

  local reviewer_count
  reviewer_count=$(echo "$config" | jq '.reviewers | length' 2>/dev/null || echo "2")

  local pids=()
  local outfiles=()
  local reviewer_names=()

  for i in $(seq 0 $((reviewer_count - 1))); do
    local name cmd args_json
    name=$(echo "$config"     | jq -r ".reviewers[$i].name" 2>/dev/null || echo "reviewer_$i")
    cmd=$(echo "$config"      | jq -r ".reviewers[$i].cmd"  2>/dev/null || echo "opencode")
    args_json=$(echo "$config" | jq -c ".reviewers[$i].args" 2>/dev/null || echo '[]')

    local outfile="${round_dir}/${name}_iter${iter}.md"
    outfiles+=("$outfile")
    reviewer_names+=("$name")

    run_reviewer "$name" "$cmd" "$args_json" "$prompt_file" "$outfile" "$context_file" &
    pids+=($!)
  done

  # Wait for all — collect results regardless of exit codes
  local failed=0
  for pid in "${pids[@]}"; do
    wait "$pid" || failed=$((failed + 1))
  done

  echo ""
  echo "=== Iteration ${iter} complete ==="
  for i in "${!outfiles[@]}"; do
    local size
    size=$(wc -c < "${outfiles[$i]}" 2>/dev/null || echo "?")
    echo "  ${reviewer_names[$i]} → ${outfiles[$i]} (${size} bytes)"
  done
  [[ $failed -gt 0 ]] && echo "  WARN: $failed process(es) reported errors"

  return 0
}

# ── COMMAND: list-reviewers ───────────────────────────────────────────────────
cmd_list() {
  local config
  config=$(read_config)

  echo "Configured reviewers:"
  if command -v jq &>/dev/null; then
    echo "$config" | jq -r '.reviewers[] | "  \(.name): \(.cmd) \(.args | join(" "))"'
  else
    echo "  (jq not available — showing defaults)"
    echo "  opencode: opencode run"
    echo "  gemini:   gemini -p"
  fi

  echo ""
  echo "Availability:"
  local count
  count=$(echo "$config" | jq '.reviewers | length' 2>/dev/null || echo "2")
  for i in $(seq 0 $((count - 1))); do
    local name cmd
    name=$(echo "$config" | jq -r ".reviewers[$i].name" 2>/dev/null || echo "reviewer_$i")
    cmd=$(echo "$config"  | jq -r ".reviewers[$i].cmd"  2>/dev/null || echo "opencode")
    if check_cmd "$cmd"; then
      echo "  ✅ $name ($cmd)"
    else
      echo "  ❌ $name ($cmd not found)"
    fi
  done

  echo ""
  echo "Timeout: ${REVIEWER_TIMEOUT}s (override: export ROUNDTABLE_TIMEOUT=N)"
}

# ── MAIN ──────────────────────────────────────────────────────────────────────
COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
  init)            cmd_init "$@" ;;
  run)             cmd_run  "$@" ;;
  list-reviewers)  cmd_list      ;;
  help|*)
    echo "Usage:"
    echo "  roundtable.sh init SLUG [ROOT]        # create round directory"
    echo "  roundtable.sh run DIR PROMPT_FILE N   # launch reviewers in parallel"
    echo "  roundtable.sh list-reviewers           # show reviewer status"
    echo ""
    echo "Env:"
    echo "  ROUNDTABLE_TIMEOUT=120   # per-reviewer timeout in seconds"
    ;;
esac
