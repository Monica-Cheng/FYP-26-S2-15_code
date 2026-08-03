import React from 'react';
import { CARDIO_ACTIVITIES, MUSCLE_OPTIONS } from '../utils/planUtils';

// Every existing official plan stores exactly 7 embedded sessions — one full
// calendar week — because plan_schedule_screen.dart groups sessions into
// week-pages of 7 (`_totalWeeks = (sessions.length / 7).ceil()`). New plans
// default to that same 7-day shape; admins can still add/remove days.
const DAYS_IN_WEEK = 7;

const TAG_OPTIONS = ['Primary', 'Accessory'];
const SET_TYPE_OPTIONS = [
  { value: 'W', label: 'Warmup (W)' },
  { value: 'N', label: 'Normal (N)' },
  { value: 'D', label: 'Drop Set (D)' },
];

// ---------------------------------------------------------------------------
// OFFICIAL mode — sets is a plain integer count, reps lives on the exercise.
// Session-level `type` is always "gym" (training) or "rest" — never "cardio".
// Cardio content lives inside a session's exercises as dedicated cardio-block
// entries (isCardio: true), not as a session-level type.
// ---------------------------------------------------------------------------

export function emptyExercise() {
  return { name: '', muscle: '', tag: 'Primary', sets: '3', reps: '10', restTime: '60', note: '', isCardio: false };
}

export function emptyCardioBlock() {
  return { isCardio: true, cardioActivity: CARDIO_ACTIVITIES[0], cardioMinutes: '15' };
}

// Seeds `daysPerWeek` training days (capped to a week) followed by rest days —
// matches the pattern most existing official plans already follow, while
// staying editable since real data doesn't enforce this split strictly.
export function buildDefaultSessions(daysPerWeek) {
  const trainingCount = Math.min(Math.max(Number(daysPerWeek) || 3, 1), DAYS_IN_WEEK);
  return Array.from({ length: DAYS_IN_WEEK }, (_, i) => {
    const isTraining = i < trainingCount;
    return {
      name: isTraining ? '' : 'Rest',
      isRestDay: !isTraining,
      estimatedMinutes: isTraining ? '45' : '0',
      exercises: isTraining ? [emptyExercise()] : [],
    };
  });
}

// Converts a real Firestore plan's sessions[] into the editor's controlled-
// input shape (string-typed numeric fields). Defensive about `sets` possibly
// being an array (custom-plan shape) even though official plans should only
// ever store it as a plain count — falls back to the array's length either way.
// An exercise only becomes a cardio-block editor row when it has the real
// `isCardio: true` flag — anything merely cardio-shaped (e.g. muscle:
// "Cardio" without the flag) loads as a normal gym exercise, unchanged,
// rather than being silently reinterpreted.
export function sessionsFromPlan(rawSessions) {
  const list = Array.isArray(rawSessions) ? rawSessions : [];
  return list.map(s => ({
    name: s.isRestDay ? (s.name || 'Rest') : (s.name || ''),
    isRestDay: !!s.isRestDay,
    estimatedMinutes: s.estimatedMinutes !== undefined && s.estimatedMinutes !== null
      ? String(s.estimatedMinutes) : '0',
    exercises: Array.isArray(s.exercises) ? s.exercises.map(ex => {
      if (ex && ex.isCardio === true) {
        return {
          isCardio: true,
          cardioActivity: CARDIO_ACTIVITIES.includes(ex.cardioActivity) ? ex.cardioActivity : CARDIO_ACTIVITIES[0],
          cardioMinutes: ex.cardioMinutes !== undefined && ex.cardioMinutes !== null
            ? String(ex.cardioMinutes)
            : (ex.sets?.[0]?.reps !== undefined ? String(ex.sets[0].reps) : '15'),
        };
      }
      return {
        isCardio: false,
        name: ex.name || '',
        muscle: ex.muscle || '',
        tag: ex.tag === 'Accessory' ? 'Accessory' : 'Primary',
        sets: typeof ex.sets === 'number'
          ? String(ex.sets)
          : (Array.isArray(ex.sets) ? String(ex.sets.length) : '3'),
        reps: ex.reps !== undefined && ex.reps !== null ? String(ex.reps) : '10',
        restTime: ex.restTime !== undefined && ex.restTime !== null ? String(ex.restTime) : '60',
        note: ex.note || '',
      };
    }) : [],
  }));
}

// Shared by Add Plan and Edit Official Plan so both write the exact same
// official-plan shape. Every existing official plan has exactly 7 sessions
// (plan_schedule_screen.dart pages sessions in blocks of 7), so that's
// enforced here rather than left as a soft convention. expectedDaysPerWeek
// (the admin's Days per Week field) must equal the number of non-rest
// sessions actually built — mismatches block saving rather than silently
// persisting inconsistent data.
export function buildAndValidateSessions(sessions, expectedDaysPerWeek) {
  if (sessions.length !== DAYS_IN_WEEK) {
    return { error: `Exactly 7 sessions (one per day of the week) are required — currently ${sessions.length}.` };
  }
  if (!sessions.some(s => !s.isRestDay)) {
    return { error: 'A plan cannot consist of 7 rest days — at least one training session is required.' };
  }

  const built = [];
  for (let i = 0; i < sessions.length; i++) {
    const s = sessions[i];
    const dayLabel = `Day ${i + 1}`;

    if (s.isRestDay) {
      built.push({
        day: dayLabel,
        name: s.name.trim() || 'Rest',
        type: 'rest',
        isRestDay: true,
        estimatedMinutes: 0,
        exercises: [],
      });
      continue;
    }

    if (!s.name.trim()) return { error: `${dayLabel}: Session Name is required.` };
    if (!s.exercises || s.exercises.length === 0) {
      return { error: `${dayLabel}: at least one exercise is required for a training day.` };
    }

    const exercises = [];
    for (let j = 0; j < s.exercises.length; j++) {
      const ex = s.exercises[j];

      if (ex.isCardio) {
        if (!CARDIO_ACTIVITIES.includes(ex.cardioActivity)) {
          return { error: `${dayLabel}, cardio block ${j + 1}: Activity must be Run, Walk, or Cycle.` };
        }
        const minutes = Number(ex.cardioMinutes);
        if (!Number.isInteger(minutes) || minutes <= 0) {
          return { error: `${dayLabel}, cardio block ${j + 1}: Minutes must be a positive integer.` };
        }
        exercises.push({
          name: `${ex.cardioActivity} ${minutes}min`,
          muscle: 'Cardio',
          restTime: 0,
          note: '',
          tag: 'Primary',
          sets: [{ type: 'N', kg: '', reps: String(minutes) }],
          isCardio: true,
          cardioActivity: ex.cardioActivity,
          cardioMinutes: minutes,
        });
        continue;
      }

      if (!ex.name.trim()) return { error: `${dayLabel}, exercise ${j + 1}: Name is required.` };
      if (!ex.muscle.trim()) return { error: `${dayLabel}, exercise ${j + 1}: Muscle is required.` };
      const sets = Number(ex.sets);
      const reps = Number(ex.reps);
      if (!Number.isInteger(sets) || sets <= 0) {
        return { error: `${dayLabel}, exercise ${j + 1}: Sets must be a positive integer.` };
      }
      if (!Number.isInteger(reps) || reps <= 0) {
        return { error: `${dayLabel}, exercise ${j + 1}: Reps must be a positive integer.` };
      }
      const restTime = Number(ex.restTime);
      if (!Number.isInteger(restTime) || restTime < 0) {
        return { error: `${dayLabel}, exercise ${j + 1}: Rest Time must be a valid non-negative integer.` };
      }
      const exercise = { name: ex.name.trim(), muscle: ex.muscle.trim(), tag: ex.tag, sets, reps, restTime };
      if (ex.note && ex.note.trim()) exercise.note = ex.note.trim();
      exercises.push(exercise);
    }

    const estMinutes = Number(s.estimatedMinutes);
    built.push({
      day: dayLabel,
      name: s.name.trim(),
      type: 'gym',
      isRestDay: false,
      estimatedMinutes: Number.isInteger(estMinutes) && estMinutes >= 0 ? estMinutes : 0,
      exercises,
    });
  }

  const actualDays = built.filter(s => !s.isRestDay).length;
  const expected = Number(expectedDaysPerWeek);
  if (expected !== actualDays) {
    return {
      error: `Days per Week (${expectedDaysPerWeek}) does not match the number of non-rest sessions (${actualDays}). `
        + 'Update Days per Week or adjust which days are marked as rest.',
    };
  }

  return { sessions: built, error: null };
}

// ---------------------------------------------------------------------------
// CUSTOM mode — sets is an array of {type: W/N/D, kg, reps} (per-set logging),
// matching saveCustomRoutine/build_routine_screen.dart exactly. No estimatedMinutes
// (custom plans never store it) and no fixed 7-day requirement (real custom
// plans vary in length — the sample "Jason babo" plan has only 2 days). No
// dedicated cardio-block UI here — any isCardio/cardioActivity/cardioMinutes
// fields already on a custom exercise are preserved untouched via `_extra`.
// ---------------------------------------------------------------------------

export function emptySet() {
  return { type: 'N', kg: '', reps: '' };
}

export function emptyCustomExercise() {
  return { name: '', muscle: '', tag: 'Primary', restTime: '90', note: '', sets: [emptySet()], _extra: {} };
}

export function buildDefaultCustomSessions(daysPerWeek) {
  const count = Math.min(Math.max(Number(daysPerWeek) || 3, 1), DAYS_IN_WEEK);
  return Array.from({ length: count }, () => ({
    name: '', isRestDay: false, type: 'gym', exercises: [emptyCustomExercise()], _extra: {},
  }));
}

// Preserves any exercise/session fields this editor doesn't manage (isCardio,
// cardioActivity, cardioMinutes, id, showNote, etc. — all real fields written
// by build_routine_screen.dart) in `_extra` so they survive a save untouched.
export function customSessionsFromPlan(rawSessions) {
  const list = Array.isArray(rawSessions) ? rawSessions : [];
  return list.map(s => {
    const { name, isRestDay, exercises, day, type, ...restSessionFields } = s;
    return {
      name: name || (isRestDay ? 'Rest' : ''),
      isRestDay: !!isRestDay,
      type: type || 'gym',
      exercises: Array.isArray(exercises) ? exercises.map(ex => {
        const { name: exName, muscle, tag, restTime, note, sets, ...restExFields } = ex;
        const setsArr = Array.isArray(sets) && sets.length > 0
          ? sets.map(st => ({
              type: (st && st.type) || 'N',
              kg: st && st.kg !== undefined && st.kg !== null ? String(st.kg) : '',
              reps: st && st.reps !== undefined && st.reps !== null ? String(st.reps) : '',
            }))
          : [emptySet()];
        return {
          name: exName || '',
          muscle: muscle || '',
          tag: tag === 'Accessory' ? 'Accessory' : 'Primary',
          restTime: restTime !== undefined && restTime !== null ? String(restTime) : '90',
          note: note || '',
          sets: setsArr,
          _extra: restExFields,
        };
      }) : [],
      _extra: restSessionFields,
    };
  });
}

export function buildAndValidateCustomSessions(sessions) {
  if (sessions.length === 0) {
    return { error: 'Add at least one training day.' };
  }
  if (!sessions.some(s => !s.isRestDay)) {
    return { error: 'At least one non-rest training session is required.' };
  }

  const built = [];
  for (let i = 0; i < sessions.length; i++) {
    const s = sessions[i];
    const dayLabel = `Day ${i + 1}`;

    if (s.isRestDay) {
      built.push({
        day: dayLabel, name: s.name.trim() || 'Rest', type: 'rest', isRestDay: true, exercises: [],
        ...s._extra,
      });
      continue;
    }

    if (!s.name.trim()) return { error: `${dayLabel}: Session Name is required.` };
    if (!s.exercises || s.exercises.length === 0) {
      return { error: `${dayLabel}: at least one exercise is required for a training day.` };
    }

    const exercises = [];
    for (let j = 0; j < s.exercises.length; j++) {
      const ex = s.exercises[j];
      if (!ex.name.trim()) return { error: `${dayLabel}, exercise ${j + 1}: Name is required.` };
      if (!ex.muscle.trim()) return { error: `${dayLabel}, exercise ${j + 1}: Muscle is required.` };
      if (!ex.sets || ex.sets.length === 0) {
        return { error: `${dayLabel}, exercise ${j + 1}: at least one set is required.` };
      }

      const sets = [];
      for (let k = 0; k < ex.sets.length; k++) {
        const st = ex.sets[k];
        if (!st.type) return { error: `${dayLabel}, exercise ${j + 1}, set ${k + 1}: Type is required.` };
        if (st.reps !== '' && (!Number.isFinite(Number(st.reps)) || Number(st.reps) < 0)) {
          return { error: `${dayLabel}, exercise ${j + 1}, set ${k + 1}: Reps must be a valid number.` };
        }
        if (st.kg !== '' && (!Number.isFinite(Number(st.kg)) || Number(st.kg) < 0)) {
          return { error: `${dayLabel}, exercise ${j + 1}, set ${k + 1}: KG must be a valid non-negative number.` };
        }
        sets.push({ type: st.type, kg: st.kg, reps: st.reps });
      }

      const restTime = Number(ex.restTime);
      exercises.push({
        name: ex.name.trim(),
        muscle: ex.muscle.trim(),
        tag: ex.tag,
        restTime: Number.isInteger(restTime) && restTime >= 0 ? restTime : 90,
        note: ex.note ? ex.note.trim() : '',
        sets,
        ...ex._extra,
      });
    }

    built.push({
      day: dayLabel, name: s.name.trim(), type: s.type || 'gym', isRestDay: false, exercises,
      ...s._extra,
    });
  }
  return { sessions: built, error: null };
}

function PlanSessionsEditor({ sessions, onChange, exerciseCatalog, mode = 'official' }) {
  const isCustomMode = mode === 'custom';
  const makeEmptyExercise = () => (isCustomMode ? emptyCustomExercise() : emptyExercise());

  const updateSession = (index, changes) => {
    onChange(sessions.map((s, i) => (i === index ? { ...s, ...changes } : s)));
  };

  const toggleRestDay = (index) => {
    const session = sessions[index];
    const nowRest = !session.isRestDay;
    if (nowRest) {
      updateSession(index, isCustomMode
        ? { isRestDay: true, name: session.name || 'Rest', exercises: [] }
        : { isRestDay: true, name: session.name || 'Rest', estimatedMinutes: '0', exercises: [] });
    } else {
      updateSession(index, isCustomMode
        ? { isRestDay: false, name: session.name === 'Rest' ? '' : session.name, exercises: [makeEmptyExercise()] }
        : { isRestDay: false, name: session.name === 'Rest' ? '' : session.name, estimatedMinutes: '45', exercises: [makeEmptyExercise()] });
    }
  };

  const addDay = () => {
    const newDay = isCustomMode
      ? { name: '', isRestDay: false, type: 'gym', exercises: [makeEmptyExercise()], _extra: {} }
      : { name: '', isRestDay: false, estimatedMinutes: '45', exercises: [makeEmptyExercise()] };
    onChange([...sessions, newDay]);
  };

  const removeDay = (index) => {
    onChange(sessions.filter((_, i) => i !== index));
  };

  const updateExercise = (dayIndex, exIndex, changes) => {
    const session = sessions[dayIndex];
    const exercises = session.exercises.map((ex, i) => (i === exIndex ? { ...ex, ...changes } : ex));
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

  const removeExercise = (dayIndex, exIndex) => {
    const session = sessions[dayIndex];
    updateSession(dayIndex, { exercises: session.exercises.filter((_, i) => i !== exIndex) });
  };

  // Selecting a known exercise prefills its muscle group as a convenience —
  // plan-embedded exercises are copies (name/muscle/...), not references into
  // the `exercises` collection, so nothing is linked by ID in either mode.
  const handleExerciseNameChange = (dayIndex, exIndex, name) => {
    const match = exerciseCatalog.find(e => e.name.toLowerCase() === name.toLowerCase());
    updateExercise(dayIndex, exIndex, match ? { name, muscle: match.muscle } : { name });
  };

  const updateSet = (dayIndex, exIndex, setIndex, changes) => {
    const session = sessions[dayIndex];
    const ex = session.exercises[exIndex];
    const setsArr = ex.sets.map((st, i) => (i === setIndex ? { ...st, ...changes } : st));
    updateExercise(dayIndex, exIndex, { sets: setsArr });
  };

  const addSet = (dayIndex, exIndex) => {
    const session = sessions[dayIndex];
    const ex = session.exercises[exIndex];
    updateExercise(dayIndex, exIndex, { sets: [...ex.sets, emptySet()] });
  };

  const removeSet = (dayIndex, exIndex, setIndex) => {
    const session = sessions[dayIndex];
    const ex = session.exercises[exIndex];
    updateExercise(dayIndex, exIndex, { sets: ex.sets.filter((_, i) => i !== setIndex) });
  };

  return (
    <div>
      {sessions.map((session, dayIndex) => (
        <div key={dayIndex} className="wwa-panel" style={{ padding: 16, marginBottom: 12 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12, flexWrap: 'wrap', gap: 10 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap' }}>
              <span style={{ fontSize: 13, fontWeight: 700, color: '#111827' }}>Day {dayIndex + 1}</span>
              <input
                className="wwa-input"
                style={{ width: 200 }}
                value={session.name}
                onChange={e => updateSession(dayIndex, { name: e.target.value })}
                placeholder={session.isRestDay ? 'Rest' : 'Session name, e.g. Upper A'}
                disabled={session.isRestDay}
              />
              <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, color: '#4b5563' }}>
                <input type="checkbox" checked={session.isRestDay} onChange={() => toggleRestDay(dayIndex)} />
                Rest Day
              </label>
              {!isCustomMode && !session.isRestDay && (
                <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, color: '#4b5563' }}>
                  Est. Minutes
                  <input
                    type="number"
                    min="0"
                    className="wwa-input wwa-input-sm"
                    value={session.estimatedMinutes}
                    onChange={e => updateSession(dayIndex, { estimatedMinutes: e.target.value })}
                  />
                </label>
              )}
            </div>
            <button className="wwa-btn wwa-btn-sm wwa-btn-danger" onClick={() => removeDay(dayIndex)}>
              Remove Day
            </button>
          </div>

          {!session.isRestDay && (
            <div>
              {session.exercises.map((ex, exIndex) => (
                <div
                  key={exIndex}
                  style={{
                    padding: '10px 0',
                    borderTop: exIndex > 0 ? '1px solid #f3f4f6' : 'none',
                  }}
                >
                  {ex.isCardio ? (
                    <div style={{
                      display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(110px, 1fr))', gap: 8, alignItems: 'end',
                    }}>
                      <div>
                        <label className="wwa-field-label">Cardio Activity</label>
                        <select
                          className="wwa-select"
                          value={ex.cardioActivity}
                          onChange={e => updateExercise(dayIndex, exIndex, { cardioActivity: e.target.value })}
                        >
                          {CARDIO_ACTIVITIES.map(a => <option key={a} value={a}>{a}</option>)}
                        </select>
                      </div>
                      <div>
                        <label className="wwa-field-label">Minutes</label>
                        <input
                          type="number"
                          min="1"
                          className="wwa-input"
                          value={ex.cardioMinutes}
                          onChange={e => updateExercise(dayIndex, exIndex, { cardioMinutes: e.target.value })}
                        />
                      </div>
                      <div>
                        <label className="wwa-field-label">Preview</label>
                        <div className="wwa-input" style={{ background: '#f9fafb', color: '#6b7280', display: 'flex', alignItems: 'center' }}>
                          {ex.cardioActivity} {ex.cardioMinutes || 0}min
                        </div>
                      </div>
                      <div>
                        <button
                          className="wwa-btn wwa-btn-sm wwa-btn-danger"
                          onClick={() => removeExercise(dayIndex, exIndex)}
                          disabled={session.exercises.length === 1}
                        >
                          Remove Cardio Block
                        </button>
                      </div>
                    </div>
                  ) : (
                    <div
                      style={{
                        display: 'grid',
                        gridTemplateColumns: 'repeat(auto-fit, minmax(110px, 1fr))',
                        gap: 8,
                        alignItems: 'end',
                      }}
                    >
                      <div>
                        <label className="wwa-field-label">Exercise Name</label>
                        <input
                          className="wwa-input"
                          list="wwa-exercise-catalog"
                          value={ex.name}
                          onChange={e => handleExerciseNameChange(dayIndex, exIndex, e.target.value)}
                          placeholder="e.g. Bench Press"
                        />
                      </div>
                      <div>
                        <label className="wwa-field-label">Muscle</label>
                        <input
                          className="wwa-input"
                          list="wwa-muscle-options"
                          value={ex.muscle}
                          onChange={e => updateExercise(dayIndex, exIndex, { muscle: e.target.value })}
                          placeholder="e.g. Chest"
                        />
                      </div>
                      <div>
                        <label className="wwa-field-label">Tag</label>
                        <select
                          className="wwa-select"
                          value={ex.tag}
                          onChange={e => updateExercise(dayIndex, exIndex, { tag: e.target.value })}
                        >
                          {TAG_OPTIONS.map(t => <option key={t} value={t}>{t}</option>)}
                        </select>
                      </div>

                      {!isCustomMode && (
                        <>
                          <div>
                            <label className="wwa-field-label">Sets</label>
                            <input
                              type="number"
                              min="1"
                              className="wwa-input"
                              value={ex.sets}
                              onChange={e => updateExercise(dayIndex, exIndex, { sets: e.target.value })}
                            />
                          </div>
                          <div>
                            <label className="wwa-field-label">Reps</label>
                            <input
                              type="number"
                              min="1"
                              className="wwa-input"
                              value={ex.reps}
                              onChange={e => updateExercise(dayIndex, exIndex, { reps: e.target.value })}
                            />
                          </div>
                        </>
                      )}

                      <div>
                        <label className="wwa-field-label">Rest (sec)</label>
                        <input
                          type="number"
                          min="0"
                          className="wwa-input"
                          value={ex.restTime}
                          onChange={e => updateExercise(dayIndex, exIndex, { restTime: e.target.value })}
                        />
                      </div>

                      <div style={{ gridColumn: '1 / -1', display: 'flex', gap: 8, alignItems: 'end' }}>
                        <div style={{ flex: 1 }}>
                          <label className="wwa-field-label">Note (optional)</label>
                          <input
                            className="wwa-input"
                            value={ex.note}
                            onChange={e => updateExercise(dayIndex, exIndex, { note: e.target.value })}
                            placeholder="e.g. Keep elbows tucked"
                          />
                        </div>
                        <button
                          className="wwa-btn wwa-btn-sm wwa-btn-danger"
                          onClick={() => removeExercise(dayIndex, exIndex)}
                          disabled={session.exercises.length === 1}
                        >
                          Remove Exercise
                        </button>
                      </div>
                    </div>
                  )}

                  {isCustomMode && !ex.isCardio && (
                    <div style={{ marginTop: 10, paddingLeft: 12, borderLeft: '2px solid #f3f4f6' }}>
                      <div className="wwa-field-label" style={{ marginBottom: 6 }}>Sets</div>
                      {ex.sets.map((st, setIndex) => (
                        <div
                          key={setIndex}
                          style={{ display: 'flex', gap: 8, alignItems: 'end', marginBottom: 6 }}
                        >
                          <div style={{ width: 140 }}>
                            <select
                              className="wwa-select"
                              value={st.type}
                              onChange={e => updateSet(dayIndex, exIndex, setIndex, { type: e.target.value })}
                            >
                              {SET_TYPE_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
                            </select>
                          </div>
                          <div style={{ width: 90 }}>
                            <input
                              className="wwa-input"
                              value={st.kg}
                              onChange={e => updateSet(dayIndex, exIndex, setIndex, { kg: e.target.value })}
                              placeholder="KG"
                            />
                          </div>
                          <div style={{ width: 90 }}>
                            <input
                              className="wwa-input"
                              value={st.reps}
                              onChange={e => updateSet(dayIndex, exIndex, setIndex, { reps: e.target.value })}
                              placeholder="Reps"
                            />
                          </div>
                          <button
                            className="wwa-btn wwa-btn-sm wwa-btn-danger"
                            onClick={() => removeSet(dayIndex, exIndex, setIndex)}
                            disabled={ex.sets.length === 1}
                          >
                            Remove Set
                          </button>
                        </div>
                      ))}
                      <button
                        className="wwa-btn wwa-btn-sm wwa-btn-secondary"
                        onClick={() => addSet(dayIndex, exIndex)}
                      >
                        + Add Set
                      </button>
                    </div>
                  )}
                </div>
              ))}
              <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
                <button
                  className="wwa-btn wwa-btn-sm wwa-btn-brand-soft"
                  onClick={() => addExercise(dayIndex)}
                >
                  + Add Exercise
                </button>
                {!isCustomMode && (
                  <button
                    className="wwa-btn wwa-btn-sm wwa-btn-secondary"
                    onClick={() => addCardioBlock(dayIndex)}
                  >
                    + Add Cardio Block
                  </button>
                )}
              </div>
            </div>
          )}
        </div>
      ))}

      <datalist id="wwa-exercise-catalog">
        {exerciseCatalog.map(e => <option key={e.name} value={e.name} />)}
      </datalist>
      <datalist id="wwa-muscle-options">
        {MUSCLE_OPTIONS.map(m => <option key={m} value={m} />)}
      </datalist>

      <button className="wwa-btn wwa-btn-sm wwa-btn-secondary" onClick={addDay}>
        + Add Day
      </button>
    </div>
  );
}

export default PlanSessionsEditor;
