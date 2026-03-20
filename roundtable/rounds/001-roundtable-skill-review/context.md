# Context — Valutazione della skill /roundtable

## Project / Domain
Claude Code custom skill (`/roundtable`) che orchestra sessioni di review multi-AI. Il sistema lancia reviewers (OpenCode, Gemini CLI) in parallelo su un topic, itera le loro posizioni fino al consenso, e produce una sintesi. Stack: Bash script (`roundtable.sh`) + Markdown skill prompt (`roundtable.md`). Il tutto è un meta-strumento: può fare review di se stesso.

## Situation
L'utente ha una skill `/roundtable` installata in `~/.claude/commands/roundtable.md` con un supporting script `roundtable.sh`. La skill:
1. Estrae topic e argomenti dalla chiamata
2. Costruisce un `context.md` autosufficiente leggendo file o conversazione
3. Crea una directory round (`roundtable/rounds/NNN-slug/`)
4. Scrive un prompt per i reviewer
5. Lancia OpenCode e Gemini CLI in parallelo via `roundtable.sh run`
6. Itera finché c'è consenso (min 3 iter, max N)
7. Sintetizza in `synthesis.md` e aggiorna un `index.md`

L'utente vuole una valutazione critica di questa skill: funziona bene? Cosa potrebbe migliorare?

## What we're trying to do
Valutare il design e l'usabilità della skill `/roundtable` come strumento di workflow AI-to-AI. Identificare punti di forza, debolezze architetturali, edge case non gestiti, e opportunità di miglioramento concrete.

## Relevant details

### Architettura complessiva

La skill ha 6 step ben definiti:
- **Step 1**: Parse argomenti (`topic`, `--max N`)
- **Step 2**: Build `context.md` — *il passo più critico* — classifica la fonte (files/conversation/mixed), legge i file rilevanti, scrive un documento autosufficiente ~1500-2500 token
- **Step 3**: Crea la directory round via `roundtable.sh init`
- **Step 4**: Scrive `prompt_iter1.txt` con struttura fissa
- **Step 5**: Loop di iterazioni con consensus detection (min 3, default max 5)
- **Step 6**: Sintesi finale in `synthesis.md` + aggiornamento `index.md`

### Script roundtable.sh (parti chiave)

```bash
# Config default
{
  "reviewers": [
    { "name": "opencode", "cmd": "opencode", "args": ["run"] },
    { "name": "gemini",   "cmd": "gemini",   "args": ["-p"]  }
  ]
}

# run_reviewer: lancia cmd con timeout (default 120s)
# OpenCode: usa --file per context.md + prompt come arg posizionale
# Gemini/altri: prompt embedded nel file, passato come arg

# Fallback se reviewer non trovato:
echo "[SKIP] $name: command '$cmd' not found" > "$outfile"
```

Il round numbering è sequenziale (`001`, `002`, …) basato su `find` del contenuto della cartella `rounds/`.

### Prompt struttura (Step 4)

```
[contenuto di context.md]

---
# Your task

Read the context above carefully, especially the "What we're trying to do"
and "What a useful response looks like" sections.

Respond directly and concretely. No preamble.

- **Assessment** / **Position**: overall take in one sentence
- **Main points**: 3–5 substantive points
- **Recommendation**: next step
- **Open questions**: uncertainties needing human input
```

### Consensus detection (Step 5)

```
iteration = 1
consensus = false
min_iterations = 3  # hardcoded

# Consensus = compatible recommendations + no unresolved critical disagreements
# NOT consensus if:
#   - Mutually exclusive approaches
#   - One flags critical issue others ignore
#   - Low confidence, positions still shifting
```

### Follow-up prompt (per iterazioni successive)

Distilla le posizioni di ogni reviewer in:
- Position (1 line)
- Key points (2-3 bullets)
- Critical issues

Poi lista solo i disaccordi non risolti e chiede ai reviewer di convergere.

### Synthesis finale (Step 6)

```markdown
# Synthesis — [topic]
**Date:** [today]
**Iterations:** N/MAX — [Consensus at iter N | Max reached]
**Reviewers:** [list]

## Consensus
## Unresolved divergences
## Key findings / issues / proposals
## Final recommendation
## Suggested tasks
```

### Operational notes
- Se `roundtable.sh` manca → esegui comandi bash direttamente, crea dir manualmente
- Se un reviewer fallisce → continua con gli altri, nota nella sintesi
- Funziona su qualsiasi progetto o pura conversazione

## Already decided — do not re-open
- I reviewer sono OpenCode e Gemini CLI (configurabili via `~/.roundtable.json`)
- Il formato di output è Markdown, salvato su disco
- Il numero minimo di iterazioni è 3 (hardcoded nel prompt)
- La skill è invocata da Claude Code come slash command

## What a useful response looks like
Valuta la skill come se fossi un AI engineer esperto di workflow e tooling. In particolare:
1. **Valuta il design generale**: la skill risolve bene il problema che si propone?
2. **Identifica problemi concreti**: cosa può andare storto? Quali edge case sono mal gestiti?
3. **Valuta Step 2 (context building)**: è il passo più critico — il design è robusto?
4. **Segnala ridondanze o complessità inutile**: c'è overhead che non porta valore?
5. **Proponi 2-3 miglioramenti specifici** con ragionamento

Flag eventuali problemi critici separatamente dai minori.

## Source files
- `~/.claude/commands/roundtable.md` — il prompt della skill (il soggetto principale della review)
- `~/.claude/commands/roundtable.sh` — lo script di supporto che lancia i reviewer
