/**
 * Pure race-control helpers for the PWA reader (Phase 2D.1 / 2D.2).
 */

export function nextGen(current) {
  return current + 1;
}

export function shouldApply(activeGen, responseGen) {
  return activeGen === responseGen;
}

export function inflightKey(gen, pageIndex) {
  return `${gen}:${pageIndex}`;
}

export function createInflightMap() {
  return new Map();
}

/** Deduplicate concurrent loads for the same gen+page. */
export async function loadOnce(inflight, key, loader) {
  if (inflight.has(key)) return inflight.get(key);
  const p = Promise.resolve()
    .then(loader)
    .finally(() => inflight.delete(key));
  inflight.set(key, p);
  return p;
}

/**
 * Ensure a late response for gen A never mutates gen B's map.
 */
export function applyBlobIfCurrent(activeGen, responseGen, map, index, url, revoke) {
  if (activeGen !== responseGen) {
    revoke(url);
    return false;
  }
  map.set(index, url);
  return true;
}

export function captureProgressPayload(chapterId, page, total, gen) {
  return { chapterId, page, total, gen, isRead: page >= total - 1 };
}

/**
 * Rapid A→B switch with page 0 in flight for both gens.
 */
export async function simulateSamePageInflightAcrossGens() {
  let gen = 0;
  const map = new Map(); // gen -> Map page->blob
  const revoked = [];
  const inflight = new Map();

  async function open(chapterId) {
    gen = nextGen(gen);
    const my = gen;
    map.set(my, new Map());
    const key = inflightKey(my, 0);
    const blob = `blob:${chapterId}:0:${my}`;
    await loadOnce(inflight, key, async () => {
      await new Promise((r) => setTimeout(r, chapterId === 1 ? 40 : 5));
      applyBlobIfCurrent(
        gen,
        my,
        map.get(my),
        0,
        blob,
        (u) => revoked.push(u),
      );
      return blob;
    });
    return my;
  }

  const a = open(1);
  const b = open(2);
  await Promise.all([a, b]);

  // Only latest gen should hold page 0
  const latest = gen;
  const latestHas = map.get(latest)?.has(0) === true;
  let staleHas = false;
  for (const [g, m] of map) {
    if (g !== latest && m.has(0)) staleHas = true;
  }
  return {
    latest,
    latestHas,
    staleHas,
    revokedLate: revoked.some((u) => u.includes(':1:')),
  };
}

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
  const lateGen = 1;
  close();
  const acceptLate = shouldApply(gen, lateGen);
  return { acceptLate, revoked, gen };
}
