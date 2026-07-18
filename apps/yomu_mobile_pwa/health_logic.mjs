export function engineReadyFromHealth(health) {
  if (!health || typeof health !== 'object') return false;
  if (typeof health.engineReady === 'boolean') return health.engineReady;
  if (typeof health.suwayomiReady === 'boolean') return health.suwayomiReady;
  const legacy = health.suwayomi;
  return Boolean(
    legacy && (legacy.isReady === true || legacy.state === 'running'),
  );
}
