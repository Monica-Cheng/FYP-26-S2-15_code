import { toDate } from './dateUtils';

export const METRIC_TYPES = ['distance', 'calories', 'duration'];

export function resolveCategoryDisplay(categoryId, categories) {
  if (!categoryId) return { text: '—', missing: false };
  const cat = categories.find(c => c.id === categoryId);
  return cat ? { text: cat.name || categoryId, missing: false } : { text: categoryId, missing: true };
}

export function formatGoal(challenge, categories) {
  if (challenge.goalValue === undefined || challenge.goalValue === null) return '—';
  const cat = categories.find(c => c.id === challenge.categoryId);
  const unit = challenge.unit || cat?.unit || '';
  return unit ? `${challenge.goalValue} ${unit}` : `${challenge.goalValue}`;
}

// Progress in the app is computed over [startDate, endDate) — a session
// exactly at endDate is excluded — so "Ended" starts at now >= endDate.
export function computeChallengeStatus(startDate, endDate) {
  const start = toDate(startDate);
  const end = toDate(endDate);
  if (!start || !end) return 'Unknown';
  const now = new Date();
  if (now < start) return 'Upcoming';
  if (now >= end) return 'Ended';
  return 'Active';
}

// Read-only preview of who "Invite All Users" would affect — computes counts
// only, performs no writes. A user is eligible when not suspended (reusing
// Users.js's exact accountStatus interpretation) and not already a
// participant or already invited.
export function computeInviteEligibility(challenge, users) {
  const participantUids = Array.isArray(challenge.participantUids) ? challenge.participantUids : [];
  const invitedUids = Array.isArray(challenge.invitedUids) ? challenge.invitedUids : [];
  const participantSet = new Set(participantUids);
  const invitedSet = new Set(invitedUids);

  let suspendedCount = 0;
  const eligibleUids = [];
  (users || []).forEach(u => {
    if (u.accountStatus === 'suspended') { suspendedCount++; return; }
    if (participantSet.has(u.id) || invitedSet.has(u.id)) return;
    eligibleUids.push(u.id);
  });

  return {
    eligibleUids,
    eligibleCount: eligibleUids.length,
    participatingCount: participantUids.length,
    invitedCount: invitedUids.length,
    suspendedCount,
  };
}

export function validateCategoryForm(form) {
  if (!form.name.trim()) return 'Category Name is required.';
  if (!form.unit.trim()) return 'Unit is required.';
  if (!METRIC_TYPES.includes(form.metricType)) return 'Metric Type must be distance, calories, or duration.';
  const min = Number(form.minGoal);
  if (form.minGoal === '' || !Number.isFinite(min) || min < 0) {
    return 'Minimum Goal must be a valid non-negative number.';
  }
  const max = Number(form.maxGoal);
  if (form.maxGoal === '' || !Number.isFinite(max)) return 'Maximum Goal must be a valid number.';
  if (max < min) return 'Maximum Goal must be greater than or equal to Minimum Goal.';
  return '';
}
