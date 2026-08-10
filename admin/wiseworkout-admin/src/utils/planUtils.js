export const CARDIO_ACTIVITIES = ['Run', 'Walk', 'Cycle'];
export const MUSCLE_OPTIONS = ['Chest', 'Back', 'Shoulders', 'Arms', 'Legs', 'Core', 'Glutes', 'Cardio'];
export const CANONICAL_PLAN_TYPES = ['Gym', 'Cardio', 'Combine'];

export function normalizeOfficialPlanType(value) {
  if (value === 'Running') return 'Cardio';
  return CANONICAL_PLAN_TYPES.includes(value) ? value : CANONICAL_PLAN_TYPES[0];
}

export function deriveOfficialMatchSport(type) {
  return normalizeOfficialPlanType(type);
}

export function parseCommaList(value) {
  return (value || '').split(',').map(s => s.trim()).filter(Boolean);
}

export function formatCommaList(list) {
  return Array.isArray(list) && list.length > 0 ? list.join(', ') : '';
}

// Returns undefined (omit the field) when every field is blank — matches the
// official-plan schema's "designedBy: map, optional" with no empty-map form.
export function buildDesignedBy({ name, title, credential, quote }) {
  const trimmed = {
    name: (name || '').trim(),
    title: (title || '').trim(),
    credential: (credential || '').trim(),
    quote: (quote || '').trim(),
  };
  return Object.values(trimmed).some(Boolean) ? trimmed : undefined;
}
