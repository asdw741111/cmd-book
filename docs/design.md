# Design: Local CLI Tool Scanner

> **SUPERSEDED (2026-11-06)** — 用户确认改为 macOS 原生应用，网页方案作废。
> 现行设计见 `docs/plans/2026-11-06-macos-cli-catalog-design.md`。
> 本文仅作历史记录保留。

Status: superseded
Date: 2026-11-06

## Goal

Build a local tool that scans the executables installed on this machine, records
where each one lives and how to use it, and lets the user list and search them in
a browser. The result is a static snapshot that can be opened without a server and
regenerated on demand.

## Non-goals

- No live server, daemon, or background watcher (rejected Option B).
- No package-manager-specific metadata (brew/npm/cargo versions are out of scope).
- No Windows support; macOS and Linux only. Windows executable resolution
  (PATHEXT, `.cmd` shims) is explicitly not attempted.
- No interactive TUI (rejected Option C).
- No network access at scan time or in the UI.

## Chosen approach

**Option A: Node scanner + static JSON snapshot + reuse of the existing web UI.**

One Node script walks `PATH`, resolves usage text per tool, and writes a single
JSON snapshot. The existing vanilla HTML/CSS/JS front end is repurposed to load
that snapshot and provide search plus a detail view. No runtime dependencies.

## Architecture

```
scripts/scan.mjs        CLI entry: discover -> describe -> write snapshot
scripts/lib/discover.mjs  PATH walking, dedupe, stat/realpath checks
scripts/lib/usage.mjs     usage resolution (help -> man -> completion)
scripts/lib/parse.mjs     pure text helpers (normalize, trim, extract description)
scripts/lib/pool.mjs      bounded-concurrency task runner with timeout
data/tools.json         generated snapshot (committed)
js/tools.js             front-end data layer: load, filter, sort, format
js/app.js               rendering, routing, keyboard interaction
index.html              list/search shell + detail panel
```

The scanner is the only component that touches the machine. The browser reads a
static file, so the app stays safe, offline, and trivially hosted.

## Scanner CLI

```
npm run scan            # scan PATH, write data/tools.json
node scripts/scan.mjs --stdout   # print JSON to stdout, do not write
node scripts/scan.mjs --limit 50 # cap tools (debug)
```

- Exit code 0 when a snapshot is written, even if some tools failed to produce
  usage text (those are recorded, not fatal).
- Exit code 1 only when discovery itself fails or the output cannot be written.
- Progress and a final count line go to stderr; stdout stays clean for `--stdout`.

## Discovery

1. Read `PATH`, split on `:`, and drop empty entries.
2. For each directory, read entries and keep regular files with the executable bit
   set, skipping symlinks that would recurse into a directory and skipping
   unreadable dirs.
3. Resolve each candidate's real path and key tools by `name` (basename).
4. On a name collision keep the first occurrence in `PATH` order as `path`, and
   list every occurrence in `allPaths`.
5. Sort the final list by `name` for deterministic snapshots.

Per-tool fields that discovery produces: `name`, `path`, `allPaths`.

## Usage resolution

For each discovered tool, try in order and stop at the first usable result:

1. **help** — `spawn(tool, ['--help'])` with an argument array. Never `sh -c`.
2. **man** — `spawn('man', ['-P', 'cat', name])`, used when help is empty or the
   tool is on the interactive skip list.
3. **completion** — look for `_<name>` in `$fpath` directories, then extract every
   `_arguments` option spec (`--flag[description]`, `-f[description]`) into a short
   list of flags. Used when help and man both fail.

Success is decided by the cleaned output containing at least 20 non-whitespace
characters, not by exit code; `exitCode` is still recorded for transparency. A tool
with nothing usable keeps `source: "none"` and `usage: ""`.

Interactive/unsafe tools (editors, pagers, multiplexers, `ssh`, `sudo`, shells and
similar) are never spawned with `--help`. They go straight to man, and if man
yields nothing they are recorded as `skipped: true` with a `skipReason`.

### Cleanup

- Strip ANSI escape sequences and carriage returns.
- Collapse runs of blank lines, trim trailing spaces.
- Drop a leading usage/synopsis block only if it is a single line longer than 200
  characters (version banners and one-line summaries are otherwise kept).
- Keep the first 80 lines or 8192 characters, whichever is hit first, and append a
  truncation marker.

### Environment for child processes

`PAGER=cat`, `MANPAGER=cat`, `GIT_PAGER=cat`, `LC_ALL=C`, `TERM=dumb`,
`COLUMNS=80`, `stdin: 'ignore'`, and stdout/stderr captured. A short deterministic
environment keeps output stable across machines.

## Safety and limits

- Arguments are always passed as an array; no shell string is constructed.
- Per-tool timeout 1500 ms, `killSignal: 'SIGKILL'`; on timeout the tool is recorded
  with `source: "none"` and a timeout note.
- Concurrency capped at 12 child processes.
- Global soft deadline of 180 s; remaining tools are marked `skipped` with
  `skipReason: "deadline"` instead of hanging the scan.
- Captured output is truncated to 256 KiB before parsing.
- The snapshot is written to `data/tools.json.tmp` and renamed into place, so an
  interrupted scan never destroys the previous good file.

## Snapshot schema

```json
{
  "version": 1,
  "scannedAt": "2026-11-06T12:00:00.000Z",
  "host": { "platform": "darwin", "arch": "arm64", "pathDirs": ["/usr/local/bin"] },
  "summary": {
    "discovered": 2090,
    "scanned": 2090,
    "withUsage": 1700,
    "skipped": 30,
    "bySource": { "help": 1200, "man": 400, "completion": 100, "none": 390 }
  },
  "tools": [
    {
      "name": "rg",
      "path": "/opt/homebrew/bin/rg",
      "allPaths": ["/opt/homebrew/bin/rg"],
      "description": "ripgrep recursively searches directories for a regex pattern",
      "usage": "Usage: rg [OPTIONS] PATTERN [PATH ...] ...",
      "source": "help",
      "durationMs": 12,
      "exitCode": 0,
      "skipped": false,
      "skipReason": null
    }
  ]
}
```

`description` is the first non-empty output line that looks like prose, shortened
to 160 characters; it is `""` when nothing suitable was found.

## Front end

Reuse the existing shell, tokens, theme toggle, and table styling. Remove the chart
module and the hard-coded DevOps datasets.

### List view (`#/`)

- Load `./data/tools.json` with `fetch`.
- Header shows tool count and the snapshot's `scannedAt`.
- Search input filters case-insensitively over `name`, `path`, and `description`.
  Results are ranked: exact name match, name prefix, name substring, then path or
  description match; ties break alphabetically.
- Rows show name, a dimmed path, a source badge (`help` / `man` / `completion` /
  `none`), and the description.
- Render at most 300 rows and show "showing X of N" above that.
- Keyboard: `/` focuses search, `↑`/`↓` move the selection, `Enter` opens the tool,
  `Esc` clears the query.

### Detail view (`#/tool/<encoded-name>`)

- Name, full path, every entry in `allPaths`, source badge, and scan timestamp.
- The full retained usage block in a monospace panel with a copy button.
- Copy-path button and a copyable `man <name>` command.
- A plain "Tool not found" state for unknown names, with a link back to the list.

The master-detail layout keeps both panes side by side on wide screens and stacks
them on narrow ones. An `aria-live` region announces the result count, and the list
uses listbox semantics.

### Re-scan

The UI cannot run the scanner. It shows the snapshot time and a hint to run
`npm run scan` when the list looks stale. This keeps the page a static artifact.

## Errors

- Missing `data/tools.json`: the list view renders a full-page hint to run
  `npm run scan`, not a blank screen.
- Malformed JSON: the same hint, plus the parse error in the console.
- A tool with no usage text still appears in the list; its detail view says
  "No usage text captured" and offers the `man` command.

## Testing

- Pure unit tests for `filterTools`/ranking, `normalizeHelp`, `parseCompletion`,
  `shortenDescription`, and discovery dedupe.
- Scanner integration test: build a temporary directory with fake executable
  scripts, point `PATH` at it, run the pipeline in-process, assert the snapshot
  shape, ordering, dedupe, and that a timeout is recorded without failing the run.
- Front-end tests stay DOM-free by testing `js/tools.js` (load/filter/format)
  directly.
- `npm test` runs `node --test`.

## File changes

- **Rewrite** `docs/design.md` (this document).
- **Replace** `js/data.js` with `js/tools.js`; update `js/app.js`, `index.html`.
- **Retire** `js/charts.js` and its test; keep `js/theme.js`; evaluate `js/table.js`
  and reuse it only if the list needs sorting.
- **Add** `scripts/`, `data/tools.json`, `package.json`, and the new tests.
- **Update** `README.md` for the new purpose and the `npm run scan` / `npm test`
  commands.

## Defaults chosen for approval

1. **Scan scope** — every `PATH` directory, deduped by name, all collisions kept in
   `allPaths`. Reject this if you want a curated subset (e.g. Homebrew only).
2. **UI strategy** — reuse the shell, tokens, theme, and table styling; drop the
   charts and DevOps data. Reject if you want a from-scratch front end.
3. **Re-scan** — print-only hint plus snapshot timestamp. Reject if you want a
   local server endpoint that triggers a scan from the browser.
