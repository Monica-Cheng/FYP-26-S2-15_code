export const CARDIO_ACTIVITIES = ['Run', 'Walk', 'Cycle'];
export const MUSCLE_OPTIONS = ['Chest', 'Back', 'Shoulders', 'Arms', 'Legs', 'Core', 'Glutes', 'Cardio'];
export const CANONICAL_PLAN_TYPES = ['Gym', 'Cardio', 'Combine'];
export const OFFICIAL_PLAN_WEEK_LENGTH = 7;

export function normalizeOfficialPlanType(value) {
  if (value === 'Running') return 'Cardio';
  return CANONICAL_PLAN_TYPES.includes(value) ? value : CANONICAL_PLAN_TYPES[0];
}

export function deriveOfficialMatchSport(type) {
  return normalizeOfficialPlanType(type);
}

export function getRequiredOfficialDayCount(durationWeeks) {
  const weeks = Number(durationWeeks);
  return Number.isInteger(weeks) && weeks > 0 ? weeks * OFFICIAL_PLAN_WEEK_LENGTH : OFFICIAL_PLAN_WEEK_LENGTH;
}

export function groupOfficialSessionsByWeek(sessions) {
  const list = Array.isArray(sessions) ? sessions : [];
  const groups = [];

  for (let start = 0; start < list.length; start += OFFICIAL_PLAN_WEEK_LENGTH) {
    groups.push({
      weekNumber: (start / OFFICIAL_PLAN_WEEK_LENGTH) + 1,
      items: list.slice(start, start + OFFICIAL_PLAN_WEEK_LENGTH).map((session, index) => ({
        session,
        dayIndex: start + index,
      })),
    });
  }

  return groups;
}

export function validateOfficialWeeklySchedule(sessions, daysPerWeek, durationWeeks) {
  const weeklyWorkouts = Number(daysPerWeek);
  const weeks = Number(durationWeeks);
  const requiredDays = getRequiredOfficialDayCount(weeks);
  const list = Array.isArray(sessions) ? sessions : [];

  if (list.length !== requiredDays) {
    return `This ${weeks}-week plan requires exactly ${requiredDays} days. Currently ${list.length}.`;
  }

  const weeklyGroups = groupOfficialSessionsByWeek(list);
  for (let index = 0; index < weeklyGroups.length; index += 1) {
    const workouts = weeklyGroups[index].items.filter(({ session }) => session?.isRestDay !== true).length;
    if (workouts !== weeklyWorkouts) {
      return `Week ${index + 1} must contain exactly ${weeklyWorkouts} workout day${weeklyWorkouts === 1 ? '' : 's'}. Currently ${workouts}.`;
    }
  }

  return null;
}

function toPositiveInteger(value) {
  const num = Number(value);
  return Number.isInteger(num) && num > 0 ? num : null;
}

function toNonNegativeInteger(value) {
  const num = Number(value);
  return Number.isInteger(num) && num >= 0 ? num : null;
}

export function calculateOfficialExerciseSeconds(exercise) {
  if (!exercise || typeof exercise !== 'object') return 0;

  if (exercise.isCardio === true) {
    const cardioMinutes = toPositiveInteger(exercise.cardioMinutes);
    return cardioMinutes ? cardioMinutes * 60 : 0;
  }

  const sets = toPositiveInteger(exercise.sets);
  const estTimePerSet = toPositiveInteger(exercise.estTimePerSet);
  const restTime = toNonNegativeInteger(exercise.restTime);

  if (!sets || !estTimePerSet || restTime === null) return 0;
  return sets * (estTimePerSet + restTime);
}

export function calculateOfficialSessionEstimatedMinutes(session) {
  if (!session || session.isRestDay === true) return 0;

  const exercises = Array.isArray(session.exercises) ? session.exercises : [];
  const totalSeconds = exercises.reduce((sum, exercise) => sum + calculateOfficialExerciseSeconds(exercise), 0);

  return totalSeconds > 0 ? Math.ceil(totalSeconds / 60) : 0;
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

export function getCallableErrorMessage(error, fallbackMessage) {
  const code = typeof error?.code === 'string' ? error.code : '';
  const message = typeof error?.message === 'string' ? error.message.trim() : '';

  const safeCodes = new Set([
    'functions/invalid-argument',
    'functions/failed-precondition',
    'functions/not-found',
    'functions/already-exists',
    'functions/permission-denied',
    'functions/unauthenticated',
    'invalid-argument',
    'failed-precondition',
    'not-found',
    'already-exists',
    'permission-denied',
    'unauthenticated',
  ]);

  if (message && safeCodes.has(code)) {
    return message.replace(/^Firebase:\s*/i, '');
  }

  return fallbackMessage;
}
