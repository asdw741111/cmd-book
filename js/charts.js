export function esc(s) {
  return String(s)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

const PADDING = 8;

function scalePoints(points, width, height) {
  const max = Math.max(...points);
  const min = Math.min(...points);
  const range = max - min || 1;
  const step = points.length > 1 ? width / (points.length - 1) : width;
  return points.map((value, i) => [
    Number((i * step).toFixed(2)),
    Number((height - PADDING - ((value - min) / range) * (height - PADDING * 2)).toFixed(2)),
  ]);
}

export function lineChart(points, { width = 640, height = 200, label = '' } = {}) {
  const title = label ? `<title>${esc(label)}</title>` : '';
  if (!Array.isArray(points) || points.length === 0) {
    return `<svg viewBox="0 0 ${width} ${height}" role="img" aria-label="${esc(label)}">${title}</svg>`;
  }
  const coords = scalePoints(points, width, height);
  const line = coords.map(([x, y]) => `${x},${y}`).join(' ');
  const area = `M${coords[0][0]},${height} L${line.replaceAll(' ', ' L')} L${coords[coords.length - 1][0]},${height} Z`;
  return `<svg viewBox="0 0 ${width} ${height}" role="img" aria-label="${esc(label)}">${title}<path d="${area}" fill="var(--accent)" fill-opacity="0.15" stroke="none"/><polyline points="${line}" fill="none" stroke="var(--accent)" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/></svg>`;
}

export function barChart(bars, { width = 640, height = 200, label = '' } = {}) {
  const title = label ? `<title>${esc(label)}</title>` : '';
  if (!Array.isArray(bars) || bars.length === 0) {
    return `<svg viewBox="0 0 ${width} ${height}" role="img" aria-label="${esc(label)}">${title}</svg>`;
  }
  const max = Math.max(...bars.map((b) => Number(b.value) || 0), 1);
  const slot = width / bars.length;
  const barWidth = Math.max(slot * 0.6, 1);
  const chartHeight = height - PADDING * 2 - 16;
  const rects = bars.map((bar, i) => {
    const value = Number(bar.value) || 0;
    const barHeight = (value / max) * chartHeight;
    const x = i * slot + (slot - barWidth) / 2;
    const y = height - PADDING - 16 - barHeight;
    return `<rect x="${x.toFixed(2)}" y="${y.toFixed(2)}" width="${barWidth.toFixed(2)}" height="${barHeight.toFixed(2)}" fill="var(--accent)"><title>${esc(bar.label)}: ${esc(value)}</title></rect>`;
  });
  const labels = bars.map((bar, i) => {
    const x = i * slot + slot / 2;
    return `<text x="${x.toFixed(2)}" y="${height - 4}" text-anchor="middle" font-size="11" fill="var(--text-dim)">${esc(bar.label)}</text>`;
  });
  return `<svg viewBox="0 0 ${width} ${height}" role="img" aria-label="${esc(label)}">${title}${rects.join('')}${labels.join('')}</svg>`;
}

export function donutChart(segments, { size = 180, label = '' } = {}) {
  const title = label ? `<title>${esc(label)}</title>` : '';
  const total = (Array.isArray(segments) ? segments : []).reduce((sum, s) => sum + (Number(s.value) || 0), 0);
  const radius = size / 2 - 12;
  const circumference = 2 * Math.PI * radius;
  const center = size / 2;
  const fallbackColors = ['var(--series-1)', 'var(--series-2)', 'var(--series-3)'];
  if (!Array.isArray(segments) || segments.length === 0 || total <= 0) {
    return `<svg viewBox="0 0 ${size} ${size}" width="${size}" height="${size}" role="img" aria-label="${esc(label)}">${title}<circle cx="${center}" cy="${center}" r="${radius}" fill="none" stroke="var(--border)" stroke-width="24"/></svg>`;
  }
  let offset = 0;
  const arcs = segments.map((segment, i) => {
    const value = Number(segment.value) || 0;
    const fraction = value / total;
    const dash = fraction * circumference;
    const color = segment.color || fallbackColors[i % fallbackColors.length];
    const arc = `<circle cx="${center}" cy="${center}" r="${radius}" fill="none" stroke="${esc(color)}" stroke-width="24" stroke-dasharray="${dash.toFixed(2)} ${(circumference - dash).toFixed(2)}" stroke-dashoffset="${(-offset).toFixed(2)}" transform="rotate(-90 ${center} ${center})"><title>${esc(segment.label)}: ${esc(value)}</title></circle>`;
    offset += dash;
    return arc;
  });
  return `<svg viewBox="0 0 ${size} ${size}" width="${size}" height="${size}" role="img" aria-label="${esc(label)}">${title}${arcs.join('')}</svg>`;
}
