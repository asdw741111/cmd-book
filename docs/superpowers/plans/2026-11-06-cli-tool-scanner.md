# CLI Tool Scanner Implementation Plan

> **SUPERSEDED (2026-11-06)** — 未执行、已废弃。用户重新设计后改为 macOS 原生 Swift 应用。
> 现行设计与验证标准见 `docs/plans/2026-11-06-macos-cli-catalog-design.md`。

> **For the implementing agent:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scan the local `PATH` for installed command-line tools, capture each tool's usage text, and present the result as a static, searchable snapshot with a tool detail view.

**Architecture:** A zero-dependency Node scanner discovers executables, probes `--help`, `man`, then zsh completion specs with strict timeouts, and writes one deterministic `data/tools.json` snapshot via temp-file rename. A vanilla ES-module frontend fetches that snapshot, ranks case-insensitive search matches, renders a keyboard-navigable list, and routes to a detail view. No server or watcher is required.

**Tech Stack:** Node 22 (minimum Node 20), `node:test`, `node:assert/strict`, vanilla HTML/CSS/ES modules.

**Spec:** `docs/design.md`

## Global Constraints

- Zero runtime and development dependencies. `package.json` has `"type": "module"`, `"private": true`, and `"engines": { "node": ">=20" }`.
- Scanner modules live under `scripts/`; browser modules live under `js/`. Tests live under `tests/`.
- Never invoke a shell. Use `spawn(command, argsArray, { shell: false })`; never `sh -c` or `shell: true`.
- Child environment is always overridden with `PAGER=cat`, `MANPAGER=cat`, `GIT_PAGER=cat`, `LC_ALL=C`, `TERM=dumb`, and `COLUMNS=80`. Child stdin is `ignore`; stdout and stderr are captured.
- Probe timeout is 1500 ms per process and sends `SIGKILL`. Concurrency is 12. Global soft deadline is 180 seconds.
- Capture is truncated to 256 KiB before parsing. Normalized usage keeps at most 80 lines or 8192 characters, whichever comes first.
- `skipped` is true for interactive tools and for tools that miss the global deadline. Never probe an interactive tool with `--help`.
- Write `data/tools.json` with a temp file plus rename. Never leave a partial snapshot.
- `--stdout` writes only JSON to stdout. Progress and diagnostics go to stderr.
- Determinism: sort tools by `name` using code-unit comparison; preserve `PATH` order in `allPaths`; keep the first `PATH` occurrence as `path`.
- The page fetches only `./data/tools.json`; it must not fetch anything else over the network.
- Target platforms are macOS and Linux only. Windows executable rules are out of scope.

## Review Focus

1. **Interactive tools never receive `--help`.** `vim`, `vi`, `nano`, `emacs`, `less`, `more`, `man`, `top`, `htop`, `btop`, `watch`, `screen`, `tmux`, `ssh`, `telnet`, `sudo`, and `su` must only use `man` or completion fallback. Covered by Task 5.
2. **No shell interpolation anywhere.** Tool names and paths are passed as argument array entries. Covered by Task 4, including a source-level assertion that `scripts/lib/usage.mjs` contains neither `sh -c` nor `shell: true`.
3. **A hanging tool must not fail a scan.** Timeout returns `source: "none"`, `exitCode: null`, `durationMs` around 1500, and the overall scan still exits 0 if discovery and writing succeed. Covered by Tasks 4 and 6.
4. **PATH dedupe is deterministic.** Deduplicate by directory-entry basename, keep the first resolved path in `path`, append later resolved paths to `allPaths`, and preserve `PATH` order. Covered by Task 2.
5. **Never expose a partial snapshot.** Writing uses temp file plus rename; the UI shows a scan instruction when the snapshot is missing or corrupt. Covered by Tasks 6 and 7.

## Scope Check

This is one subsystem: a CLI scanner plus a static viewer for its snapshot. The scanner and viewer share one schema and one user workflow. No split into separate plans is needed.

## Plan-Level Decisions

- Timeout ownership lives in `scripts/lib/usage.mjs` (`runCommand`), because that module owns the child process. `scripts/lib/pool.mjs` only limits concurrency and preserves result order.
- `skipReason` vocabulary is exactly `"timeout" | "deadline" | "interactive" | null`.
- `description` is the first non-empty line that has at least 3 words, at least 12 characters, does not start with `usage`, `synopsis`, or `-`, and is shortened to 160 characters.
- `normalizeHelp` drops the first line only when it is longer than 200 characters and a later non-empty line exists. This removes giant banner lines without losing useful short output.
- `--limit` bounds how many tools are probed; `summary.discovered` still counts every discovered tool and `summary.scanned` counts only tools actually probed. Tools skipped by the deadline are not counted as scanned.
- Completion fallback renders `Options: <flags>` from zsh `_arguments` specs when at least one flag is found.
- A scan with some failed tools still exits 0. Exit 1 is reserved for discovery failure or snapshot write failure.
- `js/app.js` exports DOM-free helpers for tests and guards browser initialization with `typeof document !== 'undefined'`.
- `js/data.js`, `js/charts.js`, and `js/table.js` are retired. `js/table.js` is retired because the tool list has no sortable columns. `js/theme.js` is kept.

## File Structure

```text
.
├── package.json                         # new: scripts, ESM, engines
├── data/
│   └── tools.json                       # generated snapshot, committed
├── scripts/
│   ├── scan.mjs                         # CLI entry, snapshot assembly, atomic write
│   └── lib/
│       ├── parse.mjs                    # truncation, normalization, descriptions, completion parsing
│       ├── discover.mjs                 # PATH discovery and basename dedupe
│       ├── pool.mjs                     # bounded-concurrency map
│       └── usage.mjs                    # help/man/completion chain, timeout, env
├── js/
│   ├── tools.js                         # snapshot loading, search ranking, timestamps
│   ├── app.js                           # routes, list, search, detail, keyboard, copy
│   └── theme.js                         # kept: theme persistence
├── css/
│   ├── tokens.css                       # kept: theme tokens
│   └── app.css                          # search/list/detail styling
├── index.html                           # new shell
├── tests/
│   ├── helpers/fixtures.mjs             # temp dirs, executables, streams, fetch stub
│   ├── parse.test.mjs
│   ├── discover.test.mjs
│   ├── pool.test.mjs
│   ├── usage.test.mjs
│   ├── scan.test.mjs
│   ├── tools.test.mjs
│   ├── app.test.mjs
│   └── theme.test.mjs                   # kept
└── README.md                            # scanner usage and workflow
```

Removed in Task 10: `js/data.js`, `js/charts.js`, `js/table.js`, `tests/data.test.mjs`, `tests/charts.test.mjs`, `tests/table.test.mjs`.

---

## Task 1: Scaffold and Text Parsing Helpers

**Files:**
- Create: `package.json`
- Create: `scripts/lib/parse.mjs`
- Test: `tests/parse.test.mjs`

**Interfaces:**
- `truncateOutput(raw: string, maxBytes = 262144): string`
- `normalizeHelp(raw: string): string`
- `looksLikeUsage(text: string): boolean`
- `extractDescription(raw: string): string`
- `shortenDescription(text: string, max = 160): string`
- `parseCompletion(raw: string): string[]`
- Constants: `MAX_USAGE_BYTES`, `MAX_USAGE_LINES`, `MAX_USAGE_CHARS`, `MAX_DESCRIPTION_CHARS`

- [ ] **Step 1: Write the failing test**

Create `tests/parse.test.mjs`:

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  MAX_USAGE_BYTES,
  MAX_USAGE_LINES,
  truncateOutput,
  normalizeHelp,
  looksLikeUsage,
  extractDescription,
  shortenDescription,
  parseCompletion,
} from '../scripts/lib/parse.mjs';

test('truncateOutput keeps short text unchanged', () => {
  assert.equal(truncateOutput('hello'), 'hello');
});

test('truncateOutput caps UTF-8 bytes and removes a split replacement character', () => {
  const raw = 'a'.repeat(MAX_USAGE_BYTES - 1) + 'é';
  const output = truncateOutput(raw);
  assert.ok(Buffer.byteLength(output, 'utf8') <= MAX_USAGE_BYTES);
  assert.equal(output.endsWith(String.fromCharCode(0xfffd)), false);
  assert.equal(output.length, MAX_USAGE_BYTES - 1);
});

test('normalizeHelp collapses blank runs and trims trailing spaces', () => {
  assert.equal(normalizeHelp('a  \n\n\nb\n'), 'a\n\nb');
});

test('normalizeHelp drops only an oversized first banner line', () => {
  const raw = 'x'.repeat(201) + '\n\nusage: demo\n\nA useful demo tool.\n';
  const output = normalizeHelp(raw);
  assert.equal(output.includes('x'.repeat(201)), false);
  assert.equal(output.includes('usage: demo'), true);
});

test('normalizeHelp keeps a long single-line help body', () => {
  const raw = 'usage: ' + 'x'.repeat(500);
  assert.equal(normalizeHelp(raw), raw);
});

test('normalizeHelp caps output lines and marks truncation', () => {
  const raw = Array.from({ length: MAX_USAGE_LINES + 5 }, (_, i) => `line ${i}`).join('\n');
  const output = normalizeHelp(raw);
  const lines = output.split('\n');
  assert.equal(lines.at(-1), '[usage truncated]');
  assert.equal(lines.length, MAX_USAGE_LINES + 1);
});

test('looksLikeUsage requires at least twenty non-whitespace characters', () => {
  assert.equal(looksLikeUsage('short'), false);
  assert.equal(looksLikeUsage('x'.repeat(20)), true);
});

test('extractDescription skips usage and short lines', () => {
  const raw = [
    'Usage: demo',
    '',
    'Demo',
    'A small tool for scanning local things.',
    'More detail.',
  ].join('\n');
  assert.equal(extractDescription(raw), 'A small tool for scanning local things.');
});

test('extractDescription rejects flag-only lines and returns empty when nothing qualifies', () => {
  assert.equal(extractDescription('--help\n-v\n'), '');
});

test('shortenDescription preserves short text and truncates long text', () => {
  assert.equal(shortenDescription('Short description'), 'Short description');
  const output = shortenDescription('word '.repeat(40), 20);
  assert.ok(output.length <= 20);
  assert.equal(output.endsWith('…'), true);
});

test('parseCompletion extracts unique sorted flags', () => {
  const raw = "_arguments '--help[show help]' '-v[verbose]' '--help'";
  assert.deepEqual(parseCompletion(raw), ['--help', '-v']);
});

test('parseCompletion returns an empty array for prose-only input', () => {
  assert.deepEqual(parseCompletion('no flags here'), []);
});
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `node --test tests/parse.test.mjs`

Expected: failure loading `../scripts/lib/parse.mjs` because the module does not exist.

- [ ] **Step 3: Write the implementation**

Create `package.json`:

```json
{
  "name": "cli-tool-scanner",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "engines": {
    "node": ">=20"
  },
  "scripts": {
    "scan": "node scripts/scan.mjs",
    "test": "node --test"
  }
}
```

Create `scripts/lib/parse.mjs`:

```js
export const MAX_USAGE_BYTES = 262144;
export const MAX_USAGE_LINES = 80;
export const MAX_USAGE_CHARS = 8192;
export const MAX_DESCRIPTION_CHARS = 160;

const REPLACEMENT = String.fromCharCode(0xfffd);

export function truncateOutput(raw, maxBytes = MAX_USAGE_BYTES) {
  if (Buffer.byteLength(raw, 'utf8') <= maxBytes) return raw;
  const bytes = Buffer.from(raw, 'utf8').subarray(0, maxBytes);
  let text = bytes.toString('utf8');
  if (text.endsWith(REPLACEMENT)) text = text.slice(0, -1);
  return text;
}

export function normalizeHelp(raw) {
  const lines = truncateOutput(raw)
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .split('\n')
    .map((line) => line.trimEnd());

  const collapsed = [];
  for (const line of lines) {
    if (line === '' && collapsed.at(-1) === '') continue;
    collapsed.push(line);
  }
  while (collapsed[0] === '') collapsed.shift();
  while (collapsed.at(-1) === '') collapsed.pop();

  if (
    collapsed.length > 1 &&
    collapsed[0].length > 200 &&
    collapsed.slice(1).some((line) => line.trim() !== '')
  ) {
    collapsed.shift();
  }

  const limited = [];
  let chars = 0;
  for (const line of collapsed) {
    if (limited.length >= MAX_USAGE_LINES) break;
    if (chars + line.length + 1 > MAX_USAGE_CHARS) break;
    limited.push(line);
    chars += line.length + 1;
  }
  if (limited.length < collapsed.length) limited.push('[usage truncated]');
  return limited.join('\n');
}

export function looksLikeUsage(text) {
  const visible = normalizeHelp(text).replaceAll('[usage truncated]', '').trim();
  return visible.length >= 20;
}

export function shortenDescription(text, max = MAX_DESCRIPTION_CHARS) {
  if (text.length <= max) return text;
  return text.slice(0, max - 1).trimEnd() + '…';
}

export function extractDescription(raw) {
  const lines = raw
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .split('\n');

  for (const line of lines) {
    const text = line.trim();
    if (text.length < 12) continue;
    if (text.startsWith('-')) continue;
    const lower = text.toLowerCase();
    if (lower.startsWith('usage') || lower.startsWith('synopsis')) continue;
    if (text.split(' ').filter(Boolean).length < 3) continue;
    return shortenDescription(text);
  }
  return '';
}

export function parseCompletion(raw) {
  const matches = raw.match(/--?[A-Za-z0-9][A-Za-z0-9-]*/g) ?? [];
  const flags = [...new Set(matches)]
    .filter((flag) => flag.length > 1 && flag !== '--')
    .sort();
  return flags.slice(0, 20);
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `node --test tests/parse.test.mjs`

Expected: all parse tests pass.

- [ ] **Step 5: Commit**

```bash
git add package.json scripts/lib/parse.mjs tests/parse.test.mjs
git commit -m "feat(scan): add project scaffold and text parsing helpers"
```

---

## Task 2: PATH Discovery and Dedupe

**Files:**
- Create: `scripts/lib/discover.mjs`
- Create: `tests/helpers/fixtures.mjs`
- Test: `tests/discover.test.mjs`

**Interfaces:**
- `discoverTools({ pathEnv = process.env.PATH ?? '' } = {}): Promise<{ tools: Array<{ name: string, path: string, allPaths: string[] }>, pathDirs: string[], skippedDirs: string[] }>`
- Fixture helpers: `makeTempDir(prefix)`, `writeExecutable(dir, name, body)`, `cleanupDir(dir)`

- [ ] **Step 1: Write the failing test**

Create `tests/helpers/fixtures.mjs`:

```js
import { chmod, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export async function makeTempDir(prefix = 'tool-scanner-') {
  return mkdtemp(join(tmpdir(), prefix));
}

export async function writeExecutable(dir, name, body = '#!/bin/sh\nexit 0\n') {
  const path = join(dir, name);
  await writeFile(path, body, 'utf8');
  await chmod(path, 0o755);
  return path;
}

export async function cleanupDir(dir) {
  await rm(dir, { recursive: true, force: true });
}
```

Create `tests/discover.test.mjs`:

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { realpath } from 'node:fs/promises';
import { discoverTools } from '../scripts/lib/discover.mjs';
import { cleanupDir, makeTempDir, writeExecutable } from './helpers/fixtures.mjs';

test('discoverTools finds executables and records PATH directories', async () => {
  const root = await makeTempDir();
  try {
    const binA = join(root, 'a');
    const binB = join(root, 'b');
    await mkdir(binA);
    await mkdir(binB);
    const alphaA = await writeExecutable(binA, 'alpha');
    const betaB = await writeExecutable(binB, 'beta');

    const result = await discoverTools({ pathEnv: `${binA}:${binB}` });

    assert.deepEqual(result.pathDirs, [binA, binB]);
    assert.deepEqual(result.skippedDirs, []);
    assert.deepEqual(result.tools.map((tool) => tool.name), ['alpha', 'beta']);
    assert.equal(result.tools[0].path, await realpath(alphaA));
    assert.equal(result.tools[1].path, await realpath(betaB));
  } finally {
    await cleanupDir(root);
  }
});

test('discoverTools dedupes by basename and preserves all resolved paths in PATH order', async () => {
  const root = await makeTempDir();
  try {
    const binA = join(root, 'a');
    const binB = join(root, 'b');
    await mkdir(binA);
    await mkdir(binB);
    const first = await writeExecutable(binA, 'same');
    const second = await writeExecutable(binB, 'same');

    const result = await discoverTools({ pathEnv: `${binA}:${binB}` });

    assert.equal(result.tools.length, 1);
    assert.equal(result.tools[0].name, 'same');
    assert.equal(result.tools[0].path, await realpath(first));
    assert.deepEqual(result.tools[0].allPaths, [await realpath(first), await realpath(second)]);
  } finally {
    await cleanupDir(root);
  }
});

test('discoverTools skips non-executable files and missing directories', async () => {
  const root = await makeTempDir();
  try {
    const bin = join(root, 'bin');
    await mkdir(bin);
    await writeFile(join(bin, 'plain.txt'), 'not executable', 'utf8');
    const missing = join(root, 'missing');

    const result = await discoverTools({ pathEnv: `${bin}:${missing}` });

    assert.deepEqual(result.tools, []);
    assert.deepEqual(result.pathDirs, [bin, missing]);
    assert.deepEqual(result.skippedDirs, [missing]);
  } finally {
    await cleanupDir(root);
  }
});

test('discoverTools drops empty PATH entries', async () => {
  const result = await discoverTools({ pathEnv: ':/tmp::' });
  assert.deepEqual(result.pathDirs, ['/tmp']);
});
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `node --test tests/discover.test.mjs`

Expected: failure loading `../scripts/lib/discover.mjs` because the module does not exist.

- [ ] **Step 3: Write the implementation**

Create `scripts/lib/discover.mjs`:

```js
import { access, readdir, realpath, stat } from 'node:fs/promises';
import { constants } from 'node:fs';
import { join } from 'node:path';

export async function discoverTools({ pathEnv = process.env.PATH ?? '' } = {}) {
  const pathDirs = pathEnv.split(':').filter(Boolean);
  const tools = [];
  const byName = new Map();
  const skippedDirs = [];

  for (const dir of pathDirs) {
    let entries;
    try {
      entries = await readdir(dir);
    } catch {
      skippedDirs.push(dir);
      continue;
    }

    for (const name of entries.slice().sort()) {
      const candidate = join(dir, name);
      let info;
      try {
        info = await stat(candidate);
      } catch {
        continue;
      }
      if (!info.isFile()) continue;

      try {
        await access(candidate, constants.X_OK);
      } catch {
        continue;
      }

      let resolved;
      try {
        resolved = await realpath(candidate);
      } catch {
        continue;
      }

      const existing = byName.get(name);
      if (existing) {
        if (!existing.allPaths.includes(resolved)) existing.allPaths.push(resolved);
        continue;
      }

      const tool = { name, path: resolved, allPaths: [resolved] };
      byName.set(name, tool);
      tools.push(tool);
    }
  }

  tools.sort((left, right) => (left.name < right.name ? -1 : left.name > right.name ? 1 : 0));
  return { tools, pathDirs, skippedDirs };
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `node --test tests/discover.test.mjs`

Expected: all discovery tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/discover.mjs tests/helpers/fixtures.mjs tests/discover.test.mjs
git commit -m "feat(scan): discover PATH executables with dedupe"
```

<!-- PLAN_CONTINUES -->
