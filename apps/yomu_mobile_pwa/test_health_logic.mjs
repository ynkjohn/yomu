import { engineReadyFromHealth } from './health_logic.mjs';

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

assert(engineReadyFromHealth({ engineReady: true }), 'new readiness true');
assert(!engineReadyFromHealth({ engineReady: false }), 'new readiness false');
assert(
  !engineReadyFromHealth({ engineReady: false, suwayomiReady: true }),
  'new readiness takes precedence over compatibility alias',
);
assert(
  engineReadyFromHealth({ suwayomiReady: true }),
  'LAN compatibility alias remains supported',
);
assert(
  engineReadyFromHealth({ suwayomi: { state: 'running', isReady: false } }),
  'loopback compatibility alias remains supported',
);
assert(!engineReadyFromHealth(null), 'missing health is unavailable');

console.log('health logic OK');
