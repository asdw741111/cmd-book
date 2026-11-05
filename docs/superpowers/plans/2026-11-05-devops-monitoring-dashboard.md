# Plan: DevOps Monitoring Dashboard (vanilla HTML/CSS/JS)

Status: drafted 2026-11-05. Awaiting review.

## File Structure

All paths relative to `/Users/peter/ai/try/command/`.

```
command/
├── index.html                 # Shell: sidebar nav, main mount point, theme script
├── css/
│   ├── tokens.css             # CSS custom properties: dark (default) + [data-theme="light"]
│   └── app.css                # Layout (sidebar + main), cards, table, tooltip
├── js/
│   ├── data.js                # Hardcoded sample data + query helpers (pure)
│   ├── charts.js              # SVG-string builders: lineChart, barChart, donutChart (pure)
│   ├── table.js               # sortRows() + renderTable() (pure builders)
│   ├── theme.js               # getTheme/setTheme/applyTheme, localStorage persistence
│   └── app.js                 # Hash routing + view rendering orchestration
├── tests/
│   ├── data.test.mjs
│   ├── charts.test.mjs
│   ├── table.test.mjs
│   └── theme.test.mjs
├── docs/
│   └── design.md              # Approved design doc
└── README.md                  # How to run
```

Runtime: zero dependencies, ES modules (`<script type="module">`), served via
`python3 -m http.server` or any static server. `file://` works for most, but ES
modules require an HTTP origin, so README documents `python3 -m http.server`.

Testing: Node built-in test runner (`node --test tests/`). All tested modules are
pure functions (no DOM), so tests run in Node directly. DOM/orchestration code in
`app.js` is covered by the manual acceptance gate.

## Design Decisions (approved)

- **Stack**: vanilla HTML/CSS/JS, ES modules, no build step, no dependencies.
- **Data**: hardcoded sample data in `js/data.js`. Four views: Overview, Services, Deploys, Hosts.
- **Charts**: hand-rolled inline SVG strings (`<svg>…</svg>` returned from pure functions). No libraries.
- **Theme**: CSS custom properties. Dark is default; light via `[data-theme="light"]` on `<html>`. Persisted in `localStorage["theme"]`. Charts read accent values from CSS vars at render time; re-render on theme change.
- **Layout**: fixed left sidebar nav + main content (Grafana/Datadog style). Hash routing: `#/overview`, `#/services`, `#/deploys`, `#/hosts`.
- **Features required**: line/area chart, bar chart, donut chart, sortable data table, dark/light toggle.
- **Features NOT required**: KPI stat cards, live data, backend.
- **Visual**: dark charcoal background, status colors (green/amber/red), blue/cyan data series, tabular numerals, compact density.
- **Tooltip**: SVG `<title>` elements (native browser tooltip) for v1 — simplest that works.

## Tasks

### Task 1: Scaffold repo and design doc

- Write `docs/design.md` (paste approved design content).
- Write `README.md` with: run instructions (`python3 -m http.server 8000`), test instructions (`node --test tests/`), project overview.
- `git init` + initial commit of docs only.

**Verify**: `git log --oneline` shows 1 commit; files exist.

### Task 2: Sample data module (`js/data.js`)

Export shape:

```js
// js/data.js
export const services = [{ name, status, latencyMs, errorRate, rpm }];   // ~8 rows
export const hosts     = [{ hostname, cpu, mem, uptimeH, status }];       // ~10 rows
export const deploys   = [{ id, service, time, author, result }];         // ~15 rows
export const metrics   = { cpu: number[], mem: number[], req: number[] }; // 24 points each

export function getServiceSummary();      // aggregates for Overview
export function getLatestDeploys(n);      // slice newest-first
```

Sample data is realistic-looking dummy values (e.g. `api-gateway`, `checkout`, `web-frontend`).

Tests (`tests/data.test.mjs`):
- `services` has ≥ 5 entries, each with all 5 keys.
- `metrics.cpu` length === 24.
- `getLatestDeploys(5)` returns 5 items, sorted newest-first.
- `getServiceSummary()` returns one entry per service with a `status` field.

**Verify**: `node --test tests/data.test.mjs` passes.

### Task 3: Theme module (`js/theme.js`)

```js
// js/theme.js
export const STORAGE_KEY = 'theme';
export function getTheme(storage = globalThis.localStorage);   // 'dark' | 'light', defaults 'dark'
export function setTheme(theme, storage = globalThis.localStorage);
export function applyTheme(theme, root = document.documentElement);
// applyTheme: root.setAttribute('data-theme', theme === 'light' ? 'light' : 'dark')
```

Storage is injected so tests can pass a fake `{ getItem, setItem }`.

Tests (`tests/theme.test.mjs`):
- defaults to `'dark'` when storage empty.
- `setTheme('light')` then `getTheme()` === `'light'`.
- rejects unknown values → falls back to `'dark'`.
- `applyTheme` sets `data-theme="light"` on a stub root object.

**Verify**: `node --test tests/theme.test.mjs` passes.

### Task 4: SVG chart builders (`js/charts.js`)

All pure: accept data + options, return an SVG markup string. Use `var(--accent)` CSS variables for colors so themes work without re-passing colors.

```js
// js/charts.js
export function lineChart(points, { width = 640, height = 200, label = '' } = {});
// points: number[] → polyline path + area fill

export function barChart(bars, { width = 640, height = 200, label = '' } = {});
// bars: [{ label, value }] → rects + x-axis labels

export function donutChart(segments, { size = 180, label = '' } = {});
// segments: [{ label, value, color }] → stroke-dasharray donut + <title> tooltips
```

Include a shared `esc(s)` helper for XML-escaping labels.

Tests (`tests/charts.test.mjs`):
- `lineChart([1,2,3])` starts with `<svg` and contains `</svg>`.
- contains a `<polyline` or `<path` with 3 coordinate pairs.
- `barChart` output contains exactly `bars.length` occurrences of `<rect`.
- `donutChart` output contains `stroke-dasharray`.
- labels are escaped: `barChart([{label: '<b>', value: 1}])` does not contain a raw `<b>` element.
- zero-data edge: `lineChart([])` still returns a valid `<svg>…</svg>` (no throw).

**Verify**: `node --test tests/charts.test.mjs` passes.

### Task 5: Table module (`js/table.js`)

```js
// js/table.js
export function sortRows(rows, column, direction = 'asc');
// direction: 'asc' | 'desc'. Numeric vs string comparison inferred from value type.
// Returns a new array (does not mutate input).

export function renderTable({ columns, rows, sortColumn, sortDir });
// columns: [{ key, label, type: 'number'|'string' }]
// Returns HTML string with <th> (with data-sort attrs) + <tbody> rows.
```

Tests (`tests/table.test.mjs`):
- numeric asc/desc sorting correct.
- string sort is case-insensitive.
- input array is not mutated.
- `renderTable` output contains one `<th>` per column and one `<tr>` per row.
- mixed types (number column) sort numerically, not lexicographically (`10 > 9`).

**Verify**: `node --test tests/table.test.mjs` passes.

### Task 6: HTML shell + CSS (`index.html`, `css/tokens.css`, `css/app.css`)

- `index.html`: `<html data-theme="dark">`, sidebar `<nav>` with 4 links (`#/overview` … `#/hosts`), `<main id="view">` mount, theme toggle button, `<link rel="stylesheet">` for both CSS files, `<script type="module" src="js/app.js">`. Inline pre-theme script reads `localStorage` before first paint to avoid flash.
- `tokens.css`: `:root { --bg, --bg-card, --text, --text-dim, --accent, --green, --amber, --red, --series-1..3, --border }` dark defaults; `[data-theme="light"]` overrides.
- `app.css`: CSS grid/flex sidebar layout (fixed 220px sidebar, main scrolls), card styles, table styles (tabular-nums, compact rows), nav active state, toggle button, responsive collapse below 720px.

**Verify**: open `index.html` via `python3 -m http.server 8000` → shell renders with sidebar; no console errors.

### Task 7: App orchestration (`js/app.js`)

```js
// js/app.js
import { renderOverview, renderServices, renderDeploys, renderHosts } from ...;
// (view render functions live in app.js or a views.js if app.js grows large)

function router();            // reads location.hash, default '#/overview', renders into #view
window.addEventListener('hashchange', router);
// Theme toggle: click → setTheme → applyTheme → router() (re-render charts with new vars)
```

Each view renders cards + charts + table by composing the modules from Tasks 2–5.
`renderTable`-generated `<th>` elements get click handlers for sort (re-render just the table).

**Verify**: navigate all 4 routes; charts render; table sorts on header click; theme toggle re-renders all charts in the new palette.

### Task 8: Acceptance gate (manual)

- [ ] Overview: line/area chart (CPU) + donut (status) + recent deploys table render.
- [ ] Services: bar chart (latency) + full sortable services table.
- [ ] Deploys: sortable deploys table.
- [ ] Hosts: sortable hosts table with status colors.
- [ ] Theme toggle switches dark↔light; persists across reload (`localStorage`).
- [ ] Charts use theme accent colors (visibly change on toggle).
- [ ] Sidebar nav switches views via hash; back/forward works.
- [ ] Table headers sort asc/desc on click; numbers sort numerically.
- [ ] `node --test tests/` passes (all 4 test files).
- [ ] No browser console errors.

**Verify**: all checkboxes checked → done.

## Scope Check

Single subsystem (one static web page + its modules). No independent subsystems
that would justify splitting. Task count (8) is within range. Not splitting.

## Commit Points

- After Task 1: `chore: add design doc and README`
- After Tasks 2–5 (each): `feat(data): …`, `feat(theme): …`, `feat(charts): …`, `feat(table): …`
- After Task 6: `feat(ui): add shell and styles`
- After Task 7: `feat(app): wire routing and views`
- After Task 8: verification only, no commit unless fixes needed.
