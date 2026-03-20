# subscription_roundtable

A `/roundtable` slash command for Claude Code that orchestrates a multi-AI review session using **OpenCode** and **Gemini CLI** — no API keys, no billing, just your existing subscriptions.

---

## What it does

You type `/roundtable <topic>` in Claude Code. It:

1. Reads the current conversation and/or codebase to build a focused context
2. Launches OpenCode and Gemini CLI **in parallel**, each reviewing independently
3. Runs up to 5 iterations — in each follow-up, every AI sees the others' positions and can agree, push back, or refine
4. Stops when consensus is reached (or at max iterations)
5. Synthesizes a final verdict: consensus points, unresolved divergences, recommended next steps

Works for code review, architecture decisions, research questions, and pure design discussions — no mode flags needed.

---

## Why subscription-based matters

Most multi-AI tools require separate API keys and charge per token. This tool uses the **CLI interfaces** of each AI, which run against your existing subscriptions:

| Tool | Auth | Cost |
|------|------|------|
| Claude Code | Anthropic subscription | already paying |
| OpenCode | opencode.ai subscription or self-hosted | already paying |
| Gemini CLI | Google account (OAuth) | free tier: 1000 req/day |

Zero extra billing. Add more reviewers by editing `~/.roundtable.json`.

---

## Requirements

- **Claude Code** — [claude.ai/code](https://claude.ai/code)
- **OpenCode** — [opencode.ai](https://opencode.ai)
- **Gemini CLI** — `npm install -g @google/gemini-cli` then `gemini` once to login with your Google account
- **jq** — `brew install jq` (optional but recommended for custom config)

---

## Install

```bash
git clone <this-repo>
cd subscription_roundtable
bash install.sh
```

Restart Claude Code. Done.

---

## Usage

```bash
# Code review
/roundtable is this implementation correct

# Architecture / design
/roundtable how should we split auth into two services

# Research
/roundtable what's the best pattern for retry in async queues

# With explicit max iterations
/roundtable memory loop validation --max 3
```

**No mode flags.** Claude reads the conversation and codebase, infers what kind of response is useful, and tells the other AIs. They adapt accordingly.

---

## How context works

Claude Code is the context selector. Before calling other AIs it builds a `context.md` with:

- What the project is (from `CLAUDE.md`, `README`, `package.json`, etc.)
- What's happening / what was decided in this conversation
- Relevant code excerpts (not full files — curated)
- Explicit instructions for what a useful response looks like

This file is embedded inline in the prompt sent to each reviewer, so it works even for AIs without filesystem access. OpenCode additionally receives `--file context.md` for deeper navigation.

All round files are saved to `roundtable/rounds/` in your project (or `~/roundtable/rounds/` if not in a git repo).

---

## Configuration

Copy `roundtable.json` to `~/.roundtable.json` and edit:

```json
{
  "reviewers": [
    { "name": "opencode", "cmd": "opencode", "args": ["run"] },
    { "name": "gemini",   "cmd": "gemini",   "args": ["-p"]  }
  ]
}
```

Add any CLI-based AI tool that accepts a prompt as an argument. Remove reviewers you don't have installed — the tool skips unavailable ones gracefully.

**Timeout:** default 120s per reviewer. Override: `export ROUNDTABLE_TIMEOUT=60`

---

## Output structure

Each `/roundtable` invocation creates:

```
roundtable/rounds/
  001-topic-slug/
    context.md          ← curated context sent to all reviewers
    prompt_iter1.txt    ← prompt for iteration 1
    opencode_iter1.md   ← OpenCode response
    gemini_iter1.md     ← Gemini response
    prompt_iter2.txt    ← follow-up with compressed positions
    ...
    synthesis.md        ← final verdict
  index.md              ← one-line summary per round
```

---

## Files

| File | Purpose |
|------|---------|
| `roundtable.md` | Claude Code slash command (prompt) |
| `roundtable.sh` | Bash script — parallel execution, timeout, config |
| `roundtable.json` | Default config template |
| `install.sh` | Copies files to `~/.claude/commands/` |
