import test from 'node:test';
import assert from 'node:assert/strict';
import { lineChart, barChart, donutChart } from '../js/charts.js';

test('lineChart returns an svg with polyline containing 3 coordinate pairs', () => {
  const svg = lineChart([1, 2, 3]);
  assert.ok(svg.startsWith('<svg'));
  assert.ok(svg.includes('</svg>'));
  const match = svg.match(/<polyline points="([^"]+)"/);
  assert.ok(match, 'expected a <polyline> with points');
  const pairs = match[1].trim().split(/\s+/);
  assert.equal(pairs.length, 3);
  for (const pair of pairs) assert.match(pair, /^-?\d+(\.\d+)?,-?\d+(\.\d+)?$/);
});

test('lineChart with empty data still returns a valid svg', () => {
  const svg = lineChart([]);
  assert.ok(svg.startsWith('<svg'));
  assert.ok(svg.includes('</svg>'));
});

test('barChart emits exactly one rect per bar', () => {
  const bars = [
    { label: 'a', value: 3 },
    { label: 'b', value: 7 },
    { label: 'c', value: 1 },
  ];
  const svg = barChart(bars);
  const occurrences = svg.match(/<rect/g) || [];
  assert.equal(occurrences.length, bars.length);
});

test('barChart escapes labels', () => {
  const svg = barChart([{ label: '<b>', value: 1 }]);
  assert.ok(!svg.includes('<b>'));
  assert.ok(svg.includes('&lt;b&gt;'));
});

test('donutChart uses stroke-dasharray and escapes tooltips', () => {
  const svg = donutChart([
    { label: 'healthy', value: 6, color: 'green' },
    { label: '<down>', value: 2, color: 'red' },
  ]);
  assert.ok(svg.includes('stroke-dasharray'));
  assert.ok(!svg.includes('<down>'));
  assert.ok(svg.includes('&lt;down&gt;'));
});

test('donutChart with zero total does not throw', () => {
  const svg = donutChart([{ label: 'none', value: 0, color: 'gray' }]);
  assert.ok(svg.startsWith('<svg'));
  assert.ok(svg.includes('</svg>'));
});
