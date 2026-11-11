export function reportReceiptLatency(createdAtMs, receivedAtMs = Date.now()) {
  if (!Number.isFinite(createdAtMs) || !Number.isFinite(receivedAtMs)) return null;
  return Math.max(0, receivedAtMs - createdAtMs);
}

export function formatReceiptLatency(milliseconds) {
  if (!Number.isFinite(milliseconds)) return 'tiempo no disponible';
  if (milliseconds < 1000) return `${Math.round(milliseconds)} ms`;
  if (milliseconds < 60000) return `${(milliseconds / 1000).toFixed(1).replace('.', ',')} s`;
  return `${Math.floor(milliseconds / 60000)} min ${Math.round((milliseconds % 60000) / 1000)} s`;
}
