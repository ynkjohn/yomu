/**
 * Production race-control helpers for the PWA reader (Phase 2D.1 / 2D.2).
 * Used by tests and mirrored by index.html controller wiring.
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

/**
 * Deduplicate concurrent loads for the same gen+page.
 *
 * Returns **exactly** the Promise stored in the Map (not an async wrapper).
 * Removal checks Promise identity so a superseded entry is not deleted.
 * Callers that own a new entry should attach `_abort` on the returned Promise
 * *before* awaiting it; existing entries must keep the owner's AbortController.
 */
export function loadOnce(inflight, key, loader) {
  if (inflight.has(key)) return inflight.get(key);
  const p = Promise.resolve()
    .then(loader)
    .finally(() => {
      if (inflight.get(key) === p) inflight.delete(key);
    });
  inflight.set(key, p);
  return p;
}

/**
 * Attach abort only if this Promise does not already own one (first owner wins).
 */
export function attachAbortIfOwner(promise, abortFn) {
  if (!promise || typeof abortFn !== 'function') return promise;
  if (typeof promise._abort === 'function') return promise;
  promise._abort = abortFn;
  return promise;
}

/** Abort every in-flight promise that exposes `_abort` (close/revoke path). */
export function abortAllInflight(inflight) {
  for (const p of inflight.values()) {
    if (p && typeof p._abort === 'function') {
      try {
        p._abort();
      } catch (_) {}
    }
  }
}

/**
 * Remove inflight entry only if it is still the same Promise.
 */
export function deleteInflightIfSame(inflight, key, promise) {
  if (inflight.get(key) === promise) {
    inflight.delete(key);
    return true;
  }
  return false;
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
 * Controller for chapter open races: abort previous pages GET, bump gen.
 * Production index.html uses the same semantics.
 */
/**
 * Production chapter-open controller (also used by index.html).
 * Aborts previous GET /chapters/{id}/pages and tracks generation.
 *
 * fetchPages(chapterId, { signal, delayMs }) → pages payload (any shape).
 */
export function createReaderChapterController({ fetchPages }) {
  let gen = 0;
  let pagesAbort = null;
  let applied = null;

  async function openChapter(chapterId, { delayMs } = {}) {
    gen = nextGen(gen);
    const my = gen;
    if (pagesAbort && typeof pagesAbort.abort === 'function') {
      try {
        pagesAbort.abort();
      } catch (_) {}
    }
    const ac =
      typeof AbortController !== 'undefined' ? new AbortController() : null;
    pagesAbort = ac;

    try {
      const pages = await fetchPages(chapterId, {
        signal: ac ? ac.signal : undefined,
        delayMs,
      });
      if (!shouldApply(gen, my)) {
        return { applied: false, gen: my, reason: 'superseded' };
      }
      applied = { chapterId, pages, gen: my };
      return { applied: true, gen: my, pages };
    } catch (err) {
      if (err && (err.name === 'AbortError' || err.code === 'ABORT')) {
        return { applied: false, gen: my, reason: 'aborted' };
      }
      if (!shouldApply(gen, my)) {
        return { applied: false, gen: my, reason: 'superseded' };
      }
      throw err;
    }
  }

  function close() {
    gen = nextGen(gen);
    if (pagesAbort && typeof pagesAbort.abort === 'function') {
      try {
        pagesAbort.abort();
      } catch (_) {}
    }
    pagesAbort = null;
    applied = null;
  }

  return {
    openChapter,
    close,
    get gen() {
      return gen;
    },
    get applied() {
      return applied;
    },
  };
}

/**
 * Rapid A→B switch with page 0 in flight for both gens (same page index).
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

/**
 * A lento → B rápido on the same controller (production controller).
 */
export async function simulateSlowAThenFastBSameController() {
  const order = [];
  const ctrl = createReaderChapterController({
    fetchPages: async (chapterId, { signal, delayMs } = {}) => {
      order.push({ chapterId, start: Date.now() });
      await new Promise((resolve, reject) => {
        const t = setTimeout(resolve, delayMs ?? (chapterId === 1 ? 50 : 5));
        if (signal) {
          if (signal.aborted) {
            clearTimeout(t);
            const e = new Error('aborted');
            e.name = 'AbortError';
            reject(e);
            return;
          }
          signal.addEventListener('abort', () => {
            clearTimeout(t);
            const e = new Error('aborted');
            e.name = 'AbortError';
            reject(e);
          });
        }
      });
      return [`page0-ch${chapterId}`];
    },
  });

  const a = ctrl.openChapter(1, { delayMs: 50 });
  const b = ctrl.openChapter(2, { delayMs: 5 });
  const [ra, rb] = await Promise.all([a, b]);
  return {
    ra,
    rb,
    finalGen: ctrl.gen,
    applied: ctrl.applied,
    aNotApplied: ra.applied === false,
    bApplied: rb.applied === true,
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
