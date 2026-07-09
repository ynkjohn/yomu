import {
  nextGen,
  shouldApply,
  loadOnce,
  captureProgressPayload,
  simulateChapterRace,
  simulateCloseDuringRequest,
} from './reader_race_logic.mjs';

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

// generation
assert(nextGen(0) === 1, 'gen bump');
assert(shouldApply(3, 3), 'same gen');
assert(!shouldApply(4, 3), 'stale gen');

// inflight dedupe
let loads = 0;
const inflight = new Map();
const p1 = loadOnce(inflight, 0, async () => {
  loads++;
  await new Promise((r) => setTimeout(r, 20));
  return 'ok';
});
const p2 = loadOnce(inflight, 0, async () => {
  loads++;
  return 'dup';
});
const [a, b] = await Promise.all([p1, p2]);
assert(a === 'ok' && b === 'ok', 'dedupe shares result');
assert(loads === 1, 'loader called once');

// progress capture uses chapterId not global
const cap = captureProgressPayload(99, 5, 10, 7);
assert(cap.chapterId === 99 && cap.page === 5 && cap.gen === 7, 'capture');

// rapid chapter switch
const race = await simulateChapterRace(async (id, delay) => {
  await new Promise((r) => setTimeout(r, delay));
  return ['p0-' + id];
});
assert(race.rb.applied === true, 'fast chapter applied');
assert(race.ra.applied === false, 'slow chapter ignored');
assert(race.applied.length === 1 && race.applied[0].chapterId === 2, 'only B');

// close during request
const closed = simulateCloseDuringRequest();
assert(closed.acceptLate === false, 'late response dropped');
assert(closed.revoked.length === 2, 'blobs revoked on close');

console.log('reader race logic OK');
