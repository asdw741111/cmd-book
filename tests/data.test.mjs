import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  services,
  hosts,
  deploys,
  metrics,
  getServiceSummary,
  getLatestDeploys,
} from '../js/data.js';

test('services has at least 5 entries with all required keys', () => {
  assert.ok(services.length >= 5, `expected >= 5 services, got ${services.length}`);
  for (const s of services) {
    assert.deepEqual(
      Object.keys(s).sort(),
      ['errorRate', 'latencyMs', 'name', 'rpm', 'status'],
      `service ${s.name} missing keys`
    );
  }
});

test('metrics.cpu has exactly 24 points', () => {
  assert.equal(metrics.cpu.length, 24);
  assert.equal(metrics.mem.length, 24);
  assert.equal(metrics.req.length, 24);
});

test('getLatestDeploys(5) returns 5 items sorted newest-first', () => {
  const latest = getLatestDeploys(5);
  assert.equal(latest.length, 5);
  const times = latest.map((d) => d.time);
  const sorted = [...times].sort().reverse();
  assert.deepEqual(times, sorted, 'expected newest-first by time');
});

test('getServiceSummary returns one entry per service with a status field', () => {
  const summary = getServiceSummary();
  assert.equal(summary.length, services.length);
  for (const s of summary) {
    assert.ok('status' in s, `summary entry ${s.name} missing status`);
  }
});

test('hosts and deploys sample shapes', () => {
  assert.ok(hosts.length >= 5);
  assert.ok(deploys.length >= 10);
  assert.deepEqual(
    Object.keys(hosts[0]).sort(),
    ['cpu', 'hostname', 'mem', 'status', 'uptimeH']
  );
  assert.deepEqual(
    Object.keys(deploys[0]).sort(),
    ['author', 'id', 'result', 'service', 'time']
  );
});
