import {
  nextGen,
  shouldApply,
  loadOnce,
  inflightKey,
  applyBlobIfCurrent,
  captureProgressPayload,
  deleteInflightIfSame,
  attachAbortIfOwner,
  abortAllInflight,
  createReaderChapterController,
  simulateChapterRace,
  simulateCloseDuringRequest,
  simulateSamePageInflightAcrossGens,
  simulateSlowAThenFastBSameController,
} from './reader_race_logic.mjs';

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

assert(nextGen(0) === 1, 'gen bump');
assert(shouldApply(3, 3), 'same gen');
assert(!shouldApply(4, 3), 'stale gen');
assert(inflightKey(2, 0) === '2:0', 'inflight key');

// a) loadOnce returns exactly the Map-stored Promise while pending
{
  const inflight = new Map();
  let resolveLoader;
  const p = loadOnce(inflight, 'k', () => new Promise((r) => {
    resolveLoader = r;
  }));
  assert(p === inflight.get('k'), 'loadOnce === inflight.get(key) while pending');
  // Not an async-function wrapper: same ref as Map entry (async would return a new Promise).
  assert(Object.is(p, inflight.get('k')), 'Object.is identity with Map');
  await Promise.resolve(); // let .then(loader) schedule
  assert(typeof resolveLoader === 'function', 'loader started');
  resolveLoader('done');
  await p;
}

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
assert(p1 === p2, 'dedupe returns same promise ref');
assert(p1 === inflight.get(inflightKey(1, 0)), 'same as map entry');
const [a, b] = await Promise.all([p1, p2]);
assert(a === 'ok' && b === 'ok', 'dedupe shares result');
assert(loads === 1, 'loader called once');

// b) revoke/close aborts owner before resolution
{
  const m = new Map();
  let aborted = false;
  let resolveLoader;
  const p = loadOnce(m, 'page0', () => new Promise((r) => {
    resolveLoader = r;
  }));
  attachAbortIfOwner(p, () => {
    aborted = true;
  });
  // second attach must not replace owner
  let replaced = false;
  attachAbortIfOwner(p, () => {
    replaced = true;
  });
  abortAllInflight(m);
  assert(aborted === true, 'revoke/close aborts before resolve');
  assert(replaced === false, 'existing AbortController not replaced');
  await Promise.resolve();
  resolveLoader('x');
  await p;
}

// c) old Promise finally must not delete newer Map entry
{
  const m = new Map();
  let resolveOld;
  const pOld = loadOnce(m, '1:0', () => new Promise((r) => {
    resolveOld = r;
  }));
  await Promise.resolve();
  const pNew = Promise.resolve('new');
  m.set('1:0', pNew); // supersede while old still pending
  resolveOld('old');
  await pOld;
  assert(m.get('1:0') === pNew, 'old finally does not delete new entry');
}

// Promise-identity helper still works
const inflight2 = new Map();
let resolveSlow;
const slow = new Promise((r) => {
  resolveSlow = r;
});
let pSlow;
pSlow = slow.finally(() => {
  deleteInflightIfSame(inflight2, '1:0', pSlow);
});
inflight2.set('1:0', pSlow);
const pFast = Promise.resolve('fast');
inflight2.set('1:0', pFast); // supersede
resolveSlow('slow');
await pSlow;
assert(inflight2.get('1:0') === pFast, 'identity guard keeps newer promise');
assert(deleteInflightIfSame(inflight2, '1:0', pFast) === true, 'same deletes');
assert(!inflight2.has('1:0'), 'removed');

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

// Production controller: A lento → B rápido (aborts pages GET of A)
const ab = await simulateSlowAThenFastBSameController();
assert(ab.bApplied === true, 'B applied');
assert(ab.aNotApplied === true, 'A not applied');
assert(ab.applied && ab.applied.chapterId === 2, 'final applied is B');

// Abort of in-flight pages fetch on second open
let aborted = false;
const ctrl = createReaderChapterController({
  fetchPages: async (id, { signal } = {}) => {
    await new Promise((resolve, reject) => {
      const t = setTimeout(resolve, id === 1 ? 80 : 5);
      if (signal) {
        signal.addEventListener('abort', () => {
          aborted = true;
          clearTimeout(t);
          const e = new Error('aborted');
          e.name = 'AbortError';
          reject(e);
        });
      }
    });
    return ['p'];
  },
});
const slowOpen = ctrl.openChapter(1);
await new Promise((r) => setTimeout(r, 5));
const fastOpen = ctrl.openChapter(2);
await Promise.all([slowOpen, fastOpen]);
assert(aborted === true, 'first pages GET aborted');

// Production index.html must use the shared module (single controller path).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const dir = path.dirname(fileURLToPath(import.meta.url));
const html = fs.readFileSync(path.join(dir, 'index.html'), 'utf8');
assert(html.includes('type="module"'), 'index is ES module');
assert(
  html.includes("from './reader_race_logic.mjs'") ||
    html.includes('from "./reader_race_logic.mjs"'),
  'index imports reader_race_logic.mjs',
);
assert(
  html.includes('createReaderChapterController'),
  'index uses shared createReaderChapterController',
);
// No parallel IIFE production race logic with its own readerGen counter.
assert(
  !html.includes('let readerGen = 0'),
  'must not reimplement readerGen counter in index',
);

console.log('reader race logic OK');
