# Design: DevOps Monitoring Dashboard

A static, zero-dependency monitoring dashboard in the spirit of Grafana / Datadog.

## Concept

A single-page ops console showing four views — Overview, Services, Deploys, and
Hosts — driven by hardcoded sample data. Dark, compact, numerically precise.

## Visual Language

- **Background**: dark charcoal (`--bg: #111417`, surfaces `#1a1f24` / `#21272d`).
- **Status**: green (healthy) `#3fb950`, amber (degraded) `#d29922`, red
  (down/critical) `#f85149`.
- **Data series**: blue `#58a6ff`, cyan `#39c5cf`, indigo `#a371f7` — rendered
  as `var(--accent)` so themes stay consistent.
- **Typography**: system sans for UI; tabular numerals (`font-variant-numeric:
  tabular-nums`) on all metrics so digits align in tables and stat cells.
- **Density**: compact — tight table rows, small chart paddings, 8px spacing
  rhythm (4 / 8 / 12 / 16 / 24 / 32).
- **Status always dual-encoded**: color + glyph (●/▲/■) so it survives
  grayscale and color-blind viewing.

## Layout

```
┌──────────┬────────────────────────────────────────────┐
│ Sidebar  │ Header (view title + theme toggle)         │
│ 220px    ├────────────────────────────────────────────┤
│ fixed    │ Main content (scrollable)                  │
│          │  - charts, tables, cards per route         │
└──────────┴────────────────────────────────────────────┘
```

- Sidebar is fixed-width 220px, full height, with brand mark and nav links.
- Nav is hash-routed: `#/overview`, `#/services`, `#/deploys`, `#/hosts`.
  Unknown hashes fall back to `#/overview`.
- Main content fills remaining width; max readable width is not capped (data
  tables want the space).

## Views

### Overview
- Four metric sparkline/area charts: request rate, error rate, p99 latency,
  CPU utilization (24h samples).
- Donut chart of current service status distribution (healthy / degraded /
  down).
- Bar chart of deploys per day over the last 14 days.

### Services
- Data table: name, status, uptime %, p99 latency, error rate, owner.
- Sortable columns (click header toggles asc/desc; default sort: name asc).

### Deploys
- Data table: time, service, version, author, result (success / failed /
  rolled back).
- Sorted newest-first by default; columns sortable.

### Hosts
- Data table: hostname, region, status, CPU %, memory %, uptime.
- Sortable; default sort hostname asc.

## Charts

Hand-rolled inline SVG built by pure functions in `js/charts.js`:

- `lineChart({ points, width, height, accent })` — line + area fill with
  axis ticks; used for the 24h metric sparklines.
- `barChart({ bars, width, height, accent })` — vertical bars with baseline;
  used for deploys/day.
- `donutChart({ segments, size, thickness })` — status distribution; segments
  colored by status palette.

All charts return SVG strings; the caller injects via `innerHTML`. Series
color is `var(--accent)` (or the status palette), so a theme switch only needs
a re-render for label colors baked as SVG attributes. Tooltips use SVG
`<title>` for v1 (no JS hover layer).

## Data

`js/data.js` exports hardcoded fixtures:

- `metrics` — 24 points (hourly) for four series: `requestRate`, `errorRate`,
  `p99`, `cpu`.
- `services` — ~8 services with `name, status, uptime, p99, errorRate, owner`.
- `hosts` — ~10 hosts with `hostname, region, status, cpu, memory, uptime`.
- `deploys` — ~20 deploys with `time, service, version, author, result`.
- Helpers: `getServiceSummary()` (status counts), `getLatestDeploys(n)`.

Dates are ISO-8601 strings; formatting happens at render time.

## Theming

- CSS custom properties defined in `css/tokens.css`.
- Dark is default; light applied via `data-theme="light"` on `<html>`.
- `js/theme.js`: `STORAGE_KEY = 'theme'`, `getTheme(storage)`,
  `setTheme(storage, value)`, `applyTheme(theme)` — storage is injectable
  (defaults to `window.localStorage`) for testability.
- Inline pre-theme script in `<head>` reads localStorage and sets the
  attribute before first paint (no flash).
- Toggle button in the header; on change, `applyTheme` + re-render charts.

## Structure

```
command/
├── index.html          # shell: sidebar, header, <main id="view">
├── css/
│   ├── tokens.css      # custom properties, dark + light themes
│   └── app.css         # layout, components, tables, charts
├── js/
│   ├── data.js         # fixtures + pure helpers
│   ├── charts.js       # pure SVG chart builders
│   ├── table.js        # sortRows + renderTable
│   ├── theme.js        # get/set/apply theme (injectable storage)
│   └── app.js          # routes, renders, events, entry point
├── tests/              # node:test units for pure modules
├── docs/
│   ├── design.md       # this file
│   └── superpowers/plans/
└── README.md
```

## Interaction

- Sidebar links set `location.hash`; `hashchange` re-renders the view.
- Table headers are `<button>`s inside `<th>`; click sorts.
- Theme toggle button flips dark/light and persists to localStorage.
- No modals, no forms, no live updates in v1.

## Accessibility & Responsiveness

- Semantic landmarks: `<nav>`, `<main>`, `<header>`; headings per view.
- Focus visible on all interactive elements; nav marks current route with
  `aria-current="page"`.
- Tables use real `<table>` markup with `<th scope="col">`.
- Charts carry `role="img"` and an `aria-label` summary.
- At <768px: sidebar collapses to a horizontal top bar; tables scroll
  horizontally in a wrapper.

## Non-Goals

- No real data sources, APIs, or websockets.
- No build step, bundler, or framework.
- No canvas/WebGL charts, no chart tooltips beyond `<title>`.
- No mobile-first redesign (desktop-first, minimally responsive).
