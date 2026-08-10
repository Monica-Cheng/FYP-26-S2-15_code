import React from 'react';
import { Clock3, Dumbbell, MoonStar, Plus, Trash2 } from 'lucide-react';
import Badge from './ui/Badge';
import { CARDIO_ACTIVITIES } from '../utils/planUtils';

const DAYS_IN_WEEK = 7;

const TAG_OPTIONS = ['Primary', 'Accessory'];
const SET_TYPE_OPTIONS = [
  { value: 'W', label: 'Warmup (W)' },
  { value: 'N', label: 'Normal (N)' },
  { value: 'D', label: 'Drop Set (D)' },
];

function getAllowedBlockKinds(planType) {
  if (planType === 'Gym') return { strength: true, cardio: false };
  if (planType === 'Cardio') return { strength: false, cardio: true };
  return { strength: true, cardio: true };
}

function findCatalogExercise(exerciseCatalog, name) {
  const normalizedName = (name || '').trim().toLowerCase();
  if (!normalizedName) return null;
  return exerciseCatalog.find((exercise) => (exercise?.name || '').trim().toLowerCase() === normalizedName) || null;
}

function hasCatalogMuscle(exercise) {
  return typeof exercise?.muscle === 'string' && exercise.muscle.trim() !== '';
}

function cardioEditorFromPlanExercise(exercise) {
  return {
    isCardio: true,
    cardioActivity: CARDIO_ACTIVITIES.includes(exercise?.cardioActivity) ? exercise.cardioActivity : CARDIO_ACTIVITIES[0],
    cardioMinutes:
      exercise?.cardioMinutes !== undefined && exercise?.cardioMinutes !== null
        ? String(exercise.cardioMinutes)
        : exercise?.sets?.[0]?.reps !== undefined
          ? String(exercise.sets[0].reps)
          : '15',
  };
}

export function emptyExercise() {
  return { name: '', muscle: '', tag: 'Primary', sets: '3', reps: '10', restTime: '60', note: '', isCardio: false };
}

export function emptyCardioBlock() {
  return { isCardio: true, cardioActivity: CARDIO_ACTIVITIES[0], cardioMinutes: '15' };
}

export function buildDefaultSessions(daysPerWeek) {
  const trainingCount = Math.min(Math.max(Number(daysPerWeek) || 3, 1), DAYS_IN_WEEK);
  return Array.from({ length: DAYS_IN_WEEK }, (_, index) => {
    const isTraining = index < trainingCount;
    return {
      name: isTraining ? '' : 'Rest',
      isRestDay: !isTraining,
      estimatedMinutes: isTraining ? '45' : '0',
      exercises: isTraining ? [emptyExercise()] : [],
    };
  });
}

export function sessionsFromPlan(rawSessions) {
  const list = Array.isArray(rawSessions) ? rawSessions : [];
  return list.map((session) => {
    const { name, isRestDay, estimatedMinutes, exercises, day, type, ...restSessionFields } = session || {};
    return {
      name: isRestDay ? name || 'Rest' : name || '',
      isRestDay: !!isRestDay,
      estimatedMinutes: estimatedMinutes !== undefined && estimatedMinutes !== null ? String(estimatedMinutes) : '0',
      exercises: Array.isArray(exercises)
        ? exercises.map((exercise) => {
            if (exercise && exercise.isCardio === true) {
              return cardioEditorFromPlanExercise(exercise);
            }

            const {
              name: exerciseName,
              muscle,
              tag,
              sets,
              reps,
              restTime,
              note,
              ...restExerciseFields
            } = exercise || {};

            return {
              isCardio: false,
              name: exerciseName || '',
              muscle: muscle || '',
              tag: tag === 'Accessory' ? 'Accessory' : 'Primary',
              sets:
                typeof sets === 'number'
                  ? String(sets)
                  : Array.isArray(sets)
                    ? String(sets.length)
                    : '3',
              reps: reps !== undefined && reps !== null ? String(reps) : '10',
              restTime: restTime !== undefined && restTime !== null ? String(restTime) : '60',
              note: note || '',
              _extra: restExerciseFields,
            };
          })
        : [],
      _extra: restSessionFields,
    };
  });
}

export function buildAndValidateSessions(sessions, expectedDaysPerWeek, planType, exerciseCatalog) {
  if (sessions.length !== DAYS_IN_WEEK) {
    return { error: `Exactly 7 sessions (one per day of the week) are required — currently ${sessions.length}.` };
  }
  if (!sessions.some((session) => !session.isRestDay)) {
    return { error: 'A plan cannot consist of 7 rest days — at least one training session is required.' };
  }

  const allowedKinds = getAllowedBlockKinds(planType);
  const built = [];
  for (let sessionIndex = 0; sessionIndex < sessions.length; sessionIndex += 1) {
    const session = sessions[sessionIndex];
    const dayLabel = `Day ${sessionIndex + 1}`;

    if (session.isRestDay) {
      built.push({
        ...session._extra,
        day: dayLabel,
        name: session.name.trim() || 'Rest',
        type: 'rest',
        isRestDay: true,
        estimatedMinutes: 0,
        exercises: [],
      });
      continue;
    }

    if (!session.name.trim()) return { error: `${dayLabel}: Session Name is required.` };
    if (!session.exercises || session.exercises.length === 0) {
      return { error: `${dayLabel}: at least one exercise is required for a training day.` };
    }

    const exercises = [];
    for (let exerciseIndex = 0; exerciseIndex < session.exercises.length; exerciseIndex += 1) {
      const exercise = session.exercises[exerciseIndex];

      if (exercise.isCardio) {
        if (!allowedKinds.cardio) {
          return { error: `${dayLabel}: ${planType} plans cannot contain cardio blocks. Remove the cardio block(s) before saving.` };
        }
        if (!CARDIO_ACTIVITIES.includes(exercise.cardioActivity)) {
          return { error: `${dayLabel}, cardio block ${exerciseIndex + 1}: Activity must be Run, Walk, or Cycle.` };
        }
        const minutes = Number(exercise.cardioMinutes);
        if (!Number.isInteger(minutes) || minutes <= 0) {
          return { error: `${dayLabel}, cardio block ${exerciseIndex + 1}: Minutes must be a positive integer.` };
        }
        exercises.push({
          name: `${exercise.cardioActivity} ${minutes}min`,
          muscle: 'Cardio',
          restTime: 0,
          isCardio: true,
          cardioActivity: exercise.cardioActivity,
          cardioMinutes: minutes,
        });
        continue;
      }

      if (!exercise.name.trim()) return { error: `${dayLabel}, exercise ${exerciseIndex + 1}: Name is required.` };
      if (!allowedKinds.strength) {
        return { error: `${dayLabel}: ${planType} plans cannot contain strength exercises. Remove the strength exercise(s) before saving.` };
      }
      const catalogExercise = findCatalogExercise(exerciseCatalog, exercise.name);
      if (!catalogExercise) {
        return { error: `${dayLabel}, exercise ${exerciseIndex + 1}: Select an exercise from the catalog before saving.` };
      }
      if (!hasCatalogMuscle(catalogExercise)) {
        return { error: `${dayLabel}, exercise ${exerciseIndex + 1}: The selected catalog exercise is missing a target muscle.` };
      }
      const sets = Number(exercise.sets);
      const reps = Number(exercise.reps);
      if (!Number.isInteger(sets) || sets <= 0) {
        return { error: `${dayLabel}, exercise ${exerciseIndex + 1}: Sets must be a positive integer.` };
      }
      if (!Number.isInteger(reps) || reps <= 0) {
        return { error: `${dayLabel}, exercise ${exerciseIndex + 1}: Reps must be a positive integer.` };
      }
      const restTime = Number(exercise.restTime);
      if (!Number.isInteger(restTime) || restTime < 0) {
        return { error: `${dayLabel}, exercise ${exerciseIndex + 1}: Rest Time must be a valid non-negative integer.` };
      }
      const builtExercise = {
        ...exercise._extra,
        name: catalogExercise.name,
        muscle: catalogExercise.muscle || '',
        tag: exercise.tag,
        sets,
        reps,
        restTime,
      };
      if (exercise.note && exercise.note.trim()) builtExercise.note = exercise.note.trim();
      exercises.push(builtExercise);
    }

    const estimatedMinutes = Number(session.estimatedMinutes);
    built.push({
      ...session._extra,
      day: dayLabel,
      name: session.name.trim(),
      type: 'gym',
      isRestDay: false,
      estimatedMinutes: Number.isInteger(estimatedMinutes) && estimatedMinutes >= 0 ? estimatedMinutes : 0,
      exercises,
    });
  }

  const actualDays = built.filter((session) => !session.isRestDay).length;
  const expected = Number(expectedDaysPerWeek);
  if (expected !== actualDays) {
    return {
      error:
        `Days per Week (${expectedDaysPerWeek}) does not match the number of non-rest sessions (${actualDays}). ` +
        'Update Days per Week or adjust which days are marked as rest.',
    };
  }

  return { sessions: built, error: null };
}

export function emptySet() {
  return { type: 'N', kg: '', reps: '' };
}

export function emptyCustomExercise() {
  return { name: '', muscle: '', tag: 'Primary', restTime: '90', note: '', sets: [emptySet()], _extra: {} };
}

export function buildDefaultCustomSessions(daysPerWeek) {
  const count = Math.min(Math.max(Number(daysPerWeek) || 3, 1), DAYS_IN_WEEK);
  return Array.from({ length: count }, () => ({
    name: '',
    isRestDay: false,
    type: 'gym',
    exercises: [emptyCustomExercise()],
    _extra: {},
  }));
}

export function customSessionsFromPlan(rawSessions) {
  const list = Array.isArray(rawSessions) ? rawSessions : [];
  return list.map((session) => {
    const { name, isRestDay, exercises, day, type, ...restSessionFields } = session;
    return {
      name: name || (isRestDay ? 'Rest' : ''),
      isRestDay: !!isRestDay,
      type: type || 'gym',
      exercises: Array.isArray(exercises)
        ? exercises.map((exercise) => {
            if (exercise && exercise.isCardio === true) {
              const { isCardio, cardioActivity, cardioMinutes, sets, ...restExerciseFields } = exercise || {};
              delete restExerciseFields.name;
              delete restExerciseFields.muscle;
              delete restExerciseFields.restTime;
              delete restExerciseFields.tag;
              delete restExerciseFields.note;
              return {
                ...cardioEditorFromPlanExercise({ isCardio, cardioActivity, cardioMinutes, sets }),
                _extra: restExerciseFields,
              };
            }

            const { name: exerciseName, muscle, tag, restTime, note, sets, ...restExerciseFields } = exercise;
            const setsArray =
              Array.isArray(sets) && sets.length > 0
                ? sets.map((setItem) => ({
                    type: (setItem && setItem.type) || 'N',
                    kg: setItem && setItem.kg !== undefined && setItem.kg !== null ? String(setItem.kg) : '',
                    reps: setItem && setItem.reps !== undefined && setItem.reps !== null ? String(setItem.reps) : '',
                  }))
                : [emptySet()];
            return {
              name: exerciseName || '',
              muscle: muscle || '',
              tag: tag === 'Accessory' ? 'Accessory' : 'Primary',
              restTime: restTime !== undefined && restTime !== null ? String(restTime) : '90',
              note: note || '',
              sets: setsArray,
              _extra: restExerciseFields,
            };
          })
        : [],
      _extra: restSessionFields,
    };
  });
}

export function buildAndValidateCustomSessions(sessions, planType, exerciseCatalog) {
  if (sessions.length === 0) {
    return { error: 'Add at least one training day.' };
  }
  if (!sessions.some((session) => !session.isRestDay)) {
    return { error: 'At least one non-rest training session is required.' };
  }

  const allowedKinds = getAllowedBlockKinds(planType);
  const built = [];
  for (let sessionIndex = 0; sessionIndex < sessions.length; sessionIndex += 1) {
    const session = sessions[sessionIndex];
    const dayLabel = `Day ${sessionIndex + 1}`;

    if (session.isRestDay) {
      built.push({
        day: dayLabel,
        name: session.name.trim() || 'Rest',
        type: 'rest',
        isRestDay: true,
        exercises: [],
        ...session._extra,
      });
      continue;
    }

    if (!session.name.trim()) return { error: `${dayLabel}: Session Name is required.` };
    if (!session.exercises || session.exercises.length === 0) {
      return { error: `${dayLabel}: at least one exercise is required for a training day.` };
    }

    const exercises = [];
    for (let exerciseIndex = 0; exerciseIndex < session.exercises.length; exerciseIndex += 1) {
      const exercise = session.exercises[exerciseIndex];
      if (exercise.isCardio) {
        if (!allowedKinds.cardio) {
          return { error: `${dayLabel}: ${planType} plans cannot contain cardio blocks. Remove the cardio block(s) before saving.` };
        }
        if (!CARDIO_ACTIVITIES.includes(exercise.cardioActivity)) {
          return { error: `${dayLabel}, cardio block ${exerciseIndex + 1}: Activity must be Run, Walk, or Cycle.` };
        }
        const minutes = Number(exercise.cardioMinutes);
        if (!Number.isInteger(minutes) || minutes <= 0) {
          return { error: `${dayLabel}, cardio block ${exerciseIndex + 1}: Minutes must be a positive integer.` };
        }
        exercises.push({
          ...exercise._extra,
          isCardio: true,
          cardioActivity: exercise.cardioActivity,
          cardioMinutes: minutes,
          name: `${exercise.cardioActivity} ${minutes}min`,
          muscle: 'Cardio',
          restTime: 0,
        });
        continue;
      }

      if (!exercise.name.trim()) return { error: `${dayLabel}, exercise ${exerciseIndex + 1}: Name is required.` };
      if (!allowedKinds.strength) {
        return { error: `${dayLabel}: ${planType} plans cannot contain strength exercises. Remove the strength exercise(s) before saving.` };
      }
      const catalogExercise = findCatalogExercise(exerciseCatalog, exercise.name);
      if (!catalogExercise) {
        return { error: `${dayLabel}, exercise ${exerciseIndex + 1}: Select an exercise from the catalog before saving.` };
      }
      if (!hasCatalogMuscle(catalogExercise)) {
        return { error: `${dayLabel}, exercise ${exerciseIndex + 1}: The selected catalog exercise is missing a target muscle.` };
      }
      if (!exercise.sets || exercise.sets.length === 0) {
        return { error: `${dayLabel}, exercise ${exerciseIndex + 1}: at least one set is required.` };
      }

      const sets = [];
      for (let setIndex = 0; setIndex < exercise.sets.length; setIndex += 1) {
        const setItem = exercise.sets[setIndex];
        if (!setItem.type) return { error: `${dayLabel}, exercise ${exerciseIndex + 1}, set ${setIndex + 1}: Type is required.` };
        if (setItem.reps !== '' && (!Number.isFinite(Number(setItem.reps)) || Number(setItem.reps) < 0)) {
          return { error: `${dayLabel}, exercise ${exerciseIndex + 1}, set ${setIndex + 1}: Reps must be a valid number.` };
        }
        if (setItem.kg !== '' && (!Number.isFinite(Number(setItem.kg)) || Number(setItem.kg) < 0)) {
          return { error: `${dayLabel}, exercise ${exerciseIndex + 1}, set ${setIndex + 1}: KG must be a valid non-negative number.` };
        }
        sets.push({ type: setItem.type, kg: setItem.kg, reps: setItem.reps });
      }

      const restTime = Number(exercise.restTime);
      exercises.push({
        name: catalogExercise.name,
        muscle: catalogExercise.muscle || '',
        tag: exercise.tag,
        restTime: Number.isInteger(restTime) && restTime >= 0 ? restTime : 90,
        note: exercise.note ? exercise.note.trim() : '',
        sets,
        ...exercise._extra,
      });
    }

    built.push({
      day: dayLabel,
      name: session.name.trim(),
      type: session.type || 'gym',
      isRestDay: false,
      exercises,
      ...session._extra,
    });
  }
  return { sessions: built, error: null };
}

function PlanSessionsEditorStyles() {
  return (
    <style>{`
      .wwpse {
        display: flex;
        flex-direction: column;
        gap: 16px;
      }
      .wwpse__day {
        border: 1px solid var(--ww-divider);
        border-radius: 14px;
        background: var(--ww-card);
        overflow: hidden;
      }
      .wwpse__day-header {
        display: flex;
        justify-content: space-between;
        gap: 14px;
        align-items: flex-start;
        padding: 16px;
        border-bottom: 1px solid var(--ww-divider);
        background: color-mix(in srgb, var(--ww-bg) 78%, white);
        flex-wrap: wrap;
      }
      .wwpse__day-main {
        min-width: 0;
        flex: 1;
      }
      .wwpse__day-title-row {
        display: flex;
        align-items: center;
        gap: 10px;
        margin-bottom: 10px;
        flex-wrap: wrap;
      }
      .wwpse__day-index {
        font-size: var(--ww-type-table-header-size);
        font-weight: var(--ww-type-table-header-weight);
        color: var(--ww-primary-dark);
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }
      .wwpse__day-header-controls {
        display: grid;
        grid-template-columns: minmax(180px, 280px) auto auto;
        gap: 10px;
        align-items: center;
      }
      .wwpse__minutes-field {
        min-width: 92px;
      }
      .wwpse__minutes-input {
        min-width: 92px;
        width: 100%;
        box-sizing: border-box;
      }
      .wwpse__day-toggle {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        font-size: var(--ww-type-secondary-size);
        color: var(--ww-text);
      }
      .wwpse__rest-state {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 16px;
        color: var(--ww-text-sec);
        font-size: var(--ww-type-body-size);
      }
      .wwpse__body {
        padding: 16px;
        display: flex;
        flex-direction: column;
        gap: 14px;
      }
      .wwpse__block {
        border: 1px solid var(--ww-divider);
        border-radius: 12px;
        background: var(--ww-card);
        padding: 14px;
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .wwpse__block-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: 10px;
        flex-wrap: wrap;
      }
      .wwpse__block-title {
        display: flex;
        align-items: center;
        gap: 8px;
        flex-wrap: wrap;
        font-size: var(--ww-type-card-title-size);
        font-weight: var(--ww-type-card-title-weight);
        color: var(--ww-primary-dark);
      }
      .wwpse__grid {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 12px;
      }
      .wwpse__grid-two {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 12px;
      }
      .wwpse__full {
        grid-column: 1 / -1;
      }
      .wwpse__preview {
        min-height: var(--ww-control-height);
        padding: 10px 12px;
        border-radius: var(--ww-radius-control);
        border: 1px solid var(--ww-divider);
        background: var(--ww-elevated);
        display: flex;
        align-items: center;
        color: var(--ww-text-sec);
        font-size: var(--ww-type-body-size);
      }
      .wwpse__inline-error {
        margin-top: 6px;
        font-size: var(--ww-type-secondary-size);
        color: var(--ww-danger, #b42318);
        line-height: 1.45;
      }
      .wwpse__sets {
        border-top: 1px solid var(--ww-divider);
        padding-top: 12px;
        display: flex;
        flex-direction: column;
        gap: 10px;
      }
      .wwpse__sets-title {
        font-size: var(--ww-type-table-header-size);
        font-weight: var(--ww-type-table-header-weight);
        color: var(--ww-text-sec);
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }
      .wwpse__set-row {
        display: grid;
        grid-template-columns: minmax(0, 1.2fr) minmax(0, 0.65fr) minmax(0, 0.65fr);
        gap: 10px;
        align-items: end;
        padding: 12px;
        border: 1px solid var(--ww-divider);
        border-radius: 10px;
        background: var(--ww-elevated);
      }
      .wwpse__set-row > div {
        min-width: 0;
      }
      .wwpse__set-row .wwa-input,
      .wwpse__set-row .wwa-select {
        width: 100%;
        min-width: 0;
        box-sizing: border-box;
      }
      .wwpse__set-action {
        grid-column: 1 / -1;
        display: flex;
        justify-content: flex-end;
        min-width: 0;
      }
      .wwpse__day-actions,
      .wwpse__block-actions,
      .wwpse__footer {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
      }
      .wwpse__footer {
        justify-content: flex-start;
      }
      @media (max-width: 980px) {
        .wwpse__grid,
        .wwpse__grid-two,
        .wwpse__day-header-controls,
        .wwpse__set-row {
          grid-template-columns: minmax(0, 1fr);
        }
      }
    `}</style>
  );
}

function PlanSessionsEditor({ sessions, onChange, exerciseCatalog, mode = 'official', planType = '' }) {
  const isCustomMode = mode === 'custom';
  const makeEmptyExercise = () => (isCustomMode ? emptyCustomExercise() : emptyExercise());
  const allowedKinds = getAllowedBlockKinds(planType);
  const makeDefaultTrainingExercises = () => (allowedKinds.cardio && !allowedKinds.strength ? [emptyCardioBlock()] : [makeEmptyExercise()]);

  const updateSession = (index, changes) => {
    onChange(sessions.map((session, sessionIndex) => (sessionIndex === index ? { ...session, ...changes } : session)));
  };

  const toggleRestDay = (index) => {
    const session = sessions[index];
    const nowRest = !session.isRestDay;
    if (nowRest) {
      updateSession(
        index,
        isCustomMode
          ? { isRestDay: true, name: session.name || 'Rest', exercises: [] }
          : { isRestDay: true, name: session.name || 'Rest', estimatedMinutes: '0', exercises: [] }
      );
    } else {
      updateSession(
        index,
        isCustomMode
          ? { isRestDay: false, name: session.name === 'Rest' ? '' : session.name, exercises: makeDefaultTrainingExercises() }
          : { isRestDay: false, name: session.name === 'Rest' ? '' : session.name, estimatedMinutes: '45', exercises: makeDefaultTrainingExercises() }
      );
    }
  };

  const addDay = () => {
    const newDay = isCustomMode
      ? { name: '', isRestDay: false, type: 'gym', exercises: makeDefaultTrainingExercises(), _extra: {} }
      : { name: '', isRestDay: false, estimatedMinutes: '45', exercises: makeDefaultTrainingExercises() };
    onChange([...sessions, newDay]);
  };

  const removeDay = (index) => {
    onChange(sessions.filter((_, sessionIndex) => sessionIndex !== index));
  };

  const updateExercise = (dayIndex, exerciseIndex, changes) => {
    const session = sessions[dayIndex];
    const exercises = session.exercises.map((exercise, index) => (index === exerciseIndex ? { ...exercise, ...changes } : exercise));
    updateSession(dayIndex, { exercises });
  };

  const addExercise = (dayIndex) => {
    const session = sessions[dayIndex];
    updateSession(dayIndex, { exercises: [...session.exercises, makeEmptyExercise()] });
  };

  const addCardioBlock = (dayIndex) => {
    const session = sessions[dayIndex];
    updateSession(dayIndex, { exercises: [...session.exercises, emptyCardioBlock()] });
  };

  const removeExercise = (dayIndex, exerciseIndex) => {
    const session = sessions[dayIndex];
    updateSession(dayIndex, { exercises: session.exercises.filter((_, index) => index !== exerciseIndex) });
  };

  const handleExerciseNameChange = (dayIndex, exerciseIndex, name) => {
    const match = findCatalogExercise(exerciseCatalog, name);
    updateExercise(dayIndex, exerciseIndex, match ? { name: match.name, muscle: match.muscle || '' } : { name, muscle: '' });
  };

  const updateSet = (dayIndex, exerciseIndex, setIndex, changes) => {
    const session = sessions[dayIndex];
    const exercise = session.exercises[exerciseIndex];
    const setsArray = exercise.sets.map((setItem, index) => (index === setIndex ? { ...setItem, ...changes } : setItem));
    updateExercise(dayIndex, exerciseIndex, { sets: setsArray });
  };

  const addSet = (dayIndex, exerciseIndex) => {
    const session = sessions[dayIndex];
    const exercise = session.exercises[exerciseIndex];
    updateExercise(dayIndex, exerciseIndex, { sets: [...exercise.sets, emptySet()] });
  };

  const removeSet = (dayIndex, exerciseIndex, setIndex) => {
    const session = sessions[dayIndex];
    const exercise = session.exercises[exerciseIndex];
    updateExercise(dayIndex, exerciseIndex, { sets: exercise.sets.filter((_, index) => index !== setIndex) });
  };

  return (
    <div className="wwpse">
      <PlanSessionsEditorStyles />

      {sessions.map((session, dayIndex) => (
        <div key={dayIndex} className="wwpse__day">
          <div className="wwpse__day-header">
            <div className="wwpse__day-main">
              <div className="wwpse__day-title-row">
                <span className="wwpse__day-index">Day {dayIndex + 1}</span>
                {session.isRestDay ? <Badge tone="neutral">Rest Day</Badge> : null}
                {!isCustomMode && !session.isRestDay && session.estimatedMinutes ? <Badge tone="neutral">{session.estimatedMinutes} min</Badge> : null}
              </div>
              <div className="wwpse__day-header-controls">
                <input
                  className="wwa-input"
                  value={session.name}
                  onChange={(event) => updateSession(dayIndex, { name: event.target.value })}
                  placeholder={session.isRestDay ? 'Rest' : 'Session name, e.g. Upper A'}
                  disabled={session.isRestDay}
                />
                <label className="wwpse__day-toggle">
                  <input type="checkbox" checked={session.isRestDay} onChange={() => toggleRestDay(dayIndex)} />
                  <span>Rest Day</span>
                </label>
                {!isCustomMode && !session.isRestDay ? (
                  <div className="wwpse__minutes-field">
                    <label className="wwa-field-label" htmlFor={`session-minutes-${dayIndex}`}>Estimated Minutes</label>
                    <input
                      id={`session-minutes-${dayIndex}`}
                      type="number"
                      min="0"
                      className="wwa-input wwpse__minutes-input"
                      value={session.estimatedMinutes}
                      onChange={(event) => updateSession(dayIndex, { estimatedMinutes: event.target.value })}
                    />
                  </div>
                ) : null}
              </div>
            </div>

            <div className="wwpse__day-actions">
              <button type="button" className="wwa-btn wwa-btn-sm wwa-btn-danger" onClick={() => removeDay(dayIndex)}>
                <Trash2 aria-hidden="true" size={14} strokeWidth={2} />
                Remove Day
              </button>
            </div>
          </div>

          {session.isRestDay ? (
            <div className="wwpse__rest-state">
              <MoonStar aria-hidden="true" size={16} strokeWidth={2} />
              <span>Rest day enabled for this training slot.</span>
            </div>
          ) : (
            <div className="wwpse__body">
              {session.exercises.map((exercise, exerciseIndex) => (
                <div key={exerciseIndex} className="wwpse__block">
                  {exercise.isCardio ? (
                    <>
                      <div className="wwpse__block-header">
                        <div className="wwpse__block-title">
                          <Clock3 aria-hidden="true" size={16} strokeWidth={2} />
                          <span>Cardio Block {exerciseIndex + 1}</span>
                        </div>
                        <button
                          type="button"
                          className="wwa-btn wwa-btn-sm wwa-btn-danger"
                          onClick={() => removeExercise(dayIndex, exerciseIndex)}
                        >
                          <Trash2 aria-hidden="true" size={14} strokeWidth={2} />
                          Remove Cardio Block
                        </button>
                      </div>
                      <div className="wwpse__grid-two">
                        <div>
                          <label className="wwa-field-label" htmlFor={`cardio-activity-${dayIndex}-${exerciseIndex}`}>Cardio Activity</label>
                          <select
                            id={`cardio-activity-${dayIndex}-${exerciseIndex}`}
                            className="wwa-select"
                            value={exercise.cardioActivity}
                            onChange={(event) => updateExercise(dayIndex, exerciseIndex, { cardioActivity: event.target.value })}
                          >
                            {CARDIO_ACTIVITIES.map((activity) => (
                              <option key={activity} value={activity}>
                                {activity}
                              </option>
                            ))}
                          </select>
                        </div>
                        <div>
                          <label className="wwa-field-label" htmlFor={`cardio-minutes-${dayIndex}-${exerciseIndex}`}>Minutes</label>
                          <input
                            id={`cardio-minutes-${dayIndex}-${exerciseIndex}`}
                            type="number"
                            min="1"
                            className="wwa-input"
                            value={exercise.cardioMinutes}
                            onChange={(event) => updateExercise(dayIndex, exerciseIndex, { cardioMinutes: event.target.value })}
                          />
                        </div>
                        <div className="wwpse__full">
                          <label className="wwa-field-label">Preview</label>
                          <div className="wwpse__preview">
                            {exercise.cardioActivity} {exercise.cardioMinutes || 0}min
                          </div>
                        </div>
                      </div>
                    </>
                  ) : (
                    <>
                      <div className="wwpse__block-header">
                        <div className="wwpse__block-title">
                          <Dumbbell aria-hidden="true" size={16} strokeWidth={2} />
                          <span>Exercise {exerciseIndex + 1}</span>
                        </div>
                        <button
                          type="button"
                          className="wwa-btn wwa-btn-sm wwa-btn-danger"
                          onClick={() => removeExercise(dayIndex, exerciseIndex)}
                        >
                          <Trash2 aria-hidden="true" size={14} strokeWidth={2} />
                          Remove Exercise
                        </button>
                      </div>

                      <div className="wwpse__grid">
                        <div>
                          <label className="wwa-field-label" htmlFor={`exercise-name-${dayIndex}-${exerciseIndex}`}>Exercise Name</label>
                          <input
                            id={`exercise-name-${dayIndex}-${exerciseIndex}`}
                            className="wwa-input"
                            list="wwa-exercise-catalog"
                            value={exercise.name}
                            onChange={(event) => handleExerciseNameChange(dayIndex, exerciseIndex, event.target.value)}
                            placeholder="e.g. Bench Press"
                          />
                          {exercise.name.trim() && !findCatalogExercise(exerciseCatalog, exercise.name) ? (
                            <div className="wwpse__inline-error">Select an exercise from the exercise catalog.</div>
                          ) : null}
                        </div>
                        <div>
                          <label className="wwa-field-label" htmlFor={`exercise-tag-${dayIndex}-${exerciseIndex}`}>Tag</label>
                          <select
                            id={`exercise-tag-${dayIndex}-${exerciseIndex}`}
                            className="wwa-select"
                            value={exercise.tag}
                            onChange={(event) => updateExercise(dayIndex, exerciseIndex, { tag: event.target.value })}
                          >
                            {TAG_OPTIONS.map((tag) => (
                              <option key={tag} value={tag}>
                                {tag}
                              </option>
                            ))}
                          </select>
                        </div>

                        {!isCustomMode ? (
                          <>
                            <div>
                              <label className="wwa-field-label" htmlFor={`exercise-sets-${dayIndex}-${exerciseIndex}`}>Sets</label>
                              <input
                                id={`exercise-sets-${dayIndex}-${exerciseIndex}`}
                                type="number"
                                min="1"
                                className="wwa-input"
                                value={exercise.sets}
                                onChange={(event) => updateExercise(dayIndex, exerciseIndex, { sets: event.target.value })}
                              />
                            </div>
                            <div>
                              <label className="wwa-field-label" htmlFor={`exercise-reps-${dayIndex}-${exerciseIndex}`}>Reps</label>
                              <input
                                id={`exercise-reps-${dayIndex}-${exerciseIndex}`}
                                type="number"
                                min="1"
                                className="wwa-input"
                                value={exercise.reps}
                                onChange={(event) => updateExercise(dayIndex, exerciseIndex, { reps: event.target.value })}
                              />
                            </div>
                          </>
                        ) : null}

                        <div>
                          <label className="wwa-field-label" htmlFor={`exercise-rest-${dayIndex}-${exerciseIndex}`}>Rest (sec)</label>
                          <input
                            id={`exercise-rest-${dayIndex}-${exerciseIndex}`}
                            type="number"
                            min="0"
                            className="wwa-input"
                            value={exercise.restTime}
                            onChange={(event) => updateExercise(dayIndex, exerciseIndex, { restTime: event.target.value })}
                          />
                        </div>

                        <div className="wwpse__full">
                          <label className="wwa-field-label" htmlFor={`exercise-note-${dayIndex}-${exerciseIndex}`}>Note (optional)</label>
                          <input
                            id={`exercise-note-${dayIndex}-${exerciseIndex}`}
                            className="wwa-input"
                            value={exercise.note}
                            onChange={(event) => updateExercise(dayIndex, exerciseIndex, { note: event.target.value })}
                            placeholder="e.g. Keep elbows tucked"
                          />
                        </div>
                      </div>

                      {isCustomMode ? (
                        <div className="wwpse__sets">
                          <div className="wwpse__sets-title">Sets</div>
                          {exercise.sets.map((setItem, setIndex) => (
                            <div key={setIndex} className="wwpse__set-row">
                              <div>
                                <label className="wwa-field-label" htmlFor={`set-type-${dayIndex}-${exerciseIndex}-${setIndex}`}>Set Type</label>
                                <select
                                  id={`set-type-${dayIndex}-${exerciseIndex}-${setIndex}`}
                                  className="wwa-select"
                                  value={setItem.type}
                                  onChange={(event) => updateSet(dayIndex, exerciseIndex, setIndex, { type: event.target.value })}
                                >
                                  {SET_TYPE_OPTIONS.map((option) => (
                                    <option key={option.value} value={option.value}>
                                      {option.label}
                                    </option>
                                  ))}
                                </select>
                              </div>
                              <div>
                                <label className="wwa-field-label" htmlFor={`set-kg-${dayIndex}-${exerciseIndex}-${setIndex}`}>KG</label>
                                <input
                                  id={`set-kg-${dayIndex}-${exerciseIndex}-${setIndex}`}
                                  className="wwa-input"
                                  value={setItem.kg}
                                  onChange={(event) => updateSet(dayIndex, exerciseIndex, setIndex, { kg: event.target.value })}
                                  placeholder="KG"
                                />
                              </div>
                              <div>
                                <label className="wwa-field-label" htmlFor={`set-reps-${dayIndex}-${exerciseIndex}-${setIndex}`}>Reps</label>
                                <input
                                  id={`set-reps-${dayIndex}-${exerciseIndex}-${setIndex}`}
                                  className="wwa-input"
                                  value={setItem.reps}
                                  onChange={(event) => updateSet(dayIndex, exerciseIndex, setIndex, { reps: event.target.value })}
                                  placeholder="Reps"
                                />
                              </div>
                              <div className="wwpse__set-action">
                                <button
                                  type="button"
                                  className="wwa-btn wwa-btn-sm wwa-btn-danger"
                                  onClick={() => removeSet(dayIndex, exerciseIndex, setIndex)}
                                  disabled={exercise.sets.length === 1}
                                >
                                  <Trash2 aria-hidden="true" size={14} strokeWidth={2} />
                                  Remove Set
                                </button>
                              </div>
                            </div>
                          ))}
                          <div className="wwpse__block-actions">
                            <button type="button" className="wwa-btn wwa-btn-sm wwa-btn-secondary" onClick={() => addSet(dayIndex, exerciseIndex)}>
                              <Plus aria-hidden="true" size={14} strokeWidth={2} />
                              Add Set
                            </button>
                          </div>
                        </div>
                      ) : null}
                    </>
                  )}
                </div>
              ))}

              <div className="wwpse__block-actions">
                {allowedKinds.strength ? (
                  <button type="button" className="wwa-btn wwa-btn-sm wwa-btn-brand-soft" onClick={() => addExercise(dayIndex)}>
                    <Plus aria-hidden="true" size={14} strokeWidth={2} />
                    Add Exercise
                  </button>
                ) : null}
                {allowedKinds.cardio ? (
                  <button type="button" className="wwa-btn wwa-btn-sm wwa-btn-secondary" onClick={() => addCardioBlock(dayIndex)}>
                    <Plus aria-hidden="true" size={14} strokeWidth={2} />
                    Add Cardio Block
                  </button>
                ) : null}
              </div>
            </div>
          )}
        </div>
      ))}

      <datalist id="wwa-exercise-catalog">
        {exerciseCatalog.map((exercise) => (
          <option key={exercise.name} value={exercise.name} />
        ))}
      </datalist>

      <div className="wwpse__footer">
        <button type="button" className="wwa-btn wwa-btn-sm wwa-btn-secondary" onClick={addDay}>
          <Plus aria-hidden="true" size={14} strokeWidth={2} />
          Add Day
        </button>
      </div>
    </div>
  );
}

export default PlanSessionsEditor;
