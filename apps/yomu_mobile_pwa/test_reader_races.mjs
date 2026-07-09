import {
  nextGen,
  shouldApply,
  loadOnce,
  inflightKey,
  applyBlobIfCurrent,
  captureProgressPayload,
  simulateChapterRace,
  simulateCloseDuringRequest,
  simulateSamePageInflightAcrossGens,
} from './reader_race_logic.mjs';

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

assert(nextGen(0) === 1, 'gen bump');
assert(shouldApply(3, 3), 'same gen');
assert(!shouldApply(4, 3), 'stale gen');
assert(inflightKey(2, 0) === '2:0', 'inflight key');

let loads = 0;
const inflight = new Map();
const p1 = loadOnce(inflight, inflightKey(1, 0), async () => {
  loads++;
  await new Promise((r) => setTimeout(r, 20));
  return 'ok';
});
const p2 = loadOnce(inflight, inflightKey(1, 0), async () => {
  loads++;
  return 'dup';
});
const [a, b] = await Promise.all([p1, p2]);
assert(a === 'ok' && b === 'ok', 'dedupe shares result');
assert(loads === 1, 'loader called once');

// Different gen keys do not collide
const map = new Map();
const revoked = [];
applyBlobIfCurrent(5, 4, map, 0, 'blob:old', (u) => revoked.push(u));
assert(map.size === 0 && revoked[0] === 'blob:old', 'stale blob revoked');
applyBlobIfCurrent(5, 5, map, 0, 'blob:new', (u) => revoked.push(u));
assert(map.get(0) === 'blob:new', 'current applied');

const cap = captureProgressPayload(99, 5, 10, 7);
assert(cap.chapterId === 99 && cap.gen === 7, 'capture');

const race = await simulateChapterRace(async (id, delay) => {
  await new Promise((r) => setTimeout(r, delay));
  return ['p0-' + id];
});
assert(race.rb.applied === true, 'fast chapter applied');
assert(race.ra.applied === false, 'slow chapter ignored');

const closed = simulateCloseDuringRequest();
assert(closed.acceptLate === false, 'late response dropped');

const samePage = await simulateSamePageInflightAcrossGens();
assert(samePage.latestHas === true, 'latest gen has page 0');
assert(samePage.staleHas === false, 'stale gen must not keep page 0');

console.log('reader race logic OK');
