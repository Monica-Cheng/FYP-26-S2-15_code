// Renders arrays as readable comma-separated text instead of React's
// no-separator array rendering; never fabricates a value if missing.
export function formatEquipment(value) {
  if (Array.isArray(value)) return value.length > 0 ? value.join(', ') : '—';
  return value || '—';
}
