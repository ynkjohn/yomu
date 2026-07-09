/**
 * Pure race-control helpers for the PWA reader (Phase 2D.1).
 * Used by node tests; mirrors index.html generation / inflight rules.
 */

export function nextGen(current) {
  return current + 1;
}

export function shouldApply(activeGen, responseGen) {
  return activeGen === responseGen;
}

export function createInflightMap() {
  return new Map();
}

/** Deduplicate concurrent loads for the same page index. */
export async function loadOnce(inflight, key, loader) {
  if (inflight.has(key)) return inflight.get(key);
  const p = Promise.resolve()
    .then(loader)
    .finally(() => inflight.delete(key));
  inflight.set(key, p);
  return p;
}

export function captureProgressPayload(chapterId, page, total, gen) {
  return { chapterId, page, total, gen, isRead: page >= total - 1 };
}

/**
 * Simulate rapid chapter switches: only last gen may apply pages.
 */
export async function simulateChapterRace(fetchPages) {
  let gen = 0;
  const applied = [];
  async function open(chapterId, delayMs) {
    gen = nextGen(gen);
    const my = gen;
    const pages = await fetchPages(chapterId, delayMs);
    if (!shouldApply(gen, my)) return { applied: false, gen: my };
    applied.push({ chapterId, pages, gen: my });
    return { applied: true, gen: my };
  }
  // open A (slow), open B (fast) — A must not apply
  const a = open(1, 50);
  const b = open(2, 5);
  const ra = await a;
  const rb = await b;
  return { ra, rb, applied, finalGen: gen };
}

export function simulateCloseDuringRequest() {
  let gen = 1;
  let blobs = ['blob:1', 'blob:2'];
  const revoked = [];
  function close() {
    gen = nextGen(gen);
    for (const b of blobs) revoked.push(b);
    blobs = [];
  }
  // late response
  const lateGen = 1;
  close();
  const acceptLate = shouldApply(gen, lateGen);
  return { acceptLate, revoked, gen };
}
