// Minimal pure-logic checks for Phase 2D preload window (no browser).
// Run: node apps/yomu_mobile_pwa/test_preload_logic.mjs

const PRELOAD_AHEAD = 2;
const PRELOAD_BEHIND = 1;

function windowRange(center, n) {
  const lo = Math.max(0, center - PRELOAD_BEHIND);
  const hi = Math.min(n - 1, center + PRELOAD_AHEAD);
  const set = new Set();
  for (let i = lo; i <= hi; i++) set.add(i);
  return set;
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

const n = 20;
assert(windowRange(0, n).size === 3, 'start window 0..2');
assert(windowRange(10, n).has(9) && windowRange(10, n).has(12), 'mid window');
assert(!windowRange(10, n).has(8), 'no behind+2');
assert(!windowRange(10, n).has(13), 'no ahead+3');
assert(windowRange(19, n).size === 2, 'end window 18..19');

// Thumbnail absolute must not get Bearer from client — client only fetches paths starting with /
function shouldAuthFetch(url) {
  return typeof url === 'string' && url.startsWith('/');
}
assert(shouldAuthFetch('/api/v1/media?t=abc'), 'ticket path ok');
assert(!shouldAuthFetch('https://cdn.example/thumb.jpg'), 'no external bearer');

console.log('preload logic OK');
