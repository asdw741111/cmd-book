import test from 'node:test';
import assert from 'node:assert/strict';
import { sortRows, renderTable } from '../js/table.js';

const rows = [
  { name: 'banana', n: 10 },
  { name: 'Apple', n: 9 },
  { name: 'cherry', n: 100 },
];

test('numeric asc and desc sorting', () => {
  assert.deepEqual(sortRows(rows, 'n', 'asc').map((r) => r.n), [9, 10, 100]);
  assert.deepEqual(sortRows(rows, 'n', 'desc').map((r) => r.n), [100, 10, 9]);
});

test('string sort is case-insensitive', () => {
  assert.deepEqual(sortRows(rows, 'name').map((r) => r.name), ['Apple', 'banana', 'cherry']);
});

test('input array is not mutated', () => {
  const original = [...rows];
  sortRows(rows, 'n', 'desc');
  assert.deepEqual(rows, original);
});

test('mixed numeric column sorts numerically, not lexicographically', () => {
  assert.ok(sortRows(rows, 'n', 'asc')[1].n === 10);
  assert.ok(sortRows(rows, 'n', 'asc')[0].n < sortRows(rows, 'n', 'asc')[1].n);
});

test('renderTable emits one th per column and one tr per row', () => {
  const html = renderTable({
    columns: [
      { key: 'name', label: 'Name', type: 'string' },
      { key: 'n', label: 'Count', type: 'number' },
    ],
    rows,
    sortColumn: 'n',
    sortDir: 'asc',
  });
  assert.equal((html.match(/<th\b/g) || []).length, 2);
  assert.equal((html.match(/<tr\b/g) || []).length, rows.length + 1);
  assert.ok(html.includes('data-sort="n"'));
});

test('renderTable escapes cell content', () => {
  const html = renderTable({
    columns: [{ key: 'x', label: 'X', type: 'string' }],
    rows: [{ x: '<script>' }],
    sortColumn: 'x',
    sortDir: 'asc',
  });
  assert.ok(!html.includes('<script>'));
  assert.ok(html.includes('&lt;script&gt;'));
});
