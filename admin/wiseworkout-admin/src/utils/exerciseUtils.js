// injuryRisk stores category NAMES as typed at selection time, which may drift
// in casing from historical data (e.g. "Lower back" vs. the injuryCategories
// doc's canonical "Lower Back"). Resolves to the canonical name for display
// via case-insensitive match, but falls back to the raw stored value instead
// of hiding it when no matching category exists (e.g. a deleted/renamed one).
export function resolveInjuryRiskLabel(rawName, categories) {
  const match = categories.find(c => (c.name || '').toLowerCase() === (rawName || '').toLowerCase());
  return match ? match.name : rawName;
}

export function formatInjuryRisk(injuryRisk, categories) {
  if (!Array.isArray(injuryRisk) || injuryRisk.length === 0) return '—';
  return injuryRisk.map(r => resolveInjuryRiskLabel(r, categories)).join(', ');
}

export function formatSecondaryMuscles(secondaryMuscles) {
  if (!Array.isArray(secondaryMuscles) || secondaryMuscles.length === 0) return '—';
  return secondaryMuscles.join(', ');
}

export function formatRepRange(minReps, maxReps) {
  if (minReps === undefined || minReps === null || maxReps === undefined || maxReps === null) return '—';
  return `${minReps} – ${maxReps} reps`;
}

export function formatWeightRange(minKg, maxKg) {
  if (minKg === undefined || minKg === null || maxKg === undefined || maxKg === null) return '—';
  return `${minKg} – ${maxKg} kg`;
}

const isPositiveInt = (v) => Number.isInteger(v) && v > 0;
const isNonNegNum = (v) => typeof v === 'number' && Number.isFinite(v) && v >= 0;

export function validateRepRange(minReps, maxReps) {
  if (!isPositiveInt(minReps)) return 'Minimum Reps must be a positive whole number.';
  if (!isPositiveInt(maxReps)) return 'Maximum Reps must be a positive whole number.';
  if (maxReps < minReps) return 'Maximum Reps must be greater than or equal to Minimum Reps.';
  return '';
}

export function validateWeightRange(minKg, maxKg) {
  if (!isNonNegNum(minKg)) return 'Minimum Weight must be a non-negative number.';
  if (!isNonNegNum(maxKg)) return 'Maximum Weight must be a non-negative number.';
  if (maxKg < minKg) return 'Maximum Weight must be greater than or equal to Minimum Weight.';
  return '';
}

// Trims, drops empties, and preserves the admin's displayed order.
export function cleanInstructionSteps(steps) {
  if (!Array.isArray(steps)) return [];
  return steps.map(s => (s || '').trim()).filter(Boolean);
}

export function validateInstructionSteps(steps) {
  return cleanInstructionSteps(steps).length === 0 ? 'At least one instruction step is required.' : '';
}

// Dedupes case-insensitively, trims, drops empties, and excludes the primary
// muscle if it was also added as a secondary muscle.
export function normalizeSecondaryMuscles(secondaryMuscles, primaryMuscle) {
  const primaryLower = (primaryMuscle || '').trim().toLowerCase();
  const seen = new Set();
  const result = [];
  (secondaryMuscles || []).forEach(raw => {
    const value = (raw || '').trim();
    if (!value) return;
    const lower = value.toLowerCase();
    if (lower === primaryLower || seen.has(lower)) return;
    seen.add(lower);
    result.push(value);
  });
  return result;
}

export function isValidGifUrl(url) {
  if (!url || typeof url !== 'string') return false;
  return /^https?:\/\//i.test(url.trim());
}
