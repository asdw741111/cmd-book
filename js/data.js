export const services = [
  { name: 'api-gateway', status: 'healthy', latencyMs: 142, errorRate: 0.001, rpm: 4820 },
  { name: 'auth-service', status: 'healthy', latencyMs: 96, errorRate: 0.0004, rpm: 1930 },
  { name: 'checkout', status: 'degraded', latencyMs: 684, errorRate: 0.018, rpm: 760 },
  { name: 'inventory', status: 'healthy', latencyMs: 210, errorRate: 0.002, rpm: 1210 },
  { name: 'payments', status: 'healthy', latencyMs: 320, errorRate: 0.0008, rpm: 980 },
  { name: 'notifications', status: 'healthy', latencyMs: 75, errorRate: 0.003, rpm: 540 },
  { name: 'search', status: 'healthy', latencyMs: 188, errorRate: 0.001, rpm: 2450 },
  { name: 'web-frontend', status: 'down', latencyMs: 0, errorRate: 1, rpm: 0 },
];

export const hosts = [
  { hostname: 'web-01', cpu: 42, mem: 61, uptimeH: 724, status: 'healthy' },
  { hostname: 'web-02', cpu: 55, mem: 67, uptimeH: 724, status: 'healthy' },
  { hostname: 'web-03', cpu: 71, mem: 74, uptimeH: 312, status: 'healthy' },
  { hostname: 'db-01', cpu: 38, mem: 82, uptimeH: 1450, status: 'healthy' },
  { hostname: 'db-02', cpu: 44, mem: 79, uptimeH: 1450, status: 'healthy' },
  { hostname: 'cache-01', cpu: 22, mem: 48, uptimeH: 990, status: 'healthy' },
  { hostname: 'worker-01', cpu: 88, mem: 76, uptimeH: 156, status: 'degraded' },
  { hostname: 'worker-02', cpu: 12, mem: 31, uptimeH: 156, status: 'healthy' },
  { hostname: 'edge-01', cpu: 63, mem: 58, uptimeH: 2100, status: 'healthy' },
  { hostname: 'edge-02', cpu: 0, mem: 0, uptimeH: 0, status: 'down' },
];

export const deploys = [
  { id: 'd15', service: 'checkout', time: '2026-11-05 09:42', author: 'jane', result: 'failed' },
  { id: 'd14', service: 'web-frontend', time: '2026-11-05 09:10', author: 'bob', result: 'failed' },
  { id: 'd13', service: 'api-gateway', time: '2026-11-05 08:55', author: 'alice', result: 'success' },
  { id: 'd12', service: 'search', time: '2026-11-05 08:30', author: 'carol', result: 'success' },
  { id: 'd11', service: 'notifications', time: '2026-11-05 07:15', author: 'bob', result: 'success' },
  { id: 'd10', service: 'payments', time: '2026-11-04 22:05', author: 'alice', result: 'success' },
  { id: 'd9', service: 'inventory', time: '2026-11-04 18:40', author: 'jane', result: 'rolled-back' },
  { id: 'd8', service: 'auth-service', time: '2026-11-04 16:20', author: 'carol', result: 'success' },
  { id: 'd7', service: 'api-gateway', time: '2026-11-04 14:02', author: 'alice', result: 'success' },
  { id: 'd6', service: 'web-frontend', time: '2026-11-04 11:48', author: 'bob', result: 'success' },
  { id: 'd5', service: 'search', time: '2026-11-03 20:33', author: 'carol', result: 'success' },
  { id: 'd4', service: 'checkout', time: '2026-11-03 15:12', author: 'jane', result: 'success' },
  { id: 'd3', service: 'payments', time: '2026-11-03 10:05', author: 'alice', result: 'rolled-back' },
  { id: 'd2', service: 'inventory', time: '2026-11-02 19:44', author: 'jane', result: 'success' },
  { id: 'd1', service: 'auth-service', time: '2026-11-02 09:21', author: 'carol', result: 'success' },
];

export const metrics = {
  cpu: [34, 36, 41, 39, 45, 52, 48, 55, 61, 58, 63, 67, 72, 69, 64, 60, 57, 54, 50, 47, 44, 42, 39, 37],
  mem: [58, 58, 59, 60, 61, 63, 64, 66, 68, 70, 71, 73, 74, 75, 75, 74, 73, 72, 71, 70, 69, 68, 67, 66],
  req: [820, 760, 690, 640, 710, 980, 1450, 1980, 2410, 2680, 2890, 3050, 3120, 2980, 2870, 2750, 2610, 2440, 2280, 2010, 1720, 1430, 1180, 960],
};

export function getServiceSummary() {
  return services.map((s) => ({ name: s.name, status: s.status }));
}

export function getLatestDeploys(n) {
  return [...deploys].sort((a, b) => b.time.localeCompare(a.time)).slice(0, n);
}
