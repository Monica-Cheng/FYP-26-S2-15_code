export const FALLBACK_BADGE_STAT_TYPES = [
  'level',
  'totalXp',
  'sessionCount',
  'totalVolume',
  'totalDistance',
  'streak',
  'gymSessionCount',
  'cardioSessionCount',
  'combinedSessionCount',
];

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

export function formatConditionsSummary(conditions, maxItems = 2) {
  if (!Array.isArray(conditions) || conditions.length === 0) return '—';

  const items = conditions.map(formatConditionText);
  if (items.length <= maxItems) {
    return items.join(', ');
  }

  return `${items.slice(0, maxItems).join(', ')} +${items.length - maxItems} more`;
}

function normalizeSupportedStatTypes(supportedStatTypes) {
  return Array.isArray(supportedStatTypes) && supportedStatTypes.length > 0
    ? supportedStatTypes
    : FALLBACK_BADGE_STAT_TYPES;
}

// Every condition must have a non-empty statType and a valid non-negative
// numeric value (including legacy numeric-string values) before a badge can
// be saved.
export function validateConditions(conditions, supportedStatTypes) {
  if (!Array.isArray(conditions) || conditions.length === 0) {
    return 'At least one condition is required.';
  }
  const allowedStatTypes = normalizeSupportedStatTypes(supportedStatTypes);
  const seenStatTypes = new Set();
  for (const c of conditions) {
    if (!c.statType || !String(c.statType).trim()) {
      return 'Every condition must have a stat type.';
    }
    const statType = String(c.statType).trim();
    if (!allowedStatTypes.includes(statType)) {
      return `Unsupported stat type: ${statType}.`;
    }
    if (seenStatTypes.has(statType)) {
      return `The stat type "${statType}" can only be used once.`;
    }
    seenStatTypes.add(statType);
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

export function validateBadgeForm(form, supportedStatTypes) {
  const name = typeof form?.name === 'string' ? form.name.trim() : '';
  const description = typeof form?.description === 'string' ? form.description.trim() : '';
  const imageUrl = typeof form?.imageUrl === 'string' ? form.imageUrl.trim() : '';

  if (!name) {
    return 'Badge Name is required.';
  }
  if (name.length > 100) {
    return 'Badge Name cannot exceed 100 characters.';
  }
  if (!description) {
    return 'Description is required.';
  }
  if (description.length > 500) {
    return 'Description cannot exceed 500 characters.';
  }
  if (imageUrl && !isValidImageUrl(imageUrl)) {
    return 'Image URL must start with http:// or https://.';
  }

  return validateConditions(form?.conditions, supportedStatTypes);
}

export function getBadgeCallableErrorMessage(err, fallbackMessage) {
  const code = typeof err?.code === 'string' ? err.code : '';
  const rawMessage = typeof err?.message === 'string' ? err.message.trim() : '';
  const message = rawMessage.replace(/^.*?:\s*/, '');

  if (/already exists/i.test(message)) {
    return message;
  }
  if (/used more than once/i.test(message)) {
    return message;
  }
  if (/unsupported stat type/i.test(message)) {
    return message;
  }
  if (/cannot exceed/i.test(message)) {
    return message;
  }
  if (/required/i.test(message)) {
    return message;
  }
  if (/valid non-negative/i.test(message)) {
    return message;
  }
  if (/cannot be deleted/i.test(message)) {
    return message;
  }
  if (/confirmation is incorrect/i.test(message)) {
    return message;
  }
  if (/not found/i.test(message)) {
    return message;
  }

  return code ? `${fallbackMessage} (${code})` : fallbackMessage;
}
