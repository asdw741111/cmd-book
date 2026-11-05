# Command — DevOps Monitoring Dashboard

A static, zero-dependency ops dashboard: Overview, Services, Deploys, and
Hosts views over hardcoded sample data. Vanilla HTML/CSS/JS with ES modules —
no build step.

## Run

ES modules require HTTP (opening `index.html` via `file://` will fail):

```sh
python3 -m http.server 8000
```

Then open http://localhost:8000/.

## Test

Unit tests cover the pure modules (`data`, `charts`, `table`, `theme`) with
Node's built-in test runner:

```sh
node --test
```

Requires Node 18+.

## Structure

- `index.html` — app shell (sidebar, header, view container)
- `css/tokens.css` — theme custom properties (dark default, light via
  `data-theme="light"`)
- `css/app.css` — layout and components
- `js/data.js` — sample data and derived helpers
- `js/charts.js` — pure SVG chart builders
- `js/table.js` — table sorting and rendering
- `js/theme.js` — theme get/set/apply
- `js/app.js` — routing and view rendering
- `tests/` — unit tests
- `docs/design.md` — design document
