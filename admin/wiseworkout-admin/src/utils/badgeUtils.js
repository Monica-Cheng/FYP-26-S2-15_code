export function isValidImageUrl(url) {
  if (!url || typeof url !== 'string') return false;
  return /^https?:\/\//i.test(url.trim());
}

// Older documents may have stored `value` as a numeric string (e.g. "50000")
// instead of a number — this coerces for display without mutating the source.
export function normalizeConditionValue(value) {
  const num = Number(value);
  return value !== '' && value !== null && value !== undefined && Number.isFinite(num) ? num : value;
}

export function formatConditionText(condition) {
  const statType = condition?.statType || 'Unknown stat';
  const value = normalizeConditionValue(condition?.value);
  return `${statType} ≥ ${value === undefined || value === null || value === '' ? '—' : value}`;
}

export function formatConditions(conditions) {
  if (!Array.isArray(conditions) || conditions.length === 0) return '—';
  return conditions.map(formatConditionText);
}

// Every condition must have a non-empty statType and a valid non-negative
// numeric value (including legacy numeric-string values) before a badge can
// be saved.
export function validateConditions(conditions) {
  if (!Array.isArray(conditions) || conditions.length === 0) {
    return 'At least one condition is required.';
  }
  for (const c of conditions) {
    if (!c.statType || !String(c.statType).trim()) {
      return 'Every condition must have a stat type.';
    }
    const num = Number(c.value);
    if (c.value === '' || c.value === null || c.value === undefined || !Number.isFinite(num) || num < 0) {
      return 'Every condition value must be a valid non-negative number.';
    }
  }
  return '';
}

// Normalizes every condition's value to a Firestore number on save — the
// schema example (`value: 50000`) stores it unquoted, and no Flutter badge
// evaluation code exists yet to confirm a different expectation.
export function normalizeConditionsForSave(conditions) {
  return conditions.map(c => ({
    statType: String(c.statType).trim(),
    value: Number(c.value),
  }));
}
