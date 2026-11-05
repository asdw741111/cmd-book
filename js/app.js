import { services, deploys, hosts, metrics, getLatestDeploys } from './data.js';
import { lineChart, barChart, donutChart, esc } from './charts.js';
import { sortRows, renderTable } from './table.js';
import { STORAGE_KEY, getTheme, setTheme, applyTheme } from './theme.js';

const view = document.getElementById('view');
const toggle = document.getElementById('theme-toggle');
const navLinks = document.querySelectorAll('.sidebar a[data-route]');

const sortState = {
  overview: { column: 'time', dir: 'desc' },
  services: { column: 'name', dir: 'asc' },
  deploys: { column: 'time', dir: 'desc' },
  hosts: { column: 'hostname', dir: 'asc' },
};

const STATUS_GLYPHS = { healthy: '●', degraded: '▲', down: '■', success: '●', failed: '■', 'rolled-back': '▲' };

const statusPill = (status) =>
  `<span class="status status-${esc(status)}">${STATUS_GLYPHS[status] || '●'} ${esc(status)}</span>`;

const deployColumns = [
  { key: 'id', label: 'Deploy', type: 'string' },
  { key: 'service', label: 'Service', type: 'string' },
  { key: 'time', label: 'Time', type: 'string' },
  { key: 'author', label: 'Author', type: 'string' },
  { key: 'result', label: 'Result', type: 'string', format: (v) => statusPill(v) },
];

const serviceColumns = [
  { key: 'name', label: 'Service', type: 'string' },
  { key: 'status', label: 'Status', type: 'string', format: (v) => statusPill(v) },
  { key: 'latencyMs', label: 'Latency (ms)', type: 'number' },
  { key: 'errorRate', label: 'Error rate', type: 'number' },
  { key: 'rpm', label: 'RPM', type: 'number' },
];

const hostColumns = [
  { key: 'hostname', label: 'Host', type: 'string' },
  { key: 'cpu', label: 'CPU %', type: 'number' },
  { key: 'mem', label: 'Mem %', type: 'number' },
  { key: 'uptimeH', label: 'Uptime (h)', type: 'number' },
  { key: 'status', label: 'Status', type: 'string', format: (v) => statusPill(v) },
];

function tableCard(title, columns, rows, viewKey) {
  const { column, dir } = sortState[viewKey];
  const sorted = sortRows(rows, column, dir);
  return `<div class="card"><h3>${esc(title)}</h3>${renderTable({
    columns,
    rows: sorted,
    sortColumn: column,
    sortDir: dir,
  })}</div>`;
}

function chartCard(title, svg) {
  return `<div class="card chart"><h3>${esc(title)}</h3>${svg}</div>`;
}

function renderOverview() {
  const counts = services.reduce((acc, s) => {
    acc[s.status] = (acc[s.status] || 0) + 1;
    return acc;
  }, {});
  const donut = donutChart(
    [
      { label: 'healthy', value: counts.healthy || 0, color: 'var(--green)' },
      { label: 'degraded', value: counts.degraded || 0, color: 'var(--amber)' },
      { label: 'down', value: counts.down || 0, color: 'var(--red)' },
    ],
    { label: 'Service health' },
  );
  view.innerHTML = `
    <h2>Overview</h2>
    <div class="grid">
      ${chartCard('CPU (24h)', lineChart(metrics.cpu, { label: 'CPU usage over 24 hours' }))}
      ${chartCard('Service health', donut)}
    </div>
    <div class="grid" style="margin-top:16px">
      ${tableCard('Recent deploys', deployColumns, getLatestDeploys(5), 'overview')}
    </div>`;
}

function renderServices() {
  const bars = services.map((s) => ({ label: s.name, value: s.latencyMs }));
  view.innerHTML = `
    <h2>Services</h2>
    <div class="grid">
      ${chartCard('Latency (ms)', barChart(bars, { label: 'Latency per service' }))}
    </div>
    <div class="grid" style="margin-top:16px">
      ${tableCard('All services', serviceColumns, services, 'services')}
    </div>`;
}

function renderDeploys() {
  view.innerHTML = `
    <h2>Deploys</h2>
    <div class="grid">
      ${tableCard('All deploys', deployColumns, deploys, 'deploys')}
    </div>`;
}

function renderHosts() {
  view.innerHTML = `
    <h2>Hosts</h2>
    <div class="grid">
      ${tableCard('Hosts', hostColumns, hosts, 'hosts')}
    </div>`;
}

const routes = {
  overview: renderOverview,
  services: renderServices,
  deploys: renderDeploys,
  hosts: renderHosts,
};

function currentRoute() {
  const hash = location.hash.replace(/^#\/?/, '');
  return routes[hash] ? hash : 'overview';
}

function router() {
  const route = currentRoute();
  navLinks.forEach((link) => link.classList.toggle('active', link.dataset.route === route));
  routes[route]();
}

view.addEventListener('click', (event) => {
  const th = event.target.closest('th[data-sort]');
  if (!th) return;
  const route = currentRoute();
  const state = sortState[route];
  const column = th.dataset.sort;
  state.dir = state.column === column && state.dir === 'asc' ? 'desc' : 'asc';
  state.column = column;
  router();
});

function syncToggleLabel() {
  toggle.textContent = getTheme() === 'dark' ? 'Switch to light' : 'Switch to dark';
}

toggle.addEventListener('click', () => {
  const next = getTheme() === 'dark' ? 'light' : 'dark';
  setTheme(next);
  applyTheme(next);
  syncToggleLabel();
  router();
});

applyTheme(getTheme());
syncToggleLabel();
window.addEventListener('hashchange', router);
router();
